"""Start a disposable MySQL server and exercise SQL, migration and real HTTP concurrency.
MYSQLD_BIN and MYSQL_CLIENT_BIN select installed binaries. No running/development DB is used.
"""
from concurrent.futures import ThreadPoolExecutor
from http.cookiejar import CookieJar
from pathlib import Path
import json,os,shutil,socket,subprocess,sys,tempfile,threading,time
import urllib.request,urllib.error
from unittest.mock import patch

ROOT=Path(__file__).parents[2]
sys.path.insert(0,str(ROOT/'app'))
from admin_console import make_server,Database,ActionError
from security import hash_password
from telemetry import Telemetry


def main():
    binary=os.environ.get('MYSQLD_BIN') or shutil.which('mysqld')
    client=os.environ.get('MYSQL_CLIENT_BIN') or shutil.which('mysql')
    if not binary or not client:raise SystemExit('Set MYSQLD_BIN and MYSQL_CLIENT_BIN to installed MySQL binaries')
    with tempfile.TemporaryDirectory(prefix='lending-integration-') as directory:
        directory=Path(directory);data=directory/'data';data.mkdir()
        with socket.socket() as sock:
            sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        options=['--no-defaults','--user='+__import__('getpass').getuser(),f'--basedir={Path(binary).parent.parent}',f'--datadir={data}']
        subprocess.run([binary]+options+['--initialize-insecure',f'--log-error={directory}/init.log'],check=True)
        process=subprocess.Popen([binary]+options+['--socket=','--bind-address=127.0.0.1',f'--port={port}','--mysqlx=0',f'--log-error={directory}/server.log'])
        commands=[client,'--no-defaults','--protocol=TCP','--host=127.0.0.1',f'--port={port}','--user=root','--batch','--binary-as-hex']
        def sql(text,db=None,ok=True):
            result=subprocess.run(commands+([db] if db else []),input=text,text=True,capture_output=True)
            if ok and result.returncode:raise AssertionError(result.stderr+result.stdout[-1600:])
            return result
        try:
            for _ in range(100):
                if not sql('SELECT 1',ok=False).returncode:break
                if process.poll() is not None:raise AssertionError((directory/'server.log').read_text())
                time.sleep(.1)
            else:raise AssertionError('MySQL startup timed out')
            paths=['database/schema.sql','database/02_programmability/010_views.sql','database/02_programmability/011_midterm_reports.sql','database/02_programmability/020_functions.sql','database/02_programmability/025_entitlements.sql','database/02_programmability/030_procedures.sql','database/02_programmability/031_draft_cancellation.sql','database/02_programmability/040_triggers.sql','database/02_programmability/041_request_delete_guard.sql','database/04_seed/010_reference_data.sql','database/04_seed/015_permissions.sql']
            for db in ['micro_lending_midterm_test','micro_lending_workflow_test']:
                sql(f'CREATE DATABASE {db} CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;')
                for path in paths:sql((ROOT/path).read_text(),db)
                if db=='micro_lending_midterm_test':
                    sql((ROOT/'database/04_seed/020_midterm_sample_data.sql').read_text(),db)
                    result=sql((ROOT/'tests/sql/midterm_demo.sql').read_text(),db)
                    assert '45' in result.stdout
                    sql((ROOT/'tests/sql/entitlements.sql').read_text(),db)
                    print('PASS 45 midterm checks and entitlement SQL cases',flush=True)
                else:
                    result=sql((ROOT/'tests/sql/early_workflows.sql').read_text(),db)
                    assert '87' in result.stdout
                    print('PASS 87 early-workflow checks',flush=True)
            # Upgrade from committed 1deed92, retaining existing business/audit records.
            upgrade='upgrade_test';sql('CREATE DATABASE '+upgrade+' CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;')
            for path in [p for p in paths if '025_' not in p and '015_permissions' not in p]:
                old=subprocess.run(['git','show','1deed928192f0f203e4f780e1b1a87daa957951a:'+path],cwd=ROOT,text=True,capture_output=True,check=True).stdout
                sql(old,upgrade)
            sql("INSERT INTO `User`(UserID,LoginName,DisplayName,PublicAlias,PrivateEmailCipher,PasswordHash) VALUES(1,'preserve','Preserve','preserve',X'01','test'); INSERT INTO UserRole(UserID,RoleCode) VALUES(1,'Borrower'); INSERT INTO BorrowerProfile(UserID,MonthlyIncomeCipher,ExternalObligationsCipher) VALUES(1,X'01',X'01'); CALL sp_create_loan_request(1,'Preserved Draft','300',3);",upgrade)
            snapshot='SELECT * FROM `User`; SELECT * FROM LoanRequest; SELECT * FROM UserRole; SELECT * FROM AuditEvent; SELECT * FROM AuditChange;'
            before=sql(snapshot,upgrade).stdout
            for path in ['database/migrations/020_entitlements.sql','database/02_programmability/025_entitlements.sql','database/04_seed/015_permissions.sql','database/migrations/021_replace_early_routines.sql','database/02_programmability/030_procedures.sql','database/02_programmability/031_draft_cancellation.sql']:
                sql((ROOT/path).read_text(),upgrade)
            assert sql(snapshot,upgrade).stdout==before
            print('PASS upgrade preserves users, requests, memberships and audit history',flush=True)
            db='micro_lending_midterm_test'
            # Add independently authenticated administrator; fictional seed passwords cannot log in.
            sql("CALL sp_create_user(5,'second_admin','Second Admin','second_admin',X'01','fixture-not-a-login');",db)
            second=int(sql("SELECT UserID FROM `User` WHERE LoginName='second_admin';",db).stdout.splitlines()[-1])
            sql(f"CALL sp_set_role(5,{second},'Administrator',1);",db)
            from admin_console import literal
            password='fictional integration password'
            # Exercise the real private provisioning command; no passwords in argv.
            import runpy
            setup_wrapper=directory/'setup-mysql'
            setup_wrapper.write_text('#!'+sys.executable+'\nimport os,sys\nos.execv('+repr(client)+','+repr(commands[:6])+"+[x for x in sys.argv[1:] if not x.startswith('--login-path=')])\n")
            setup_wrapper.chmod(0o700)
            for user in (5,second):
                with patch.dict(os.environ,{'MYSQL_BIN':str(setup_wrapper),'ENTITLEMENTS_DATABASE':db}),patch('getpass.getpass',return_value=password),patch.object(sys,'argv',['provision_admin.py',str(user)]):
                    runpy.run_path(str(ROOT/'app/provision_admin.py'),run_name='__main__')
            assert sql("SELECT COUNT(*) FROM AuditEvent WHERE EventType='PasswordProvisioned';",db).stdout.splitlines()[-1]=='2'
            first_login=sql('SELECT LoginName FROM `User` WHERE UserID=5;',db).stdout.splitlines()[-1]
            sql("CREATE USER 'console_operator'@'localhost';",db)
            sql((ROOT/'database/entitlements_console_grants.sql').read_text().replace('micro_lending_midterm_demo',db),db)
            runtime_commands=[client,'--no-defaults','--protocol=TCP','--host=127.0.0.1',f'--port={port}','--user=console_operator']
            for denied in ['UPDATE `User` SET AccountStatus=AccountStatus;','SELECT * FROM AuditEvent;','CALL sp_lock_policy();']:
                result=subprocess.run(runtime_commands+[db],input=denied,text=True,capture_output=True)
                assert result.returncode, 'Runtime privilege bypass'
            print('PASS runtime cannot write base users, read raw audit or execute internal lock helper',flush=True)
            wrapper=directory/'mysql-wrapper'
            wrapper.write_text('#!'+sys.executable+'\nimport os,sys\nos.execv('+repr(client)+','+repr(runtime_commands)+"+[x for x in sys.argv[1:] if not x.startswith('--login-path=')])\n")
            # commands[:7] includes --batch; XML option overrides batch formatting.
            wrapper.chmod(0o700)
            with patch.dict(os.environ,{'MYSQL_BIN':str(wrapper),'ENTITLEMENTS_DATABASE':db}):
                telemetry=Telemetry(directory/'telemetry')
                server=make_server(0,telemetry=telemetry)
                thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
                url='http://127.0.0.1:'+str(server.server_port)
                def browser():return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
                def http(opener,path,payload=None,csrf=None):
                    headers={'Content-Type':'application/json'}
                    if csrf:headers['X-CSRF-Token']=csrf
                    request=urllib.request.Request(url+path,data=json.dumps(payload).encode() if payload is not None else None,headers=headers)
                    try:
                        response=opener.open(request,timeout=15);return response.status,json.loads(response.read())
                    except urllib.error.HTTPError as error:return error.code,json.loads(error.read())
                try:
                    a,b,unknown=browser(),browser(),browser()
                    assert http(unknown,'/matrix')[0]==401
                    assert http(unknown,'/login',dict(login=first_login,password='wrong'))[0]==401
                    code,session_a=http(a,'/login',dict(login=first_login,password=password));assert code==200
                    code,session_b=http(b,'/login',dict(login='second_admin',password=password));assert code==200
                    ca,cb=session_a['csrf'],session_b['csrf']
                    assert session_a['user_id']!=session_b['user_id']
                    assert http(a,'/matrix')[0]==200 and http(b,'/matrix')[0]==200
                    assert http(a,'/role',dict(code='NoCSRF'))[0]==403
                    def create(opener,csrf,role):
                        return http(opener,'/role',dict(code=role,category='Borrower',description='Concurrent test',active=True,version=None),csrf)
                    with ThreadPoolExecutor(2) as pool:
                        results=list(pool.map(lambda x:create(*x),[(a,ca,'ParallelA'),(b,cb,'ParallelB')]))
                    assert [r[0] for r in results]==[200,200],results
                    assert create(a,ca,'Conflict')[0]==200
                    def grant(args):
                        opener,csrf,permission=args
                        return http(opener,'/permission',dict(role='Conflict',permission=permission,scope='OWN',version=0),csrf)
                    with ThreadPoolExecutor(2) as pool:
                        results=list(pool.map(grant,[(a,ca,'request.cancel'),(b,cb,'request.read')]))
                    assert sorted(r[0] for r in results)==[200,409],results
                    events=sql("SELECT COUNT(DISTINCT ActorUserID) FROM AuditEvent WHERE EventType='RoleConfigured' AND SubjectKey IN('ParallelA','ParallelB');",db)
                    assert events.stdout.splitlines()[-1]=='2'
                    # Revocation is effective for an already signed-in administrator.
                    version=int(sql("SELECT RowVersion FROM `Role` WHERE RoleCode='Administrator';",db).stdout.splitlines()[-1])
                    assert http(b,'/permission',dict(role='Administrator',permission='role.assign',scope=None,version=version),cb)[0]==200
                    status,denied=http(a,'/membership',dict(user=7,role='Borrower',grant=True),ca)
                    assert status==403,(status,denied)
                    context=denied['error']['attempt_context_id']
                    assert sql("SELECT COUNT(*) FROM AuditEvent WHERE ContextID=UNHEX('"+context+"') AND Outcome='Denied';",db).stdout.splitlines()[-1]=='1'
                    assert http(b,'/permission',dict(role='Administrator',permission='role.assign',scope='ALL',version=version+1),cb)[0]==200
                    # A real failed MySQL connection produces fallback evidence and a local alert.
                    bad=directory/'unavailable-mysql'
                    bad.write_text('#!'+sys.executable+'\nimport os,sys\nos.execv('+repr(client)+','+repr([client,'--no-defaults','--protocol=TCP','--host=127.0.0.1','--port=1','--user=console_operator'])+"+[x for x in sys.argv[1:] if not x.startswith('--login-path=')])\n")
                    bad.chmod(0o700)
                    with patch.dict(os.environ,{'MYSQL_BIN':str(bad)}):
                        status,failure=http(a,'/matrix')
                        assert status==503,(status,failure)
                    assert (directory/'telemetry/audit-fallback.jsonl').exists()
                    assert 'audit_database_unavailable' in telemetry.snapshot()['active_alerts']
                    assert create(a,ca,'Recovery')[0]==200
                    assert not telemetry.audit_broken
                    assert http(a,'/monitoring')[0]==200
                    print('PASS real connection failure, local fallback alert, recovery write and protected monitoring',flush=True)
                    # PDF deliverables: inspect real metrics and a correlated HTTP/database trace.
                    exported=a.open(url+'/metrics').read().decode()
                    assert '# TYPE db_operations_total counter' in exported
                    assert '# TYPE db_client_duration_seconds histogram' in exported
                    assert '# TYPE db_connection_slots_in_use gauge' in exported
                    records=[json.loads(line) for line in (directory/'telemetry/operations.jsonl').read_text().splitlines()]
                    root_span=next(r for r in records if r['kind']=='request' and r.get('action')=='/matrix' and r.get('outcome')=='success')
                    status,trace=http(a,'/trace?context='+root_span['trace_id'])
                    assert status==200
                    assert any(s.get('component')=='mysql' and s.get('parent_span_id')==root_span['span_id'] for s in trace)
                    assert http(unknown,'/metrics')[0]==401 and http(unknown,'/trace?context='+root_span['trace_id'])[0]==401
                    sys.path.insert(0,str(ROOT/'tests/observability'))
                    from diagnose import run as diagnose
                    evidence=diagnose(telemetry)
                    evidence['mysql_version']=sql('SELECT VERSION();').stdout.splitlines()[-1]
                    report_path=os.environ.get('OBSERVABILITY_REPORT')
                    if report_path:
                        report_path=Path(report_path);report_path.parent.mkdir(parents=True,exist_ok=True)
                        report_path.write_text(json.dumps(evidence,indent=2)+'\n')
                    print('PASS PDF metrics, trace links and measured remediation: p50 %.2f -> %.2f ms; p95 %.2f -> %.2f ms' %
                          (evidence['before']['p50_ms'],evidence['after']['p50_ms'],evidence['before']['p95_ms'],evidence['after']['p95_ms']),flush=True)
                    # Two attempts to remove each other cannot remove both administrators.
                    with ThreadPoolExecutor(2) as pool:
                        results=list(pool.map(lambda x:http(x[0],'/membership',dict(user=x[2],role='Administrator',grant=False),x[1]),[(a,ca,second),(b,cb,5)]))
                    assert sorted(r[0] for r in results)==[200,403],results
                    assert sql("SELECT COUNT(*) FROM UserRole WHERE RoleCode='Administrator' AND ActiveMarker=1;",db).stdout.splitlines()[-1]=='1'
                    # Logout is session-local even if another account's role was revoked.
                    assert http(a,'/logout',{},ca)[0]==200
                    assert http(a,'/session')[0]==401
                    assert http(b,'/session')[0]==200
                    # Simulate audit persistence outage at the gateway boundary.
                    with patch.object(Database,'failure',side_effect=ActionError('DB_ERROR',503)):
                        assert http(unknown,'/matrix')[0]==401
                    assert (directory/'telemetry/audit-fallback.jsonl').exists()
                    assert 'audit_database_unavailable' in telemetry.snapshot()['active_alerts']
                    records=''.join(p.read_text() for p in (directory/'telemetry').glob('*.jsonl'))
                    assert password not in records and ca not in records and cb not in records
                    print('PASS two HTTP sessions, independent audit actors, concurrent edits, revocation, last-admin race, logout, denial deduplication, audit fallback and redaction',flush=True)
                finally:
                    server.shutdown();server.server_close();thread.join(timeout=5)
            print('ALL EXPANDED INTEGRATION CHECKS PASSED',flush=True)
        finally:
            process.terminate();process.wait(timeout=15)

if __name__=='__main__':main()
