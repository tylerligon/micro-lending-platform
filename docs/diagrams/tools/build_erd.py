"""Regenerate the three-page layout from model.json. Overwrites manual layout edits.
To export an existing manually edited layout, run export_svg.py instead.
"""
from pathlib import Path
import json, textwrap
import xml.etree.ElementTree as ET

D=Path(__file__).resolve().parents[1]
M=json.loads((D/'model.json').read_text())
E={e['name']:e for e in M['entities']}
BLUE='#235983'; INK='#183247'; MUTED='#536b7c'; LIGHT='#eef5f9'
mx=ET.Element('mxfile',host='app.diagrams.net',type='device',version='24.7.17')

def page(pid,name,w,h):
 p=ET.SubElement(mx,'diagram',id=pid,name=name)
 g=ET.SubElement(p,'mxGraphModel',dx=str(w),dy=str(h),grid='1',gridSize='10',guides='1',tooltips='1',connect='1',arrows='1',fold='1',page='1',pageScale='1',pageWidth=str(w),pageHeight=str(h),math='0',shadow='0')
 r=ET.SubElement(g,'root'); ET.SubElement(r,'mxCell',id='0');ET.SubElement(r,'mxCell',id='1',parent='0');return r

def node(r,id,value,x,y,w,h,shape='rectangle',fill='white',stroke=BLUE,fs=18,bold=False,align='center',parent='1',extra='',fontstyle=0):
 st=f'shape={shape};whiteSpace=wrap;html=0;rounded=0;fillColor={fill};strokeColor={stroke};strokeWidth=1.5;fontFamily=DejaVu Sans;fontSize={fs};fontColor={INK};align={align};verticalAlign=middle;fontStyle={fontstyle or (1 if bold else 0)};'+extra
 c=ET.SubElement(r,'mxCell',id=id,value=value,style=st,vertex='1',parent=parent)
 ET.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'})
 return c

def txt(r,id,value,x,y,w,h,fs=18,bold=False,align='left',parent='1',fontstyle=0):
 return node(r,id,value,x,y,w,h,'text','none','none',fs,bold,align,parent,fontstyle=fontstyle)

def edge(r,id,points,source=None,target=None,dashed=False,double=False):
 def attached(point):
  px,py=point
  for c in r.findall('mxCell'):
   if c.get('vertex')!='1' or c.get('parent')!='1' or 'shape=text;' in c.get('style','') or c.get('id','').endswith('.inner'):continue
   g=c.find('mxGeometry');x,y,w,h=[float(g.get(k,'0')) for k in ['x','y','width','height']]
   if w and h and x-1<=px<=x+w+1 and y-1<=py<=y+h+1 and min(abs(px-x),abs(px-x-w),abs(py-y),abs(py-y-h))<1:
    return c.get('id'),(px-x)/w,(py-y)/h
  return None
 attrs=dict(id=id,edge='1',parent='1',style=f'edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=none;startArrow=none;strokeColor={BLUE};strokeWidth=1.8;dashed={int(dashed)};exitX=1;exitY=0.5;entryX=0;entryY=0.5;')
 if not source:
  a=attached(points[0])
  if a:source=a[0];attrs['style']+=f'exitX={a[1]};exitY={a[2]};exitPerimeter=0;'
 if not target:
  a=attached(points[-1])
  if a:target=a[0];attrs['style']+=f'entryX={a[1]};entryY={a[2]};entryPerimeter=0;'
 if source: attrs['source']=source
 if target: attrs['target']=target
 c=ET.SubElement(r,'mxCell',**attrs);g=ET.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
 ET.SubElement(g,'mxPoint',x=str(points[0][0]),y=str(points[0][1]),attrib={'as':'sourcePoint'})
 if len(points)>2:
  a=ET.SubElement(g,'Array',attrib={'as':'points'})
  for x,y in points[1:-1]:ET.SubElement(a,'mxPoint',x=str(x),y=str(y))
 ET.SubElement(g,'mxPoint',x=str(points[-1][0]),y=str(points[-1][1]),attrib={'as':'targetPoint'})
 return c

def banner(r,pid,title,subtitle,w):
 txt(r,pid+'.title',title,45,25,w-90,48,30,True)
 txt(r,pid+'.subtitle',subtitle,45,80,w-90,46,18)

def box(r,id,label,x,y,w=260,h=74,weak=False):
 node(r,id,label,x,y,w,h,bold=True,fs=23,fill=LIGHT)
 if weak:node(r,id+'.inner','',6,6,w-12,h-12,fill='none',parent=id)

def diamond(r,id,label,x,y,w=175,h=92,ident=False):
 node(r,id,label,x,y,w,h,'rhombus',fs=17,bold=True)
 if ident:node(r,id+'.inner','',7,7,w-14,h-14,'rhombus','none',parent=id)

def line(r,id,pts,total=False):
 edge(r,id,pts)
 if total:
  # The conceptual paths are orthogonal. Offset a second line visibly.
  if len(pts)==2 and pts[0][0]==pts[1][0]:q=[(x+5,y) for x,y in pts]
  elif len(pts)==2:q=[(x,y+5) for x,y in pts]
  else:
   q=[(x+5,y+5) for x,y in pts]
   q[0]=(pts[0][0]+(5 if pts[0][0]==pts[1][0] else 0),pts[0][1]+(5 if pts[0][1]==pts[1][1] else 0))
   q[-1]=(pts[-1][0]+(5 if pts[-1][0]==pts[-2][0] else 0),pts[-1][1]+(5 if pts[-1][1]==pts[-2][1] else 0))
  edge(r,id+'.total',q)

# Page 1: the conceptual story with Chen notation and an explicit M:N mapping.
r=page('conceptual',M['pages'][0]['name'],2200,1790)
banner(r,'concept','Micro-lending · conceptual model','Read the named relationships first. Complete typed attributes appear on pages 2–3; repeated User labels denote the same entity.',2200)
box(r,'c.borrower','User (borrower)',70,200)
diamond(r,'c.owns','owns',410,191)
box(r,'c.request','LoanRequest',665,200)
diamond(r,'c.receives','receives',1005,191)
box(r,'c.commitment','FundingCommitment',1260,200,300)
diamond(r,'c.makes','makes',1645,191)
box(r,'c.lender','User (lender)',1870,200,260)
line(r,'c.owns.left',[(330,237),(410,237)])
line(r,'c.owns.right',[(585,237),(665,237)],True)
line(r,'c.receives.left',[(925,237),(1005,237)])
line(r,'c.receives.right',[(1180,237),(1260,237)],True)
line(r,'c.makes.left',[(1560,237),(1645,237)],True)
line(r,'c.makes.right',[(1820,237),(1870,237)])
for id,label,x,y,w in [('a','(0,N)',340,195,66),('b','(1,1)',592,195,66),('c','(0,N)',935,195,66),('d','(1,1)',1187,195,66),('e','(1,1)',1570,195,70),('f','(0,N)',1812,159,85)]:txt(r,'c.card.'+id,label,x,y,w,25,17)
txt(r,'c.repeat','Each contribution is its own event. One lender may contribute again to the same eligible request.',1190,300,920,55,18)
diamond(r,'c.evaluates','evaluates',710,398,170,100)
box(r,'c.evaluation','RequestEvaluation',650,625,290)
line(r,'c.eval.up',[(795,274),(795,398)])
line(r,'c.eval.down',[(795,498),(795,625)],True)
txt(r,'c.eval.c1','(0,N)',810,324,80,30,18)
txt(r,'c.eval.c2','(1,1)',810,548,80,30,18)
txt(r,'c.eval.note','RequestEvaluation retains:\n• a submission observation\n• its assessment completion\n• separate review/funding attempts\n\nCompleted history is immutable.',70,435,505,190,19)
diamond(r,'c.origin','activates',1110,425,175,100)
box(r,'c.loan','Loan',1390,438,260)
line(r,'c.origin.left',[(925,255),(970,255),(970,475),(1110,475)])
line(r,'c.origin.right',[(1285,475),(1390,475)],True)
txt(r,'c.origin.c1','(0,1)',975,435,90,30,18)
txt(r,'c.origin.c2','(1,1)',1294,435,90,30,18)
txt(r,'c.full','Only full funding activates a loan.\nBorrowers can have multiple loans.',1680,510,470,75,18)
diamond(r,'c.schedule','schedules',1432,675,175,100,True)
box(r,'c.installment','Installment',1390,910,260,84,True)
line(r,'c.schedule.up',[(1520,512),(1520,675)],True)
line(r,'c.schedule.down',[(1520,775),(1520,910)],True)
txt(r,'c.schedule.c1','(3 or 6)',1535,621,125,30,18)
txt(r,'c.schedule.c2','(1,1)',1535,835,85,30,18)
txt(r,'c.weak.note','Weak entity: PK (LoanID, InstallmentNumber)\nInstallmentNumber is unique only within its loan.',1330,1020,700,60,18)
node(r,'c.partial','InstallmentNumber',1750,920,310,64,'ellipse',fs=19)
line(r,'c.partial.link',[(1650,952),(1750,952)])
edge(r,'c.partial.underline',[(1790,969),(2020,969)],dashed=True)
txt(r,'c.partial.caption','Partial key (dashed underline)',1740,990,400,30,16)
box(r,'c.repayment','Repayment',665,910,260,84)
diamond(r,'c.haspayment','records',1095,690,175,100)
line(r,'c.pay.loan',[(1390,490),(1350,490),(1350,740),(1270,740)])
line(r,'c.pay.payment',[(1095,740),(795,740),(795,910)],True)
txt(r,'c.pay.c1','(0,N)',1280,705,80,28,18)
txt(r,'c.pay.c2','(1,1)',805,852,80,28,18)
diamond(r,'c.covers','covers',1080,902,175,100)
line(r,'c.covers.left',[(925,952),(1080,952)],True)
line(r,'c.covers.right',[(1255,952),(1390,952)])
txt(r,'c.covers.c1','(1,N)',960,910,90,26,18)
txt(r,'c.covers.c2','(0,N)',1280,910,90,26,18)
node(r,'c.amount','AllocatedPrincipal',1070,1080,195,62,'ellipse',fs=17)
line(r,'c.amount.link',[(1167,1002),(1167,1080)])
txt(r,'c.cover.map','M:N → RepaymentAllocation\nOne payment can cover several installments;\none installment can receive several payments.',680,1185,1100,82,20,align='center')

# Identity and attribute notation stay in the same conceptual page.
node(r,'c.legend.panel','',45,1320,2110,420,fill='#f7fafc',stroke='#c4d6e1')
txt(r,'c.legend.title','Notation and relational mapping',70,1340,800,35,23,True)
box(r,'c.attr.user','User',95,1425,180,70)
diamond(r,'c.attr.assigned','assigned',335,1415,170,90)
box(r,'c.attr.role','Role',565,1425,180,70)
line(r,'c.attr.roles.left',[(275,1460),(335,1460)])
line(r,'c.attr.roles.right',[(505,1460),(565,1460)])
txt(r,'c.attr.roles.c1','(0,N)',263,1382,80,27,16)
txt(r,'c.attr.roles.c2','(0,N)',515,1382,80,27,16)
txt(r,'c.attr.roles.map','M:N roles → UserRole episodes.\nAt most one active membership per pair.',70,1640,435,70,17)
node(r,'c.attr.key','UserID',95,1560,165,55,'ellipse',fs=18,fontstyle=4)
node(r,'c.attr.roles','Roles',300,1560,165,55,'ellipse',fs=18)
node(r,'c.attr.roles.inner','',306,1566,153,43,'ellipse','none')
node(r,'c.attr.derived','RemainingPrincipal',510,1560,240,55,'ellipse',fs=18,extra='dashed=1;')
line(r,'c.attr.key.link',[(185,1495),(185,1560)])
line(r,'c.attr.multi.link',[(220,1495),(220,1520),(382,1520),(382,1560)])
txt(r,'c.attr.derived.note','Loan balance:\nscheduled − allocations.',510,1630,270,65,16)
node(r,'c.attr.composite','RepaymentID',850,1410,240,65,'ellipse',fs=19)
node(r,'c.attr.loanid','LoanID',805,1535,170,55,'ellipse',fs=18)
node(r,'c.attr.repaynum','RepaymentNumber',1000,1535,245,55,'ellipse',fs=18)
line(r,'c.attr.comp1',[(925,1475),(890,1535)])
line(r,'c.attr.comp2',[(1015,1475),(1122,1535)])
txt(r,'c.attr.comp.note','Composite identifier maps to two PK columns.\nRole ovals are notation, not a stored list.\nDashed oval = derived; underlined oval = key.',815,1605,500,98,17)
txt(r,'c.legend.text','Rectangles: entities · diamonds: relationships\nDouble rectangle + diamond: weak / identifying\nDouble line: total participation · single: partial\n(min,max) at an entity: its participation count\n\nThe 3-or-6 schedule minimum is transactional.\nPage 2–3 FK cards state both directions explicitly.\nAll 15 entities and 114 attributes are defined there.',1370,1390,740,290,19)

UK={
'User':[['LoginName'],['PublicAlias']], 'UserRole':[['UserID','RoleCode','ActiveMarker']],
'RequestEvaluation':[['RequestID','EvaluationKind','AttemptNumber'],['RequestID','FinalReviewMarker']],
'OperationReceipt':[['CallerUserID','OperationReference']], 'FundingCommitment':[['OperationID'],['EvaluationID']],
'Loan':[['RequestID']], 'Installment':[['LoanID','DueDate']], 'Repayment':[['OperationID']]}

def logical(pageinfo):
 pid=pageinfo['id'];r=page(pid,pageinfo['name'],2080,3000)
 heights=[170,170]
 banner(r,pid,'Micro-lending · '+('accounts, requests and funding' if pid=='funding' else 'loans, repayments and oversight'),
  'PK primary key · U# unique group · F## foreign key · G generated · FK cards give counts in both directions.',2080)
 for idx,name in enumerate(pageinfo['entities']):
  e=E[name];col=min(range(2),key=lambda i:heights[i]);x=40+col*1020;y=heights[col]
  base=f'{pid}.{name}'; cols=e['columns']; fks=[f for f in M['relationships'] if f['child']==name]
  uks=UK.get(name,[])
  notes=['PK: '+e['pk']]+[f'U{i+1}: '+', '.join(uk) for i,uk in enumerate(uks)]
  if not uks: notes.append('No additional UNIQUE constraint.')
  if name=='FundingCommitment':notes.append('Lender = receipt caller; repeat lender/request pairs allowed.')
  if name=='LoanRequest':notes.append('Fixed D1. Frozen inputs required after submission; no borrower UNIQUE.')
  if name=='RequestEvaluation':notes+=['Result: Pass iff both flags = 1 after completion.', 'FinalReviewMarker: 1 for a final Review; otherwise NULL.']
  if name=='UserRole':notes.append('ActiveMarker: 1 if active; otherwise NULL.')
  if name=='RepaymentAllocation':notes.append('Both composite FKs share LoanID: cross-loan allocation is impossible.')
  if name=='Loan':notes.append('Borrower/terms from request. Current balance/overdue are derived.')
  wrapped=[line for n in notes for line in textwrap.wrap(n,69)]
  head=95; rowh=31; h=head+len(cols)*rowh+len(wrapped)*21+22
  node(r,base,'',x,y,650,h,fill='white',stroke=BLUE)
  node(r,base+'.header','',0,0,650,58,fill=LIGHT,parent=base)
  txt(r,base+'.name',name,12,5,626,29,22,True,parent=base)
  txt(r,base+'.kind',e['kind']+' · '+e['basis'],12,33,626,24,12,parent=base)
  for label,xx,ww in [('Attribute',12,285),('MySQL type',300,180),('Keys',485,100),('NULL',590,57)]:
   txt(r,base+'.label.'+label,label,xx,62,ww,27,15,True,parent=base)
  for j,c in enumerate(cols):
   ry=head+j*rowh;cid=base+'.'+c['name'];keys=[]
   if c['name'] in e['pk'].strip('()').replace(' ','').split(','):keys.append('PK')
   if 'Generated' in c['nullable']:keys.append('G')
   for k,uk in enumerate(uks,1):
    if c['name'] in uk:keys.append('U'+str(k))
   for f in fks:
    if c['name'] in f['columns']:keys.append('F'+f['id'][2:])
   node(r,cid,'',0,ry,650,rowh,fill='#f6f9fb' if j%2==0 else 'white',stroke='none',parent=base)
   txt(r,cid+'.name',c['name'],12,0,285,rowh,16,parent=cid,fontstyle=4 if 'PK' in keys else 0)
   txt(r,cid+'.type',c['type'],300,0,180,rowh,15,parent=cid)
   txt(r,cid+'.keys',' '.join(keys),485,0,100,rowh,12,parent=cid)
   txt(r,cid+'.null','G/Yes' if 'Generated' in c['nullable'] else ('Yes' if c['nullable'].startswith('Yes') else c['nullable']),590,0,57,rowh,14,parent=cid)
  txt(r,base+'.constraints','\n'.join(wrapped),12,head+len(cols)*rowh+10,626,len(wrapped)*21,15,parent=base)
  # A reference card per FK avoids 27 long lines crossing other tables. These
  # are named references, not extra entities; the conceptual page shows topology.
  last=y+70
  for k,f in enumerate(fks):
   ci=next(i for i,c in enumerate(cols) if c['name']==f['columns'][-1]);sy=y+head+ci*rowh+rowh/2
   cy=max(sy-44,last);last=cy+104;cx=x+710
   rid=base+'.ref.'+f['id'];refkey=', '.join(f['references'])
   refrows=textwrap.wrap(refkey,25)
   content=f"{f['id']} → {f['parent']}\n"+'\n'.join(refrows)+f"\nchild → parent {f['parents_per_child']}\nparent → child {f['children_per_parent']}"
   rh=max(90,19*(len(refrows)+3)+12);last=cy+rh+12
   node(r,rid,content,cx,cy,250,rh,fill=LIGHT,stroke='#8daec5',fs=14,extra='dashed=1;')
   ex=cx;ey=cy+rh/2;mid=x+675+k*8
   edge(r,base+'.fk.'+f['id'],[(x+650,sy),(mid,sy),(mid,ey),(ex,ey)],source=base+'.'+f['columns'][-1],target=rid)
  heights[col]=max(y+h,last if fks else y+h)+45
 bottom=max(heights)
 if pid=='funding':
  notes='Profile = current values. Request = frozen submitted values. Evaluation = one retained check.\nReceipt = caller-scoped exact retry. Commitment = one contribution, including repeat lender contributions.\nDashed cards are named references, not entities. Full constraints: TDD §4, §6–8. Audit catalogue: §8.1.'
 else:
  notes='DERIVED VIEWS (not application entities): v_request_funding = one request; v_installment_balance = one installment;\nv_loan_balance = one loan. RQ-04/05 calculate overdue at T. Lender scope uses EXISTS of an own Applied commitment.\nBuildRun / BuildStep are operational only (TDD §9). Reconciliation, schedule minimums and oldest-first allocation require transactions.'
 node(r,pid+'.notes','',40,bottom,2000,135,fill='#f7fafc',stroke='#c4d6e1')
 txt(r,pid+'.notes.text',notes,60,bottom+16,1960,100,18)
 txt(r,pid+'.footer','FRD 1.2 · TDD 1.2 · 15 entities / 114 attributes / 27 FKs · FK matrix: ERD.md · Source: model.json',40,bottom+150,2000,35,18)
 graph=mx.findall('diagram')[-1].find('mxGraphModel');graph.set('pageHeight',str(int(bottom+220)));graph.set('dy',str(int(bottom+220)))

logical(M['pages'][1]);logical(M['pages'][2])
ET.indent(mx)
(D/'Micro_Lending_ERD.drawio').write_bytes(ET.tostring(mx,encoding='utf-8',xml_declaration=True))
print('Wrote 3 editable pages.')
