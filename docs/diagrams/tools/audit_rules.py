"""Reference audit-contract checks for design fixtures; not database authorization.

The catalogue declares alternatives (human OR service), not independently mixable
role/service lists. Binding checks follow actual subject/receipt relationships.
Bootstrap trust is an explicit verifier input, never a flag taken from an event.
"""
from datetime import datetime
import json


def audit_errors(data, catalogue, *, bootstrap_accounts=()):
    errors = []
    specs = {s['name']: s for s in catalogue['events']}
    key_fields = {name: key.split('/') for name, key in catalogue['subjects'].items() if name != 'Attempt'}
    rows = {name: {'/'.join(str(r[k]) for k in keys): r for r in data[name]}
            for name, keys in key_fields.items()}
    users = {r['UserID']: r for r in data['User']}
    requests = {r['RequestID']: r for r in data['LoanRequest']}
    loans = {r['LoanID']: r for r in data['Loan']}
    receipts = {r['OperationID']: r for r in data['OperationReceipt']}
    evaluations = {r['EvaluationID']: r for r in data['RequestEvaluation']}
    by_event = {e['AuditEventID']: e for e in data['AuditEvent']}
    changes = {}
    for c in data['AuditChange']:
        fields = changes.setdefault(c['AuditEventID'], {})
        if c['FieldName'] in fields:
            errors.append((c['AuditEventID'], 'duplicate_change'))
        fields[c['FieldName']] = c
        ev = by_event.get(c['AuditEventID'])
        if not ev or c['FieldName'] not in specs.get(ev['EventType'], {}).get('fields', []):
            errors.append((c['AuditEventID'], 'field_allowlist'))
        if c['FieldName'] in catalogue['redacted_fields'] and (c['OldValue'] is not None or c['NewValue'] is not None):
            errors.append((c['AuditEventID'], 'private_value'))

    def active_role(user, role, when):
        if user not in users:
            return False
        t = datetime.fromisoformat(when.replace('Z', '+00:00'))
        return any(r['UserID'] == user and r['RoleCode'] == role
                   and datetime.fromisoformat(r['GrantedAt'].replace('Z', '+00:00')) <= t
                   and (r['RevokedAt'] is None or t < datetime.fromisoformat(r['RevokedAt'].replace('Z', '+00:00')))
                   for r in data['UserRole'])

    def repayment_origin(e, loan_id):
        op = receipts.get(e['OperationID'])
        payment = next((r for r in data['Repayment'] if r['OperationID'] == e['OperationID']), None)
        if not op or not payment or payment['LoanID'] != loan_id or op['ActionCode'] != 'PostRepayment':
            return False
        return op['CallerUserID'] == requests[loans[loan_id]['RequestID']]['BorrowerID']

    def binding_matches(rule, e, subject):
        binding = rule.get('binding', 'none')
        actor = e['ActorUserID']; initiator = e['InitiatingUserID']
        op = receipts.get(e['OperationID'])
        if binding == 'none':
            return e['OperationID'] is None
        if binding in ('fresh_build', 'bootstrap_grant'):
            return (e['EventType'] in catalogue['bootstrap_contract']['events']
                    and e['TechnicalAccount'] in bootstrap_accounts and e['OperationID'] is None
                    and (binding != 'bootstrap_grant' or subject['GrantedByUserID'] is None))
        if binding == 'grantor':
            return actor == subject['GrantedByUserID'] and e['OperationID'] is None
        if binding == 'revoker':
            return actor == subject['RevokedByUserID'] and subject['RevokedAt'] is not None and e['OperationID'] is None
        if binding == 'profile_owner':
            return actor == subject['UserID'] and e['OperationID'] is None
        if binding == 'request_owner':
            return actor == subject['BorrowerID'] and e['OperationID'] is None
        if binding == 'reviewer':
            decision = 'Approve' if e['EventType'] == 'ReviewApproved' else 'Reject'
            return (actor == subject['AdministratorID'] and subject['EvaluationKind'] == 'Review'
                    and subject['Decision'] == decision and e['ContextID'] == subject['ContextID']
                    and e['OperationID'] is None)
        if binding == 'submission_evaluation':
            return (subject['EvaluationKind'] == 'Submission' and subject['CompletedAt'] is not None
                    and e['OperationID'] is None)
        if binding == 'commitment_caller':
            return (op is not None and actor == op['CallerUserID'] and op['ActionCode'] == 'CommitFunding'
                    and e['OperationID'] == subject['OperationID']
                    and e['ContextID'] == evaluations[subject['EvaluationID']]['ContextID'])
        if binding == 'repayment_caller':
            return (e['OperationID'] == subject['OperationID'] and repayment_origin(e, subject['LoanID'])
                    and actor == op['CallerUserID'])
        if binding == 'note_author':
            return actor == subject['AdministratorID'] and e['OperationID'] is None
        if binding == 'activation_operation':
            request_id = subject['RequestID']
            loan = next((l for l in data['Loan'] if l['RequestID'] == request_id), None)
            final = next((c for c in data['FundingCommitment'] if c['OperationID'] == e['OperationID']), None)
            if not op or not loan or not final or final['RequestID'] != request_id or op['ActionCode'] != 'CommitFunding':
                return False
            try:
                original_result = json.loads(op['ReceiptSnapshot'].split('\n', 1)[1])
            except (ValueError, IndexError):
                return False
            return (str(original_result.get('loanID')) == str(loan['LoanID'])
                    and original_result.get('commitmentState') == 'Applied'
                    and e['ContextID'] == evaluations[final['EvaluationID']]['ContextID']
                    and e['OccurredAt'] == loan['ActivatedAt'])
        if binding == 'release_parent':
            parents = [p for p in data['AuditEvent'] if p['EventType'] in ('RequestCancelled', 'RequestExpired')
                       and p['SubjectKey'] == str(subject['RequestID']) and p['ContextID'] == e['ContextID']
                       and p['OccurredAt'] == e['OccurredAt'] and p['Outcome'] == 'Success']
            return (len(parents) == 1 and initiator == (parents[0]['ActorUserID'] if parents[0]['ServiceActor'] is None
                                                       else parents[0]['InitiatingUserID'])
                    and e['OperationID'] is None)
        if binding == 'repayment_operation':
            return (repayment_origin(e, subject['LoanID'])
                    and any(p['EventType'] == 'RepaymentPosted' and p['OperationID'] == e['OperationID']
                            and p['ContextID'] == e['ContextID'] and p['OccurredAt'] == e['OccurredAt']
                            for p in data['AuditEvent']))
        if binding == 'no_operation':
            return e['OperationID'] is None
        if binding == 'failure_context':
            actions = catalogue['service_failure_actions'][e['ServiceActor']]
            return e['OperationID'] is None and e['SubjectKey'].split('/')[0] in actions
        return False  # Unknown contract rules fail closed.

    def actor_matches(rule, e, subject):
        actor = e['ActorUserID']; role = e['ActingRoleCode']; service = e['ServiceActor']; initiator = e['InitiatingUserID']
        kind = rule['kind']
        if kind == 'human':
            return (actor is not None and role == rule['role'] and active_role(actor, role, e['OccurredAt'])
                    and service is None and initiator is None and binding_matches(rule, e, subject))
        if kind == 'verified_failure':
            return (actor in users and service is None and initiator is None
                    and (role is None or active_role(actor, role, e['OccurredAt'])))
        if kind == 'anonymous':
            return actor is None and role is None and service is None and initiator is None
        if kind != 'service' or service != rule['service'] or actor is not None or role is not None:
            return False
        mode = rule['initiator']
        op = receipts.get(e['OperationID'])
        initiator_ok = {
            'none': initiator is None,
            'optional_administrator': initiator is None or active_role(initiator, 'Administrator', e['OccurredAt']),
            'optional_verified_user': initiator is None or initiator in users,
            'funding_caller': op is not None and initiator == op['CallerUserID'] and active_role(initiator, 'Lender', e['OccurredAt']),
            'repayment_caller': op is not None and initiator == op['CallerUserID'] and active_role(initiator, 'Borrower', e['OccurredAt']),
            'parent_initiator': initiator is None or initiator in users,
        }.get(mode, False)
        return initiator_ok and binding_matches(rule, e, subject)

    for e in data['AuditEvent']:
        eid = e['AuditEventID']; spec = specs.get(e['EventType'])
        if not spec:
            errors.append((eid, 'unknown_event')); continue
        if (e['SubjectType'] != spec['subject'] or e['Outcome'] != spec['outcome']
                or (e['ReasonCode'] is not None and e['ReasonCode'] not in catalogue['reasons'])):
            errors.append((eid, 'event_vocabulary'))
        subject = rows.get(spec['subject'], {}).get(e['SubjectKey'])
        if spec['subject'] != 'Attempt' and subject is None:
            errors.append((eid, 'subject_missing')); continue
        if not any(actor_matches(rule, e, subject) for rule in spec['actors']):
            errors.append((eid, 'actor_rule'))
        if e['Outcome'] != 'Success' and (e['ReasonCode'] is None or e['OperationID'] is not None):
            errors.append((eid, 'failure_context'))
        reason = spec.get('required_reason')
        if e['EventType'] == 'RequestCancelled':
            reason = 'ADMIN_DECISION' if e['ActingRoleCode'] == 'Administrator' else 'BORROWER_CANCELLED'
        if reason and e['ReasonCode'] != reason:
            errors.append((eid, 'required_reason'))
        fields = changes.get(eid, {})
        if not set(spec.get('required_fields', [])) <= fields.keys():
            errors.append((eid, 'required_change'))
        if e['EventType'] == 'AccountStatusChanged':
            status = fields.get('AccountStatus', {})
            if (status.get('OldValue'), status.get('NewValue')) not in {
                    ('Active', 'Restricted'), ('Restricted', 'Active'), ('Active', 'Inactive'),
                    ('Restricted', 'Inactive'), ('Inactive', 'Active')}:
                errors.append((eid, 'status_transition'))
        for name, constraint in catalogue['protected_fields'].items():
            if name not in fields:
                continue
            c = fields[name]; value = c['NewValue']
            if (e['EventType'] != constraint['event'] or c['OldValue'] != constraint['old_value']
                    or not isinstance(value, str) or not constraint['min_characters'] <= len(value) <= constraint['max_characters']
                    or (constraint['trimmed'] and (value != value.strip() or not value))):
                errors.append((eid, 'protected_value'))
    return errors


def project_audit_changes(changes, role, catalogue):
    """Expected read projection only; real routines must obtain the verified role."""
    if role not in ('Administrator', 'Auditor'):
        raise PermissionError('General audit access requires Administrator or Auditor')
    result = []
    for change in changes:
        c = dict(change)
        protected = catalogue['protected_fields'].get(c['FieldName'])
        if c['FieldName'] in catalogue['redacted_fields'] or (protected and role not in protected['read_roles']):
            c['OldValue'] = c['NewValue'] = None
        result.append(c)
    return result
