"""Generate the workflow companion's editable diagram and SVG from one layout."""
from pathlib import Path
from html import escape
from xml.etree import ElementTree as E

OUT=Path(__file__).resolve().parents[1]
boxes=[
 ('Permission',30,90,330,110,['PK PermissionCode','Existing capability catalogue']),
 ('RequestWorkflowAction',480,90,670,170,['PK ActionCode','FK PermissionCode -> Permission','SuccessEventType']),
 ('RequestWorkflowState',30,380,330,130,['PK StateCode','Description']),
 ('RequestWorkflowTransition',480,350,670,230,['PK/FK ActionCode','PK/FK FromState -> StateCode','FK ToState -> StateCode','IsEnabled (0/1)','RowVersion']),
]
root=E.Element('mxfile');d=E.SubElement(root,'diagram',name='Request workflow rules')
g=E.SubElement(d,'mxGraphModel',pageWidth='1200',pageHeight='920');cells=E.SubElement(g,'root')
E.SubElement(cells,'mxCell',id='0');E.SubElement(cells,'mxCell',id='1',parent='0')
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="920" viewBox="0 0 1200 920"><rect width="1200" height="920" fill="white"/>']
def label(key,text,x,y,size=18):
 c=E.SubElement(cells,'mxCell',id=key,value=text,vertex='1',parent='1',style=f'text;html=0;align=left;fontSize={size};')
 E.SubElement(c,'mxGeometry',x=str(x),y=str(y-24),width='1120',height='28',attrib={'as':'geometry'})
 svg.append(f'<text x="{x}" y="{y}" font-family="sans-serif" font-size="{size}" fill="#163449">{escape(text)}</text>')
label('title','Request workflow policy - current build: 20 tables / 136 columns / 33 FKs',30,42,24)
for name,x,y,w,h,lines in boxes:
 c=E.SubElement(cells,'mxCell',id=name,value='\n'.join([name]+lines),vertex='1',parent='1',style='whiteSpace=wrap;html=0;fontSize=18;align=left;spacing=12;fillColor=#eef5fa;')
 E.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'})
 svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="#eef5fa" stroke="#235983"/>')
 for i,line in enumerate([name]+lines):
  svg.append(f'<text x="{x+14}" y="{y+30+i*30}" font-family="sans-serif" font-size="18" fill="#163449">{escape(line)}</text>')
for name,source,target,path in [
 ('capability','Permission','RequestWorkflowAction','M360 145 H480'),
 ('action','RequestWorkflowAction','RequestWorkflowTransition','M810 260 V350'),
 ('source_state','RequestWorkflowState','RequestWorkflowTransition','M360 420 H480'),
 ('destination_state','RequestWorkflowState','RequestWorkflowTransition','M360 470 H480')]:
 c=E.SubElement(cells,'mxCell',id=name,source=source,target=target,value=name.replace('_',' '),edge='1',parent='1',style='endArrow=none;fontSize=14;')
 E.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
 svg.append(f'<path d="{path}" fill="none" stroke="#235983" stroke-width="2"/>')
label('cardinality','Each transition has exactly one action, source and destination; each parent has 0..N references.',30,625,18)
rows=[('Action','Source','Destination','Required permission'),
 ('CreateDraft','NotCreated','Draft','request.create'),
 ('EditDraft','Draft','Draft','request.edit'),
 ('SubmitRequest','Draft','Submitted','request.submit'),
 ('CancelDraft','Draft','Cancelled','request.cancel')]
for i,row in enumerate(rows):
 for j,(x,value) in enumerate(zip([30,300,540,800],row)):
  label('rule_cell_'+str(i)+'_'+str(j),value,x,685+i*32,20)
label('boundary','Definitions name implemented handlers. Administrators can enable/disable rules with audited version checks.',30,885,17)
svg.append('</svg>')
E.ElementTree(root).write(OUT/'Request_Workflow.drawio',encoding='utf-8',xml_declaration=True)
(OUT/'07-request-workflow.svg').write_text(''.join(svg))
