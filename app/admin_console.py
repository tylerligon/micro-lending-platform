"""Concurrent, session-authenticated local administration application.
Run python3 app/admin_console.py after the isolated build; see docs/Entitlements.md.
"""
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, HTTPServer
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time
from urllib.parse import urlsplit, parse_qs
from xml.etree import ElementTree as ET
from security import Sessions, hash_password, verify_password
from telemetry import Telemetry


def literal(value):
    if value is None: return 'NULL'
    if type(value) in (int, bool): return str(int(value))
    return "CONVERT(X'" + str(value).encode().hex() + "' USING utf8mb4)"


class ActionError(Exception):
    def __init__(self, code, status=403, number=1644, uncertain=False):
        self.code, self.status, self.number, self.uncertain = code, status, number, uncertain
        super().__init__(code)


def classify(number, message):
    if number == 1213: return ActionError('DB_DEADLOCK', 503, number)
    if number == 1205: return ActionError('DB_LOCK_TIMEOUT', 503, number)
    if number in (2002,2003,2006,2013): return ActionError('DB_ERROR',503,number,number in (2006,2013))
    if 'audit' in message.lower() and 'failure' in message.lower(): return ActionError('INTEGRITY_FAILURE',503,number)
    if 'version' in message: return ActionError('STALE_VERSION',409,number)
    if 'Owner' in message or 'Owned' in message: return ActionError('OWNER_REQUIRED',403,number)
    if 'Participation' in message: return ActionError('PARTICIPATION_REQUIRED',403,number)
    if 'Permission' in message: return ActionError('ROLE_REQUIRED',403,number)
    return ActionError('INVALID_INPUT' if number == 1644 else 'DB_ERROR',400 if number == 1644 else 503,number)


class Database:
    slots = threading.BoundedSemaphore(4)

    def __init__(self, actor=None, context=None, telemetry=None, parent_span=None):
        self.actor, self.context, self.telemetry = actor, context or secrets.token_hex(16), telemetry
        self.trace_id, self.parent_span = self.context, parent_span
        self.name = os.environ.get('ENTITLEMENTS_DATABASE','micro_lending_midterm_demo')
        if not re.fullmatch('[A-Za-z0-9_]+',self.name): raise ValueError('Invalid database')

    def query(self, sql):
        start, started_at = time.monotonic(), time.time()
        acquire_span, database_span = secrets.token_hex(8), secrets.token_hex(8)
        acquired = self.slots.acquire(timeout=3)
        waited = time.monotonic()-start
        if self.telemetry:
            self.telemetry.observe('db_acquire_duration_seconds',waited)
            self.telemetry.log('span',self.context,trace_id=self.trace_id,span_id=acquire_span,
                               parent_span_id=self.parent_span,name='db.acquire_slot',component='application',
                               start_time=started_at,end_time=time.time(),duration_ms=round(waited*1000,2),
                               outcome='success' if acquired else 'error')
        if not acquired:
            if self.telemetry: self.telemetry.count('db_acquire_timeouts_total')
            raise ActionError('DB_ERROR',503)
        if self.telemetry:
            self.telemetry.gauge('db_connection_slots_in_use',delta=1)
            self.telemetry.count('db_operations_total')
        match=re.search(r'CALL (sp_[a-z_]+)',sql)
        operation=match.group(1) if match else 'SELECT'
        if 'SELECT r.RoleCode,r.RoleClass' in sql: operation='permission_matrix'
        execution_start, execution_at, outcome = time.monotonic(),time.time(),'error'
        try:
            # CLI round-trip includes connection establishment and SQL execution.
            command = [os.environ.get('MYSQL_BIN','/usr/local/mysql/bin/mysql'),
                       '--login-path='+os.environ.get('MYSQL_LOGIN_PATH','cs437'),
                       '--connect-timeout=3','--xml',self.name]
            prepared = "SET @ml_context=UNHEX('"+self.context+"'); SET SESSION innodb_lock_wait_timeout=3; " + sql
            try:
                result = subprocess.run(command,input=prepared,text=True,capture_output=True,timeout=10)
            except (subprocess.TimeoutExpired, OSError) as exc:
                raise ActionError('CONNECTION_LOST',503,2013,True) from exc
            if result.returncode:
                match = re.search(r'ERROR (\d+)',result.stderr)
                raise classify(int(match.group(1)) if match else 2003,result.stderr)
            if not result.stdout.strip():
                outcome='success'
                return []
            xml = re.sub(r'<\?xml[^>]*\?>','',result.stdout)
            root = ET.fromstring('<results>'+xml+'</results>')
            rows=[{f.attrib['name']:f.text for f in row} for row in root.findall('.//row')]
            outcome='success'
            return rows
        finally:
            elapsed=time.monotonic()-execution_start
            self.slots.release()
            if self.telemetry:
                self.telemetry.gauge('db_connection_slots_in_use',delta=-1)
                self.telemetry.observe('db_client_duration_seconds',elapsed)
                if outcome=='error': self.telemetry.count('db_errors_total')
                self.telemetry.log('span',self.context,trace_id=self.trace_id,span_id=database_span,
                                   parent_span_id=self.parent_span,name='mysql.client_round_trip',component='mysql',operation=operation,
                                   start_time=execution_at,end_time=time.time(),duration_ms=round(elapsed*1000,2),outcome=outcome)
                if elapsed >= .5: self.telemetry.count('slow_database_calls')

    def matrix(self):
        return self.query(f"START TRANSACTION; CALL sp_require_permission({literal(self.actor)},NULL,'permission.manage',NULL,@r); "
            "SELECT r.RoleCode,r.RoleClass,r.Description,r.IsActive,r.RowVersion,p.PermissionCode,rp.ScopeCode,"
            "CASE r.RoleClass WHEN 'Borrower' THEN p.BorrowerScope WHEN 'Lender' THEN p.LenderScope "
            "WHEN 'Administrator' THEN p.AdministratorScope ELSE p.AuditorScope END AS SupportedScope "
            "FROM `Role` r CROSS JOIN Permission p LEFT JOIN RolePermission rp ON rp.RoleCode=r.RoleCode "
            "AND rp.PermissionCode=p.PermissionCode ORDER BY r.RoleCode,p.PermissionCode; COMMIT;")

    def workflow(self):
        return self.query(f"START TRANSACTION; CALL sp_require_permission({literal(self.actor)},NULL,'permission.manage',NULL,@r); "
            "SELECT t.ActionCode,t.FromState,t.ToState,a.PermissionCode,a.SuccessEventType,t.IsEnabled,t.RowVersion "
            "FROM RequestWorkflowTransition t JOIN RequestWorkflowAction a USING(ActionCode) ORDER BY t.ActionCode,t.FromState; COMMIT;")

    def action(self, route, data):
        name, keys = {'/role':('sp_configure_role',['code','category','description','active','version']),
                      '/permission':('sp_configure_permission',['role','permission','scope','version']),
                      '/membership':('sp_set_role',['user','role','grant']),
                      '/workflow':('sp_set_request_transition',['action','state','enabled','version'])}[route]
        values = [data[k] for k in keys]
        for key,value in zip(keys,values):
            if key in ('version','user') and value is not None and type(value) is not int: raise ValueError('Integer required')
            if key in ('active','grant','enabled') and type(value) is not bool: raise ValueError('Boolean required')
            if isinstance(value,str) and len(value)>255: raise ValueError('Value too long')
        sql = 'CALL '+name+'('+','.join(map(literal,[self.actor]+values))+');'
        parent = self.context
        for attempt in range(3):
            try: return self.query(sql)
            except ActionError as error:
                if error.number not in (1213,1205) or attempt == 2: raise
                if self.telemetry:
                    self.telemetry.count('transaction_retries')
                    self.telemetry.log('retry',parent,attempt=attempt+1,reason=error.code,attempt_context=self.context)
                self.context = hashlib.sha256((parent+':'+str(attempt+1)).encode()).hexdigest()[:32]
                time.sleep(0.02*(attempt+1))

    def failure(self, action, error):
        # SQL routines may already have recorded this context. Read first, then avoid duplicates.
        existing = self.query("CALL sp_failure_exists(UNHEX('"+self.context+"'));")
        if existing and int(existing[0]['n']): return
        self.query('CALL sp_record_failure('+','.join(map(literal,[self.actor,action,error.code]))+
                   ",UNHEX('"+self.context+"'),"+str(int(error.status>=500))+');')


class ConcurrentServer(HTTPServer):
    """Bound both running request handlers and queued requests; no thread-per-client growth."""
    def __init__(self, address, handler):
        super().__init__(address,handler)
        self.executor, self.capacity = ThreadPoolExecutor(max_workers=8), threading.BoundedSemaphore(16)

    def process_request(self, request, address):
        if not self.capacity.acquire(blocking=False):
            request.sendall(b'HTTP/1.0 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n')
            if hasattr(self,'telemetry'): self.telemetry.count('request_capacity_denials')
            self.shutdown_request(request)
            return
        self.executor.submit(self.run_request,request,address)

    def run_request(self, request, address):
        try:
            request.settimeout(10)
            self.finish_request(request,address)
        except Exception:
            pass  # Individual handler termination never logs request bodies/headers.
        finally:
            self.shutdown_request(request)
            self.capacity.release()

    def server_close(self):
        super().server_close()
        if hasattr(self,'stop_monitor'): self.stop_monitor.set()
        self.executor.shutdown(wait=True)


def make_server(port=8765, telemetry=None, sessions=None):
    telemetry = telemetry or Telemetry(os.environ.get('ENTITLEMENTS_LOG_DIR','/tmp/micro-lending-telemetry'))
    sessions = sessions or Sessions()
    telemetry.gauge('db_connection_slots_capacity',4)
    telemetry.gauge('http_worker_capacity',8)
    telemetry.gauge('db_connection_slots_in_use',0)
    telemetry.gauge('http_requests_in_progress',0)
    login_lock, login_attempts = threading.Lock(), {}
    # Used for equal-cost unknown-login verification. Never an account credential.
    dummy_hash = hash_password(secrets.token_urlsafe(24))
    secure = os.environ.get('ENTITLEMENTS_SECURE_COOKIE') == '1'

    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass

        def reply(self,status,value,kind='application/json',cookie=None):
            raw = (value if isinstance(value,str) else json.dumps(value)).encode()
            self.send_response(status)
            self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(raw)))
            self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('X-Frame-Options','DENY')
            if cookie: self.send_header('Set-Cookie',cookie)
            self.end_headers(); self.wfile.write(raw)

        def body(self):
            size = int(self.headers.get('Content-Length','0'))
            if not 0<size<=8192: raise ValueError('Invalid size')
            data = json.loads(self.rfile.read(size))
            if not isinstance(data,dict): raise ValueError('Object required')
            return data

        def session(self):
            cookie = SimpleCookie()
            try: cookie.load(self.headers.get('Cookie',''))
            except Exception: raise ActionError('NOT_AUTHENTICATED',401)
            token = cookie['session'].value if 'session' in cookie else ''
            row = sessions.get(token)
            if not row: raise ActionError('NOT_AUTHENTICATED',401)
            self.db.actor = row['user']
            current = self.db.query('CALL sp_session_user('+literal(row['user'])+');')
            if not current or current[0]['AccountStatus'] != 'Active':
                sessions.revoke(token)
                raise ActionError('ACCOUNT_INACTIVE',403)
            return token,row

        def login(self):
            # Cross-origin login CSRF is blocked; unauthenticated callers have no token yet.
            origin = self.headers.get('Origin')
            if origin and origin != os.environ.get('ENTITLEMENTS_PUBLIC_ORIGIN','http://'+self.headers.get('Host','')):
                raise ActionError('INVALID_INPUT',403)
            now, address = time.monotonic(),self.client_address[0]
            with login_lock:
                if address not in login_attempts and len(login_attempts)>=1024: raise ActionError('NOT_AUTHENTICATED',429)
                attempts = login_attempts.setdefault(address,deque(maxlen=10))
                while attempts and now-attempts[0]>=60: attempts.popleft()
                if len(attempts)>=10: raise ActionError('NOT_AUTHENTICATED',429)
                attempts.append(now)
            data = self.body()
            login,password = data.get('login'),data.get('password')
            if not isinstance(login,str) or not isinstance(password,str) or len(login)>80 or len(password)>256:
                raise ActionError('NOT_AUTHENTICATED',401)
            rows = self.db.query('CALL sp_auth_lookup('+literal(login)+');')
            valid = verify_password(password,rows[0]['PasswordHash'] if rows else dummy_hash)
            if not rows or not valid or rows[0]['AccountStatus'] != 'Active':
                raise ActionError('NOT_AUTHENTICATED',401)
            user = int(rows[0]['UserID'])
            # Rotate any previous session in this browser after successful authentication.
            old = SimpleCookie(); old.load(self.headers.get('Cookie',''))
            if 'session' in old: sessions.revoke(old['session'].value)
            token,csrf = sessions.create(user)
            self.db.actor = user
            self.reply(200,{'csrf':csrf,'user_id':user},cookie='session='+token+'; HttpOnly; SameSite=Strict; Path=/'+('; Secure' if secure else ''))

        def handle_action(self):
            if self.path == '/login' and self.command=='POST': self.login(); return
            if self.path=='/' and self.command=='GET':
                self.reply(200,Path(__file__).with_name('admin.html').read_text(),'text/html; charset=utf-8'); return
            token,row = self.session()
            if self.command=='GET':
                if self.path=='/session': self.reply(200,{'csrf':row['csrf'],'user_id':row['user']})
                elif self.path=='/matrix': self.reply(200,self.db.matrix())
                elif self.path=='/workflow': self.reply(200,self.db.workflow())
                elif self.path in ('/monitoring','/metrics','/trace'):
                    self.db.matrix() # Requires live permission.manage, not merely a session.
                    if self.path=='/metrics':
                        self.reply(200,telemetry.prometheus(),'text/plain; version=0.0.4; charset=utf-8')
                    elif self.path=='/trace':
                        context=parse_qs(urlsplit(self.target).query).get('context',[''])[0]
                        if not re.fullmatch('[0-9a-f]{32}',context): raise ActionError('INVALID_INPUT',400)
                        self.reply(200,telemetry.trace(context))
                    else:
                        snapshot=telemetry.snapshot()
                        with sessions.lock: snapshot['active_sessions']=sum(1 for s in sessions.rows.values() if sessions.clock()-s['seen']<sessions.idle and sessions.clock()-s['created']<sessions.absolute)
                        self.reply(200,snapshot)
                else: raise ActionError('INVALID_INPUT',404)
                return
            import hmac
            if not hmac.compare_digest(self.headers.get('X-CSRF-Token',''),row['csrf']):
                raise ActionError('INVALID_INPUT',403)
            if self.path=='/logout':
                sessions.revoke(token)
                self.reply(200,{},cookie='session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'); return
            if self.path not in ('/role','/permission','/membership','/workflow'): raise ActionError('INVALID_INPUT',404)
            self.reply(200,self.db.action(self.path,self.body()))

        def dispatch(self):
            start,started_at,context = time.monotonic(),time.time(),secrets.token_hex(16)
            self.target=self.path
            self.path=urlsplit(self.path).path
            span=secrets.token_hex(8)
            self.db = Database(context=context,telemetry=telemetry,parent_span=span)
            telemetry.gauge('http_requests_in_progress',delta=1)
            telemetry.count('http_requests_total')
            operation = self.path if self.path in ('/','/login','/logout','/session','/matrix','/monitoring','/metrics','/trace','/role','/permission','/membership','/workflow') else '/unknown'
            try:
                self.handle_action()
                telemetry.count('requests_success')
                if self.command=='POST' and self.path in ('/role','/permission','/membership','/workflow'): telemetry.audit_recovered()
                outcome = 'success'
            except Exception as exc:
                error = exc if isinstance(exc,ActionError) else ActionError('INVALID_INPUT',400) if isinstance(exc,(ValueError,KeyError,TypeError)) else ActionError('DB_ERROR',503)
                outcome = error.code
                telemetry.count('database_failures' if error.status>=500 else 'denials')
                try:
                    self.db.failure(operation,error)
                    telemetry.audit_recovered()
                except Exception:
                    telemetry.count('audit_failures')
                    telemetry.fallback({'time':time.time(),'context_id':context,'action':operation,
                                        'actor_id':self.db.actor,'reason':error.code,'outcome':'Failed' if error.status>=500 else 'Denied'})
                self.reply(error.status,{'error':{'code':error.code,'context_id':context,'attempt_context_id':self.db.context,
                           'retryable':error.number in (1213,1205),'outcome_uncertain':error.uncertain}})
            finally:
                elapsed=time.monotonic()-start
                telemetry.gauge('http_requests_in_progress',delta=-1)
                telemetry.observe('http_request_duration_seconds',elapsed)
                telemetry.log('request',context,span_id=span,parent_span_id=None,name=operation,action=operation,component='application',
                              start_time=started_at,end_time=time.time(),outcome=locals().get('outcome','interrupted'),duration_ms=round(elapsed*1000,2))

        do_GET = dispatch
        do_POST = dispatch

    server = ConcurrentServer(('127.0.0.1',port),Handler)
    server.telemetry,server.sessions = telemetry,sessions
    server.stop_monitor=threading.Event()
    def monitor():
        while not server.stop_monitor.wait(1):
            with telemetry.lock: telemetry.evaluate()
    threading.Thread(target=monitor,daemon=True).start()
    return server


if __name__=='__main__':
    server = make_server()
    try: server.serve_forever()
    finally: server.server_close()
