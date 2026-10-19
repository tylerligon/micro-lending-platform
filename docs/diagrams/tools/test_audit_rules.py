"""Targeted design-contract regressions, called by validate_erd.py (stdlib only)."""
import copy
from audit_rules import audit_errors, project_audit_changes


def run_audit_cases(fixture, catalogue):
    passed = []
    build_identity = {'fixture_builder@localhost'}

    def verify(data):
        return audit_errors(data, catalogue, bootstrap_accounts=build_identity)

    def expect(label, condition):
        if not condition:
            raise AssertionError(label)
        passed.append(label)

    def target(data, name, predicate=lambda e: True):
        return next(e for e in data['AuditEvent'] if e['EventType'] == name and predicate(e))

    def reject(label, name, updates, code='actor_rule', predicate=lambda e: True):
        data = copy.deepcopy(fixture); e = target(data, name, predicate); e.update(updates)
        expect(label, (e['AuditEventID'], code) in verify(data))

    expect('valid fixture actor bindings and protected explanations', not verify(fixture))
    # The reviewer's exact mutation, plus a wrong role that the replacement actor actually holds.
    reject('commitment rejects Borrower role', 'CommitmentAccepted', {'ActingRoleCode': 'Borrower'})
    reject('dual-role Borrower cannot act as Borrower for commitment', 'CommitmentAccepted', {'ActorUserID': 7, 'ActingRoleCode': 'Borrower'})
    reject('same-role different lender cannot claim contribution', 'CommitmentAccepted', {'ActorUserID': 3})
    reject('same-caller different receipt cannot claim contribution', 'CommitmentAccepted', {'OperationID': 1002})
    reject('funding evaluation context must match', 'CommitmentAccepted', {'ContextID': '0'*32})
    reject('missing required human actor', 'CommitmentAccepted', {'ActorUserID': None})
    reject('missing required acting role', 'CommitmentAccepted', {'ActingRoleCode': None})
    reject('human event cannot carry service actor', 'CommitmentAccepted', {'ServiceActor': 'Activation'})
    reject('human event cannot carry service initiator', 'CommitmentAccepted', {'InitiatingUserID': 3})
    reject('assessment rejects wrong approved service', 'AssessmentCompleted', {'ServiceActor': 'Expiration'})
    reject('assessment requires service actor', 'AssessmentCompleted', {'ServiceActor': None})
    reject('manual assessment requires Administrator initiator', 'AssessmentCompleted', {'InitiatingUserID': 2})
    reject('activation requires initiating lender', 'LoanActivated', {'InitiatingUserID': None})
    reject('activation belongs to final contributor, not first contributor', 'LoanActivated', {'InitiatingUserID': 2})
    reject('activation rejects receipt from another request', 'LoanActivated', {'OperationID': 1004})
    reject('applied pledge uses final-operation initiator', 'CommitmentApplied', {'InitiatingUserID': 2})
    reject('repayment actor must own that loan', 'RepaymentPosted', {'ActorUserID': 4})
    reject('repayment must bind its own receipt', 'RepaymentPosted', {'OperationID': 2002})
    reject('profile actor must own target', 'ProfileSaved', {'ActorUserID': 4})
    reject('request actor must own target', 'RequestSaved', {'ActorUserID': 4}, predicate=lambda e:e['SubjectKey']=='101')
    reject('scheduled delinquency rejects ordinary lender initiator', 'DelinquencyChanged', {'InitiatingUserID': 2})
    reject('borrower cancellation requires ownership', 'RequestCancelled', {'ActorUserID': 7}, predicate=lambda e:e['ActingRoleCode']=='Borrower')
    reject('lender cancellation forbidden', 'RequestCancelled', {'ActorUserID': 2, 'ActingRoleCode': 'Lender'})
    reject('administrator cancellation uses administrative reason', 'RequestCancelled', {'ReasonCode':'BORROWER_CANCELLED'}, 'required_reason', lambda e:e['ActingRoleCode']=='Administrator')
    reject('bootstrap cannot log status changes', 'AccountStatusChanged', {'ActorUserID':None,'ActingRoleCode':None,'ServiceActor':'Bootstrap'})
    reject('bootstrap requires trusted build connection', 'UserCreated', {'TechnicalAccount':'app_runtime@localhost'}, predicate=lambda e:e['ServiceActor']=='Bootstrap')
    runtime_errors = audit_errors(fixture, catalogue)
    expect('runtime never accepts Bootstrap', all((e['AuditEventID'],'actor_rule') in runtime_errors for e in fixture['AuditEvent'] if e['ServiceActor']=='Bootstrap'))
    data = copy.deepcopy(fixture)
    next(r for r in data['UserRole'] if r['UserID']==2 and r['RoleCode']=='Lender')['RevokedAt']='2026-07-31T00:00:00Z'
    expect('revoked role invalid at event time', (target(data,'CommitmentAccepted')['AuditEventID'],'actor_rule') in verify(data))
    data = copy.deepcopy(fixture)
    next(r for r in data['UserRole'] if r['UserID']==2 and r['RoleCode']=='Lender')['GrantedAt']='2026-08-02T00:00:00Z'
    expect('future role grant cannot authorize earlier event', (target(data,'CommitmentAccepted')['AuditEventID'],'actor_rule') in verify(data))
    # Give another real user the right role: rejection must come from attribution, not role absence.
    for name, field, identity in [('ReviewApproved','AdministratorID',6),('NoteAppended','AdministratorID',6),('RoleGranted','GrantedByUserID',6)]:
        data=copy.deepcopy(fixture); e=target(data,name,lambda x:x['ServiceActor'] is None)
        data['UserRole'].append(dict(data['UserRole'][4],UserRoleID=99,UserID=identity))
        e['ActorUserID']=identity
        expect(name+' binds recorded '+field, (e['AuditEventID'],'actor_rule') in verify(data))
    for value, valid in [('x',True),('界'*1000,True),('界'*1001,False),('',False),('   ',False),(' trailing ',False),(None,False)]:
        data=copy.deepcopy(fixture); e=target(data,'AccountStatusChanged')
        c=next(c for c in data['AuditChange'] if c['AuditEventID']==e['AuditEventID'] and c['FieldName']=='StatusReason');c['NewValue']=value
        expect('status explanation boundary '+str(len(value) if isinstance(value,str) else 'NULL')+repr(value[:10] if isinstance(value,str) else value), not verify(data) if valid else (e['AuditEventID'],'protected_value') in verify(data))
    data=copy.deepcopy(fixture);e=target(data,'AccountStatusChanged')
    data['AuditChange']=[c for c in data['AuditChange'] if not(c['AuditEventID']==e['AuditEventID'] and c['FieldName']=='StatusReason')]
    expect('missing status explanation rejected', (e['AuditEventID'],'required_change') in verify(data))
    data=copy.deepcopy(fixture);e=target(data,'AccountStatusChanged')
    c=next(c for c in data['AuditChange'] if c['AuditEventID']==e['AuditEventID'] and c['FieldName']=='StatusReason');c['OldValue']='Previous explanation'
    expect('status explanation is new event context, not overwritten history', (e['AuditEventID'],'protected_value') in verify(data))
    reject('status change requires administrative reason code','AccountStatusChanged',{'ReasonCode':None},'required_reason')
    data=copy.deepcopy(fixture);e=target(data,'AccountStatusChanged')
    next(c for c in data['AuditChange'] if c['AuditEventID']==e['AuditEventID'] and c['FieldName']=='AccountStatus')['OldValue']='Inactive'
    expect('Inactive cannot transition straight to Restricted',(e['AuditEventID'],'status_transition') in verify(data))
    data=copy.deepcopy(fixture);e=target(data,'CommitmentAccepted')
    data['AuditChange'].append(dict(AuditEventID=e['AuditEventID'],FieldName='StatusReason',OldValue=None,NewValue='Wrong event'))
    expect('explanation is not an arbitrary event text field', (e['AuditEventID'],'field_allowlist') in verify(data))
    data=copy.deepcopy(fixture);e=target(data,'ProfileSaved')
    next(c for c in data['AuditChange'] if c['AuditEventID']==e['AuditEventID'])['NewValue']='1000.00'
    expect('private financial value cannot enter audit', (e['AuditEventID'],'private_value') in verify(data))
    admin=project_audit_changes(fixture['AuditChange'],'Administrator',catalogue)
    auditor=project_audit_changes(fixture['AuditChange'],'Auditor',catalogue)
    expect('Administrator retains all four explanations', len([c for c in admin if c['FieldName']=='StatusReason' and c['NewValue']])==4)
    expect('Auditor receives only explanation field name', all(c['OldValue'] is None and c['NewValue'] is None for c in auditor if c['FieldName']=='StatusReason'))
    expect('read projection never edits stored history', all(c['NewValue'] for c in fixture['AuditChange'] if c['FieldName']=='StatusReason'))
    for role in ('Borrower','Lender',None):
        try:
            project_audit_changes(fixture['AuditChange'],role,catalogue)
        except PermissionError:
            passed.append(str(role)+' denied general audit projection')
        else:
            raise AssertionError(str(role)+' unexpectedly read audit history')
    # Failure events may truthfully retain an unauthenticated caller or no verified role.
    for changes,valid in [({'ActorUserID':None,'ActingRoleCode':None,'ReasonCode':'NOT_AUTHENTICATED'},True),
                          ({'ActingRoleCode':None,'ReasonCode':'ROLE_REQUIRED'},True),
                          ({'ActorUserID':None},False),
                          ({'ActorUserID':None,'ActingRoleCode':None,'ServiceActor':'Expiration'},False),
                          ({'ActorUserID':None,'ActingRoleCode':None,'ServiceActor':'Activation'},True)]:
        data=copy.deepcopy(fixture);e=target(data,'AttemptRejected');e.update(changes)
        expect('failure attribution '+repr(changes), not verify(data) if valid else (e['AuditEventID'],'actor_rule') in verify(data))
    return passed
