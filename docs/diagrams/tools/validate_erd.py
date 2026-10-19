"""Design verifier: standard library only. This does NOT execute MySQL or an API.

Checks the dictionary, the editable XML, its direct SVG exports, and concrete
complete fixture specifications. Business-rule checks are reference calculations, not tests
of an implemented application. Failing any check exits nonzero.
"""
from pathlib import Path
from decimal import Decimal as D
from datetime import date, datetime, timezone
import calendar, copy, hashlib, importlib.util, json, re, tempfile
import xml.etree.ElementTree as ET
from audit_rules import audit_errors
from test_audit_rules import run_audit_cases

ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[1]
m=json.loads((ROOT/'model.json').read_text());f=json.loads((ROOT/'sample-records.json').read_text())
entities={e['name']:e for e in m['entities']};checks=[]
def check(label,condition):
 if not condition:raise AssertionError(label)
 checks.append(label)
def tup(row,names):return tuple(row.get(n) for n in names)
def pk(e):return e['pk'].strip('()').replace(' ','').split(',')
UK={'User':[['LoginName'],['PublicAlias']], 'UserRole':[['UserID','RoleCode','ActiveMarker']],
 'RequestEvaluation':[['RequestID','EvaluationKind','AttemptNumber'],['RequestID','FinalReviewMarker']],
 'OperationReceipt':[['CallerUserID','OperationReference']], 'FundingCommitment':[['OperationID'],['EvaluationID']],
 'Loan':[['RequestID']], 'Installment':[['LoanID','DueDate']], 'Repayment':[['OperationID']]}

check('15 application entities',len(entities)==15)
check('114 application attributes',sum(len(e['columns']) for e in entities.values())==114)
check('27 application FKs',len(m['relationships'])==27)
check('Operational tables excluded',len(m['operational_entities'])==2 and not any(n.startswith('build_admin') for n in entities))
check('Removed tables absent',not set(['PolicyVersion','PolicyInstallmentOption','ControlledValue','ExposureComponent','RequestSnapshot','EligibilityCondition','Assessment','ReviewDecision']) & entities.keys())
for e in entities.values():
 cols={c['name']:c for c in e['columns']}
 check(e['name']+' unique column names',len(cols)==len(e['columns']))
 check(e['name']+' declared PK nonnull',all(c in cols and cols[c]['nullable']=='No' for c in pk(e)))
 for c in cols.values():check(e['name']+'.'+c['name']+' complete definition',all(c.get(k) for k in ['name','type','nullable','key','purpose']))
for rel in m['relationships']:
 a={c['name']:c for c in entities[rel['child']]['columns']};b={c['name']:c for c in entities[rel['parent']]['columns']}
 check(rel['id']+' FK arity/type',len(rel['columns'])==len(rel['references']) and all(a[x]['type']==b[y]['type'] for x,y in zip(rel['columns'],rel['references'])))
 check(rel['id']+' references key',rel['references'] in [pk(entities[rel['parent']])]+UK.get(rel['parent'],[]))
 check(rel['id']+' FK optionality',('0..1' if any(a[x]['nullable']=='Yes' for x in rel['columns']) else '1')==rel['parents_per_child'])

source=ROOT/'Micro_Lending_ERD.drawio';raw=source.read_bytes();mx=ET.fromstring(raw)
check('one source with three pages',len(mx.findall('diagram'))==3 and source.name=='Micro_Lending_ERD.drawio')
allids=set(); seenfields=set(); seenfks=set()
svg_ns={'s':'http://www.w3.org/2000/svg'}
for page,p in zip(mx.findall('diagram'),m['pages']):
 check('page identity '+p['id'],page.get('id')==p['id'])
 cells={c.get('id'):c for c in page.findall('mxGraphModel/root/mxCell')}
 check(p['id']+' unique cell IDs',len(cells)==len(page.findall('mxGraphModel/root/mxCell')))
 svg=ET.parse(ROOT/p['export']).getroot()
 check(p['id']+' export source hash',svg.get('data-source-sha256')==hashlib.sha256(raw).hexdigest())
 check(p['id']+' export page',svg.get('data-page-id')==p['id'])
 groups={g.get('data-cell-id'):g for g in svg.findall('s:g',svg_ns)}
 for id,c in cells.items():
  if c.find('mxGeometry') is None:continue
  check(id+' exported',id in groups)
  value=c.get('value','')
  if value:
   actual='\n'.join(''.join(t.itertext()) for t in groups[id].findall('s:text/s:tspan',svg_ns))
   check(id+' text agrees',actual==value)
  if c.get('edge')=='1' and '.fk.' in id:
   check(id+' attached endpoints',c.get('source') in cells and c.get('target') in cells)
   seenfks.add(id.split('.fk.')[1])
 for name in p.get('entities',[]):
  for c in entities[name]['columns']:
   id=p['id']+'.'+name+'.'+c['name']
   check(id+' complete typed row',cells[id+'.name'].get('value')==c['name'] and cells[id+'.type'].get('value')==c['type'])
   check(id+' shown once',(name,c['name']) not in seenfields);seenfields.add((name,c['name']))
check('all FKs rendered',seenfks=={r['id'] for r in m['relationships']})
check('all attributes rendered once',len(seenfields)==114)
# Re-export the actual source into a temporary directory and compare every byte.
spec=importlib.util.spec_from_file_location('export_svg',ROOT/'tools/export_svg.py');exporter=importlib.util.module_from_spec(spec);spec.loader.exec_module(exporter)
with tempfile.TemporaryDirectory() as td:
 dest=Path(td)/source.name;dest.write_bytes(raw);(dest.parent/'model.json').write_bytes((ROOT/'model.json').read_bytes())
 for p in exporter.export(dest):check(p.name+' deterministic source export',p.read_bytes()==(ROOT/p.name).read_bytes())

def structural_errors(data):
 errors=[]
 for name,e in entities.items():
  for kind,keys in [('PK',pk(e))]+[('UNIQUE',x) for x in UK.get(name,[])]:
   seen=set()
   for row in data.get(name,[]):
    key=tup(row,keys)
    if None in key:
     if kind=='PK':errors.append(name+' missing PK')
     continue # MySQL UNIQUE permits NULL; projection-only optional columns.
    if key in seen:errors.append(name+' duplicate '+kind)
    seen.add(key)
 for r in m['relationships']:
  parents={tup(x,r['references']) for x in data.get(r['parent'],[])}
  for row in data.get(r['child'],[]):
   key=tup(row,r['columns'])
   if None in key:
    if r['parents_per_child']=='1':errors.append(r['id']+' missing required FK')
   elif key not in parents:errors.append(r['id']+' orphan FK')
 return errors
check('all 27 FKs and keys in complete fixture',not structural_errors(f))
bad=copy.deepcopy(f);bad['Loan'].append(dict(bad['Loan'][0],LoanID=999));check('second loan for same request rejected structurally',bool(structural_errors(bad)))
bad=copy.deepcopy(f);bad['FundingCommitment'][0]['RequestID']=999;check('orphan contribution rejected structurally',bool(structural_errors(bad)))
bad=copy.deepcopy(f);bad['UserRole'].append(dict(bad['UserRole'][0],UserRoleID=99));check('duplicate active role rejected structurally',bool(structural_errors(bad)))
bad=copy.deepcopy(f);bad['UserRole'].append(dict(bad['UserRole'][0],UserRoleID=99,RevokedAt='2026-08-01T00:00:00Z',RevokedByUserID=5,ActiveMarker=None));check('revoked role history allowed',not structural_errors(bad))
bad=copy.deepcopy(f);review=next(e for e in bad['RequestEvaluation'] if e['EvaluationKind']=='Review');bad['RequestEvaluation'].append(dict(review,EvaluationID=999,AttemptNumber=99));check('second final review rejected structurally',bool(structural_errors(bad)))
bad=copy.deepcopy(f);bad['RequestEvaluation'].append(dict(review,EvaluationID=999,AttemptNumber=99,Decision=None,Reason=None,DecidedAt=None,FinalReviewMarker=None));check('separate nonfinal review attempt allowed',not structural_errors(bad))

requests={x['RequestID']:x for x in f['LoanRequest']};loans={x['LoanID']:x for x in f['Loan']};receipts={x['OperationID']:x for x in f['OperationReceipt']};evals={x['EvaluationID']:x for x in f['RequestEvaluation']}
payments={(x['LoanID'],x['RepaymentNumber']):x for x in f['Repayment']}
def lender(c):return receipts[c['OperationID']]['CallerUserID']
for c in f['FundingCommitment']:
 ev=evals[c['EvaluationID']];op=receipts[c['OperationID']]
 check('commitment '+str(c['CommitmentID'])+' linked intent',op['ActionCode']=='CommitFunding' and ev['RequestID']==c['RequestID'] and ev['EvaluationKind']=='Funding' and ev['Result']=='Pass')
for p in f['Repayment']:
 op=receipts[p['OperationID']]
 check('repayment owner '+str(p['OperationID']),op['ActionCode']=='PostRepayment' and op['CallerUserID']==requests[loans[p['LoanID']]['RequestID']]['BorrowerID'])
for op in receipts.values():check('one event per receipt '+str(op['OperationID']),sum(x['OperationID']==op['OperationID'] for x in f['FundingCommitment']+f['Repayment'])==1)
check('same borrower has two active loans',sum(requests[l['RequestID']]['BorrowerID']==1 and l['LoanState']=='Active' for l in loans.values())==2)
check('same lender repeated contributions',[(x['Amount']) for x in f['FundingCommitment'] if x['RequestID']==101 and lender(x)==2]==['300.00','200.00'])
for loan in loans.values():
 q=requests[loan['RequestID']];schedule=[i for i in f['Installment'] if i['LoanID']==loan['LoanID']]
 check('funding equals principal '+str(loan['LoanID']),sum(D(x['Amount']) for x in f['FundingCommitment'] if x['RequestID']==q['RequestID'] and x['CommitmentState']=='Applied')==D(q['Principal']))
 check('complete schedule '+str(loan['LoanID']),len(schedule)==q['InstallmentCount'] and sum(D(i['ScheduledPrincipal']) for i in schedule)==D(q['Principal']))
check('partly funded request has no loan',not any(x['RequestID']==103 for x in loans.values()))
for key,p in payments.items():check('payment allocations reconcile '+str(key),sum(D(a['AllocatedPrincipal']) for a in f['RepaymentAllocation'] if (a['LoanID'],a['RepaymentNumber'])==key)==D(p['Amount']))
balances={}
today=date.fromisoformat(f['evaluation_date'])
for loan in loans.values():
 unpaid=[];paid=D(0)
 for i in f['Installment']:
  if i['LoanID']!=loan['LoanID']:continue
  amount=sum(D(a['AllocatedPrincipal']) for a in f['RepaymentAllocation'] if (a['LoanID'],a['InstallmentNumber'])==(i['LoanID'],i['InstallmentNumber']))
  remaining=D(i['ScheduledPrincipal'])-amount;check('installment cap '+str((i['LoanID'],i['InstallmentNumber'])),remaining>=0);paid+=amount
  if remaining:unpaid.append((date.fromisoformat(i['DueDate']),remaining))
 overdue=[(due,amount) for due,amount in unpaid if due<today]
 balances[loan['LoanID']]=dict(repaid=paid,outstanding=sum((a for _,a in unpaid),D(0)),overdue=sum((a for _,a in overdue),D(0)),days_past_due=(today-min(d for d,_ in overdue)).days if overdue else 0)
 expected=f['calculation_examples']['expected_loans'][str(loan['LoanID'])]
 check('independent loan totals '+str(loan['LoanID']),all(balances[loan['LoanID']][k]==(v if isinstance(v,int) else D(v)) for k,v in expected.items()))
def visible_loans(user):return sorted(l['LoanID'] for l in loans.values() if any(c['RequestID']==l['RequestID'] and c['CommitmentState']=='Applied' and lender(c)==user for c in f['FundingCommitment']))
for user,expected in f['calculation_examples']['expected_lender_loans'].items():check('participation scope '+user,visible_loans(int(user))==expected)
check('lender totals do not multiply with repeat contributions',sum(balances[k]['outstanding'] for k in visible_loans(2))==D('550'))
check('borrower outstanding sum counts two loans once',sum(b['outstanding'] for b in balances.values())==D('750'))

def retry(caller,ref,action,target,amount):
 matches=[o for o in receipts.values() if o['CallerUserID']==caller and o['OperationReference']==ref]
 if not matches:return None
 o=matches[0];events=f['FundingCommitment'] if o['ActionCode']=='CommitFunding' else f['Repayment'];event=next(e for e in events if e['OperationID']==o['OperationID']);original_target=event['RequestID'] if o['ActionCode']=='CommitFunding' else event['LoanID']
 if (action,target,D(amount))!=(o['ActionCode'],original_target,D(event['Amount'])):raise ValueError('Conflicting operation reference')
 return o['ReceiptSnapshot']
check('exact retry after funding returns original',retry(2,'fund-201','CommitFunding',101,'300.00')==receipts[1001]['ReceiptSnapshot'])
try:retry(2,'fund-201','CommitFunding',101,'301.00');raise AssertionError('conflict not raised')
except ValueError:check('changed contents conflict',True)
check('new reference is a new action',retry(2,'new-ref','CommitFunding',103,'100.00') is None)
check('operation reference is caller scoped',retry(3,'fund-201','CommitFunding',101,'300.00') is None)

def largest(principal,n):
 cents=int(D(principal)*100);base=cents//n;return D(cents-base*(n-1))/100
def assess(income,external,other,proposed,no_delinquency=True):return D(income)>=D(external)+D(other)+D(proposed) and no_delinquency
check('affordability exact boundary',assess('300','100','0','200') and not assess('299.99','100','0','200'))
check('delinquency independently blocks credit',not assess('1000','100','0','200',False))
for principal,expected in [('1200',[True,False]),('900',[True,True])]:
 burden=D('300');results=[]
 for _ in range(2):
  proposed=largest(principal,3);results.append(assess('1000','100',burden,proposed));burden+=proposed
 check('serialized submission reasoning '+principal,results==expected)
def current_exposure(data,borrower):
 total=D(0);reqs={q['RequestID']:q for q in data['LoanRequest']}
 for q in reqs.values():
  if q['BorrowerID']==borrower and q['RequestState'] in ['Submitted','PendingReview','OpenFunding']:
   total+=largest(q['Principal'],q['InstallmentCount'])
 for loan in data['Loan']:
  if loan['LoanState']!='Active' or reqs[loan['RequestID']]['BorrowerID']!=borrower:continue
  remainders=[]
  for inst in data['Installment']:
   if inst['LoanID']!=loan['LoanID']:continue
   paid=sum(D(a['AllocatedPrincipal']) for a in data['RepaymentAllocation'] if (a['LoanID'],a['InstallmentNumber'])==(inst['LoanID'],inst['InstallmentNumber']))
   remainders.append(D(inst['ScheduledPrincipal'])-paid)
  total+=max(remainders,default=D(0))
 return total
before=copy.deepcopy(f);before['Loan']=[l for l in before['Loan'] if l['LoanID']!=502]
next(q for q in before['LoanRequest'] if q['RequestID']==102)['RequestState']='OpenFunding'
check('funded-request conversion counted once',current_exposure(before,1)==D('500') and current_exposure(f,1)==D('500'))
def allowed_funding(amount,now):
 q=requests[103];remaining=D(q['Principal'])-sum(D(c['Amount']) for c in f['FundingCommitment'] if c['RequestID']==103 and c['CommitmentState']=='Pending')
 return q['RequestState']=='OpenFunding' and D('0')<D(amount)<=remaining and now<q['FundingDeadlineAt']
check('remaining cap and deadline boundary',allowed_funding('200','2026-10-19T00:00:00Z') and not allowed_funding('200.01','2026-10-19T00:00:00Z') and not allowed_funding('1','2026-11-01T00:00:00Z'))
check('due today is not overdue',not date(2026,10,19)<today)
def due(origin,n):
 month=origin.month-1+n;year=origin.year+month//12;month=month%12+1
 return date(year,month,min(origin.day,calendar.monthrange(year,month)[1]))
check('monthly date uses original day',due(date(2026,1,31),1)==date(2026,2,28) and due(date(2026,1,31),2)==date(2026,3,31))
check('cent rounding remainder',largest('100.00',3)==D('33.34'))
bad=copy.deepcopy(f)
bad['OperationReceipt'].append(dict(OperationID=2999,CallerUserID=1,OperationReference='cross-loan-check',ActionCode='PostRepayment'))
bad['Repayment'].append(dict(LoanID=501,RepaymentNumber=99,OperationID=2999))
bad['RepaymentAllocation'].append(dict(LoanID=502,RepaymentNumber=99,InstallmentNumber=1,AllocatedPrincipal='1.00'))
check('cross-loan allocation fails composite FK',any('orphan FK' in e for e in structural_errors(bad)))
for n in f['OversightNote']:
 check('note XOR '+str(n['NoteID']),(n['RequestID'] is None)!=(n['LoanID'] is None))
 if n['CorrectsNoteID']:
  prior=next(x for x in f['OversightNote'] if x['NoteID']==n['CorrectsNoteID']);check('same-target correction',tup(n,['RequestID','LoanID'])==tup(prior,['RequestID','LoanID']))

frd=(REPO/'docs/Functional_Requirements_Document.md').read_text();tdd=(REPO/'docs/Technical_Design_Document.md').read_text();explain=(REPO/'docs/ERD.md').read_text()
for prefix,n in [('FR',33),('BR',26),('SEC',14),('RQ',8),('AC',30)]:
 check(prefix+' requirement IDs retained',all(f'| {prefix}-{i:02d} |' in frd for i in range(1,n+1)))
check('document baselines', '| Version | 1.2 |' in frd and 'FRD 1.2' in tdd and 'TDD 1.2' in explain)
for e in entities.values():
 for c in e['columns']:
  check('TDD column '+e['name']+'.'+c['name'],f"| {c['name']} | `{c['type']}` | {c['nullable']} |" in tdd)
check('fixed-policy and evidence tradeoffs documented','coexisting policy versions' in frd and 'component history is required' not in frd.replace('no component history is required',''))
check('implementation limitation explicit','implementation consistency remains unverified' in explain)
for p in [REPO/'README.md',REPO/'docs/ERD.md',REPO/'docs/Technical_Design_Document.md']:
 for target in re.findall(r'\]\(([^)]+)\)',p.read_text()):
  if target.startswith(('http:','https:','#')):continue
  file=target.split('#')[0]
  if file:check(str(p.name)+' link '+file,(p.parent/file).exists())

# Complete fixture and canonical source references, not just selected key projections.
check('seven fictional users',len(f['User'])==7)
active_roles={u['UserID']:{r['RoleCode'] for r in f['UserRole'] if r['UserID']==u['UserID'] and r['RevokedAt'] is None} for u in f['User']}
check('FRD seven-user role distribution',sum(r=={'Borrower'} for r in active_roles.values())==2 and sum(r=={'Lender'} for r in active_roles.values())==2 and active_roles[7]=={'Borrower','Lender'} and active_roles[5]=={'Administrator'} and active_roles[6]=={'Auditor'})
check('dual role owns eligible request',requests[104]['BorrowerID']==7 and requests[104]['RequestState']=='OpenFunding')
check('self-funding denial leaves no effect',not any(c['RequestID']==104 for c in f['FundingCommitment']) and not any(o['OperationReference']=='dual-self-test' for o in f['OperationReceipt']))
check('dual role has no unrelated loan access',visible_loans(7)==[])
check('receipt holds original committed result',receipts[1001]['ReceiptSnapshot'].startswith('201\n') and json.loads(receipts[1001]['ReceiptSnapshot'].split('\n',1)[1])['commitmentState']=='Pending')
for e in entities.values():
 check(e['name']+' canonical TDD section','tdd_section' not in e and f"### {e['section']} {e['name']}" in tdd)
 names={c['name'] for c in e['columns']}
 check(e['name']+' has fixture rows',bool(f[e['name']]))
 for i,row in enumerate(f[e['name']]):
  check(f"{e['name']} row {i} complete",set(row)==names)
  for col in e['columns']:
   v=row[col['name']];label=f"{e['name']}[{i}].{col['name']}"
   if col['nullable']=='No':check(label+' required',v is not None)
   if v is None:continue
   if col['type']=='BINARY(16)':check(label+' 16 byte UUID',isinstance(v,str) and re.fullmatch('[0-9a-f]{32}',v) is not None)
   if col['type'].startswith('DATETIME'):check(label+' UTC timestamp',datetime.fromisoformat(v.replace('Z','+00:00')).utcoffset().total_seconds()==0)
   if col['type'].startswith('VARBINARY'):check(label+' encryption directive',isinstance(v,dict) and set(v)=={'encrypt'})
   if col['name']=='PasswordHash':check(label+' injected hash directive',v=={'hash_password_env':'FIXTURE_PASSWORD'})
for op in m['operational_entities']:check(op['name']+' operational section current',op.get('section')=='9' and 'tdd_section' not in op)
for e in f['RequestEvaluation']:
 check('evaluation generated result '+str(e['EvaluationID']),e['Result']==('Pass' if e['NoDelinquencyPass'] and e['AffordabilityPass'] else 'Fail') if e['CompletedAt'] else e['Result'] is None)
 check('review marker '+str(e['EvaluationID']),e['FinalReviewMarker']==(1 if e['EvaluationKind']=='Review' and e['Decision'] else None))
cat=json.loads((ROOT/'audit-catalogue.json').read_text());events={e['name']:e for e in cat['events']}
check('audit catalogue has no duplicate names',len(events)==len(cat['events']))
check('stale catalogue reference removed','Section 14 catalogue' not in tdd and 'Section 14 catalogue' not in (ROOT/'model.json').read_text())
for e in events.values():
 check(e['name']+' rendered catalogue entry',f"| `{e['name']}` |" in tdd)
 check(e['name']+' fits declared storage',len(e['name'])<=40 and e['subject'] in cat['subjects'])
 allowed=', '.join(e['fields']) or 'None'
 check(e['name']+' allowlist agreement',f'| {allowed} |' in next(line for line in tdd.splitlines() if line.startswith(f"| `{e['name']}` |")))
for e in events.values():
 if any(a['kind']=='verified_failure' for a in e['actors']):
  actor_label='Verified caller / unauthenticated / listed services'
 else:
  labels=[]
  for a in e['actors']:
   label=a.get('role') or a.get('service')
   if label=='Bootstrap':label+=' (fresh build)'
   if label not in labels:labels.append(label)
  actor_label=' / '.join(labels)
 row=next(line for line in tdd.splitlines() if line.startswith(f"| `{e['name']}` |"))
 check(e['name']+' actor catalogue/document agreement',row.split('|')[3].strip()==actor_label)
 check(e['name']+' no obsolete scalar actor fields','role' not in e and 'service' not in e)
for reason in cat['reasons']:check(reason+' documented reason',len(reason)<=40 and '`'+reason+'`' in tdd)
check('lifecycle and denial audit examples',len(f['AuditEvent'])>=20 and {'RequestSubmitted','AssessmentCompleted','ReviewApproved','CommitmentAccepted','LoanActivated','RepaymentPosted','DelinquencyChanged','AttemptRejected'} <= {e['EventType'] for e in f['AuditEvent']})
audit_by_id={e['AuditEventID']:e for e in f['AuditEvent']}
for e in f['AuditEvent']:
 spec=events[e['EventType']]
 check('audit vocabulary '+str(e['AuditEventID']),e['Outcome']==spec['outcome'] and e['SubjectType']==spec['subject'] and (e['ReasonCode'] is None or e['ReasonCode'] in cat['reasons']) and (e['ServiceActor'] is None or e['ServiceActor'] in cat['service_actors']))
 check('audit reason required '+str(e['AuditEventID']),e['Outcome']=='Success' or e['ReasonCode'] is not None)
 check('human and service actors distinct '+str(e['AuditEventID']),not(e['ActorUserID'] is not None and e['ServiceActor'] is not None))
 if e['SubjectType']!='Attempt':
  subject=e['SubjectType'];key=e['SubjectKey'].split('/')
  check('typed subject exists '+str(e['AuditEventID']),tuple(key) in {tuple(str(r[k]) for k in pk(entities[subject])) for r in f[subject]})
for c in f['AuditChange']:
 ev=audit_by_id[c['AuditEventID']];spec=events[ev['EventType']]
 check('event field allowlist '+str(c['AuditEventID'])+c['FieldName'],c['FieldName'] in spec['fields'])
 if c['FieldName'] in cat['redacted_fields']:check('private change redacted '+str(c['AuditEventID'])+c['FieldName'],c['OldValue'] is None and c['NewValue'] is None)
audit_failures=audit_errors(f,cat,bootstrap_accounts={'fixture_builder@localhost'})
check('event-specific audit contract: '+repr(audit_failures),not audit_failures)
audit_cases=run_audit_cases(f,cat)
for label in audit_cases:check('audit regression: '+label,True)
# Failure numbers are allocated when the separate retention transaction acquires its lock.
retained=[1,2];rolled_back_candidate=3
retained.append(3) # another action wins before failure recording reacquires the lock
recorded_failure=max(retained)+1
check('failed attempt does not reuse rolled-back candidate',recorded_failure==4 and recorded_failure!=rolled_back_candidate)
# A reference completion predicate, not an executed MySQL trigger.
def completes(schedule,per_installment,posted,per_payment,state):
 return state=='Active' and len(schedule) in (3,6) and all(x>0 for x in schedule) and all(0<=paid<=due for paid,due in zip(per_installment,schedule)) and posted==per_payment and sum(posted)==sum(per_installment)==sum(schedule)
check('partial allocation cannot complete',not completes([300,300,300],[300,300,299],[899],[899],'Active'))
check('unallocated payment cannot complete',not completes([300,300,300],[300,300,300],[900,1],[900,0],'Active'))
check('final reconciled allocation completes',completes([300,300,300],[300,300,300],[100,800],[100,800],'Active'))
check('already repaid never completes again',not completes([300,300,300],[300,300,300],[900],[900],'Repaid'))
# Independently verify every application-view text cell and re-exported file too.
app_source=ROOT/'Application_Design.drawio';app_raw=app_source.read_bytes();app_xml=ET.fromstring(app_raw)
check('two application views distinct from ERD',len(app_xml.findall('diagram'))==2 and len(m['pages'])==3)
for page,p in zip(app_xml.findall('diagram'),m['design_pages']):
 svg=ET.parse(ROOT/p['export']).getroot();groups={g.get('data-cell-id'):g for g in svg.findall('s:g',svg_ns)}
 check(p['id']+' export identity',page.get('id')==p['id'] and svg.get('data-source-sha256')==hashlib.sha256(app_raw).hexdigest())
 for c in page.findall('mxGraphModel/root/mxCell'):
  if c.find('mxGeometry') is None:continue
  check(c.get('id')+' application export cell',c.get('id') in groups)
  if c.get('value'):
   actual='\n'.join(''.join(t.itertext()) for t in groups[c.get('id')].findall('s:text/s:tspan',svg_ns))
   check(c.get('id')+' application text',actual==c.get('value'))
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/app_source.name;path.write_bytes(app_raw);path.with_name('model.json').write_bytes((ROOT/'model.json').read_bytes())
 for p in exporter.export(path):check(p.name+' exact direct export',p.read_bytes()==(ROOT/p.name).read_bytes())

print(f'PASS: {len(checks)} design assertions; 15 entities / 114 attributes / 27 FKs; 3 ERD + 2 application SVGs source-matched.')
print(f'Including {len(audit_cases)} targeted audit-contract regression cases.')
print('Complete fixture/reference calculations only. MySQL load, API, races, rollback, application encryption and native draw.io UI round-trip NOT executed.')
