"""Rebuild the two application-design views; these are not additional ERDs."""
from pathlib import Path
import xml.etree.ElementTree as ET
D=Path(__file__).resolve().parents[1]
mx=ET.Element('mxfile',host='app.diagrams.net',type='device',version='24.7.17')
BLUE='#235983';INK='#183247';LIGHT='#eef5f9'
def page(id,name,w,h):
 d=ET.SubElement(mx,'diagram',id=id,name=name);g=ET.SubElement(d,'mxGraphModel',page='1',pageWidth=str(w),pageHeight=str(h),grid='1',gridSize='10')
 r=ET.SubElement(g,'root');ET.SubElement(r,'mxCell',id='0');ET.SubElement(r,'mxCell',id='1',parent='0');return r
def cell(r,id,text,x,y,w,h,fs=20,fill='white',bold=False,align='center',border=True):
 shape='rectangle' if border else 'text'
 c=ET.SubElement(r,'mxCell',id=id,value=text,vertex='1',parent='1',style=f'shape={shape};html=0;whiteSpace=wrap;fillColor={fill};strokeColor={BLUE if border else "none"};strokeWidth=1.5;fontFamily=DejaVu Sans;fontSize={fs};fontColor={INK};fontStyle={1 if bold else 0};align={align};verticalAlign=middle;')
 ET.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'});return c
def edge(r,id,src,dst,pts):
 cells={c.get('id'):c for c in r.findall('mxCell')}
 ratios=[]
 for cid,pt in [(src,pts[0]),(dst,pts[-1])]:
  g=cells[cid].find('mxGeometry');x,y,w,h=[float(g.get(k,'0')) for k in ['x','y','width','height']];ratios.append(((pt[0]-x)/w,(pt[1]-y)/h))
 st=f'edgeStyle=orthogonalEdgeStyle;endArrow=block;strokeColor={BLUE};strokeWidth=2;exitX={ratios[0][0]};exitY={ratios[0][1]};entryX={ratios[1][0]};entryY={ratios[1][1]};exitPerimeter=0;entryPerimeter=0;'
 c=ET.SubElement(r,'mxCell',id=id,edge='1',parent='1',source=src,target=dst,style=st);g=ET.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
 for tag,pt in [('sourcePoint',pts[0]),('targetPoint',pts[-1])]:ET.SubElement(g,'mxPoint',x=str(pt[0]),y=str(pt[1]),attrib={'as':tag})
 if len(pts)>2:
  a=ET.SubElement(g,'Array',attrib={'as':'points'})
  for x,y in pts[1:-1]:ET.SubElement(a,'mxPoint',x=str(x),y=str(y))
def title(r,id,title,sub):
 cell(r,id+'.title',title,40,20,1520,55,30,bold=True,align='left',border=False)
 cell(r,id+'.sub',sub,40,80,1520,60,19,align='left',border=False)
r=page('application-flow','Application boundaries and transaction data flow',1600,1350)
title(r,'flow','Application boundaries · design contract','Proposed single deployable service. Instructor confirmation of the microservices interpretation is still required.\nNo running API/UI or database implementation is represented here. TDD §§2, 6–8.')
cell(r,'browser','BROWSER\nSame-origin UI\nSession cookie + CSRF\nNo DB credentials or keys',40,190,360,170,22,LIGHT,True)
cell(r,'service','TRUSTED SERVICE\nCommand + Query modules\nIdentity, crypto, DB coordinator\nOne reserved connection per action',570,190,470,170,22,LIGHT,True)
cell(r,'database','MYSQL / INNODB\nRestricted routines + triggers\n15 application tables\nEncrypted private columns',1190,190,370,170,21,LIGHT,True)
edge(r,'http','browser','service',[(400,250),(570,250)]);cell(r,'http.label','HTTPS / API',407,202,155,36,17,border=False)
edge(r,'db','service','database',[(1040,250),(1190,250)]);cell(r,'db.label','TLS / routines',1046,202,140,36,16,border=False)
cell(r,'worker','WORKER\nAssessment / expiry / delinquency\nSame coordinator, worker credential',570,435,470,120,21,LIGHT)
edge(r,'worker.call','worker','service',[(805,435),(805,360)])
cell(r,'keys','INJECTED SECRETS\nKeys + separate runtime DB credentials\nNever in browser, tables or audit',40,435,430,120,20)
edge(r,'keys.call','keys','service',[(470,480),(515,480),(515,320),(570,320)])
cell(r,'scope','TRUST BOUNDARY\nService may decrypt internally.\nPublic responses use FRD allowlists.\nA lender sees only participating loans.',1130,420,430,155,19,fill='#f7fafc')
cell(r,'steps.title','One mutation · one connection · one atomic result',40,625,1520,50,27,bold=True,align='left',border=False)
steps=[('prepare','1  PREPARE / LOCK\nValidate actor and receipt retry.\nLock Users → profile → requests\n→ loans → installments; capture T.',40,710),('decrypt','2  DECRYPT / AUTHENTICATE\nRead exact locked envelopes.\nDecrypt locally with field-bound AAD.\nFailure aborts the entire action.',575,710),('calculate','3  CALCULATE IN SQL\nBound decimal inputs; current burden.\nCheck capacity, deadline, delinquency.\nReturn authoritative check summary.',1110,710),('write','4  WRITE + AUDIT\nEncrypt retained summary.\nRoutine writes business effects.\nTrigger alone owns loan completion.',1110,970),('commit','5  COMMIT / RESPOND\nStore original financial receipt.\nCommit before reporting success.\nExact retry returns original result.',575,970),('failure','6  ON FAILURE\nWhole transaction rollback.\nSeparate failure evidence transaction.\nRetry transient errors at most 3 tries.',40,970)]
for id,txt,x,y in steps:cell(r,id,txt,x,y,450,170,20,LIGHT)
edge(r,'p-d','prepare','decrypt',[(490,795),(575,795)])
edge(r,'d-c','decrypt','calculate',[(1025,795),(1110,795)])
edge(r,'c-w','calculate','write',[(1335,880),(1335,970)])
edge(r,'w-commit','write','commit',[(1110,1055),(1025,1055)])
# Failure is an alternative branch, explicitly labeled rather than a post-commit step.
cell(r,'failure.branch','Failure branch from steps 1–5; step 6 is not executed after a confirmed successful commit.',40,1165,1520,45,20,align='left',border=False)
cell(r,'flow.note','RQ-01 uses the same lock/decrypt/calculate boundary without writing evaluation history.\nOther reports use one consistent snapshot and authorization scope. Session memory is operational, not another entity.\nEditable source + exports: Application_Design.drawio · Explanation and API contracts: TDD §2.',40,1230,1520,88,19,align='left',border=False)
r=page('wireframes','Basic UI wireframes — design only',1600,1490)
title(r,'ui','Basic interface · wireframes','FR-33 / AC-25. Layout sketches only; controls are not implemented. Same lending rules and authorization apply to every route.\nShared sign-in → permitted role navigation. A dual user can switch Borrower/Lender; self-funding stays forbidden.')
def panel(id,title,x,y,w,h):
 cell(r,id,'',x,y,w,h,fill='#f7fafc');cell(r,id+'.title',title,x+18,y+12,w-36,45,25,LIGHT,True,align='left',border=False)
def text(id,s,x,y,w,h,fs=20):cell(r,id,s,x,y,w,h,fs,align='left',border=False)
def button(id,s,x,y,w):cell(r,id,s,x,y,w,48,18,LIGHT,True)
panel('b','BORROWER · own requests and loans',40,175,740,740)
text('b.profile','Private profile: monthly income [1000.00]\nExternal obligations [100.00]          [Save profile]',60,245,700,75)
text('b.draft','New request: purpose [equipment]\nPrincipal [300.00]     Installments [3 / 6]',60,345,700,75)
button('b.save','Save draft',60,430,175);button('b.submit','Submit request',260,430,205)
text('b.loans','MY LOANS       Outstanding       Overdue\n501                 $550.00          $250.00\n502                 $200.00              $0.00\nTotal               $750.00          $250.00',60,515,700,130)
text('b.payment','Selected loan 501 → schedule / payment allocations\nRepayment amount [____]       [Post repayment]\nA payment affects this selected loan only.',60,680,700,110)
text('b.result','Result area: committed receipt / useful error.\nUnknown outcome → check result / retry same payment.',60,810,700,70,18)
panel('l','LENDER · public requests and own loans',820,175,740,740)
text('l.filter','Filters: principal [min] [max]    installments [all]\nEligible requests ordered by funding deadline',840,245,700,75)
text('l.list','REQUEST     Alias        Principal       Remaining\n103           alias4         $300.00         $200.00\n104           alias7         $300.00         $300.00\nPrivate income, contact and inputs are absent.',840,345,700,140)
text('l.fund','Request 103: contribution [100.00]\nEach new contribution receives a new reference.',840,505,700,75)
button('l.contribute','Contribute',840,590,210)
text('l.loans','MY FUNDED LOANS · example: Lender 2\nLoan 501 / Borrower 1 · overdue $250.00\n[Full schedule]  [Repayments]  [Delinquency]\nLoan 502 is absent: this lender did not fund it.',840,675,700,130)
text('l.result','Repeat contribution is permitted while eligible/open.\nRepeated participation never duplicates loan totals.',840,815,700,65,18)
panel('o','OVERSIGHT · Administrator or read-only Auditor',40,960,1520,390)
text('o.review','ADMINISTRATOR\nReview queue → authorized inputs and check results\n[Approve] [Reject + reason]   [Append follow-up note]\nAccounts → [Restrict] / role management\nNo editing past payments, assessments or audit events.',65,1035,720,200)
text('o.audit','ADMINISTRATOR + AUDITOR\nLoan-scoped delinquency → schedule / history\nMonthly reports → totals over authorized records\nAudit history → event, actor, time, safe old/new values\nAuditor: no mutations or private financial inputs.',825,1035,700,200)
text('o.empty','Every workspace needs loading, empty, validation, denial, success and unknown-outcome states.\nButtons do not enforce permission: API + routines do. Label repayments as loan progress, never lender payouts.',65,1260,1450,65,18)
text('ui.footer','Money is fictional and interest-free. UTC timestamps / calendar due dates. No wallet, payment provider or disbursement screen.\nEditable source + exports: Application_Design.drawio · API/session/field contracts: TDD §2.2.',40,1380,1520,70,19)
ET.indent(mx);(D/'Application_Design.drawio').write_bytes(ET.tostring(mx,encoding='utf-8',xml_declaration=True))
print('Wrote 2 editable application-design views.')
