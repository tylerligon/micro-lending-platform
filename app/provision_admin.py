"""Private setup command; never exposed by the HTTP server.
Uses a separate build-administrator MySQL login path. No password in arguments/Git.
"""
import argparse
import getpass
from admin_console import Database,literal
from security import hash_password

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('user_id',type=int,help='Existing fictional administrator account')
    args=parser.parse_args()
    first=getpass.getpass('New application password: ')
    if first!=getpass.getpass('Confirm password: '):raise SystemExit('Passwords differ')
    db=Database()
    rows=db.query('SELECT u.UserID,u.PasswordHash FROM `User` u JOIN UserRole ur USING(UserID) JOIN `Role` r USING(RoleCode) '
                  "WHERE u.AccountStatus='Active' AND ur.ActiveMarker=1 AND r.IsActive=1 AND r.RoleClass='Administrator' "
                  'AND u.UserID='+literal(args.user_id)+';')
    if not rows:raise SystemExit('Existing active administrator required')
    if rows[0]['PasswordHash'].startswith('scrypt$'):
        raise SystemExit('Credentials already provisioned; this setup command does not rotate passwords')
    query = ('START TRANSACTION; CALL sp_lock_policy(); UPDATE `User` u SET PasswordHash='
        +literal(hash_password(first))+',RowVersion=RowVersion+1 WHERE UserID='+literal(args.user_id)
        +' AND PasswordHash='+literal(rows[0]['PasswordHash'])+" AND AccountStatus='Active' "
        +"AND EXISTS(SELECT 1 FROM UserRole ur JOIN `Role` r USING(RoleCode) WHERE ur.UserID=u.UserID AND ur.ActiveMarker=1 AND r.IsActive=1 AND r.RoleClass='Administrator'); "
        +"SET @changed=ROW_COUNT(); INSERT INTO AuditEvent(EventType,Outcome,ServiceActor,TechnicalAccount,SubjectType,SubjectKey,ContextID) "
        +"SELECT 'PasswordProvisioned','Success','Bootstrap',SESSION_USER(),'User',"+literal(str(args.user_id))
        +",@ml_context FROM DUAL WHERE @changed=1; SET @event=LAST_INSERT_ID(); "
        +"INSERT INTO AuditChange(AuditEventID,FieldName) SELECT @event,'PasswordHash' FROM DUAL WHERE @changed=1; "
        +"SELECT @changed AS changed; COMMIT;")
    result=db.query(query)
    if not result or result[0]['changed']!='1':raise SystemExit('Account changed; no password was provisioned')
    print('Initial application password provisioned with redacted audit. Start with a separate runtime login path.')
