"""Generate the companion entitlement source and SVG from one layout specification."""
from pathlib import Path
from xml.etree import ElementTree as E
from html import escape
p=Path(__file__).resolve().parents[1]
boxes=[('Role',40,80,400,240,['PK RoleCode VARCHAR(16)','Description VARCHAR(255) NOT NULL','RoleClass VARCHAR(16) NOT NULL','IsActive BOOLEAN NOT NULL','RowVersion BIGINT UNSIGNED NOT NULL','Immutable category; configurable grants']),('Permission',580,80,470,240,['PK PermissionCode VARCHAR(40)','BorrowerScope VARCHAR(16) NULL','LenderScope VARCHAR(16) NULL','AdministratorScope VARCHAR(16) NULL','AuditorScope VARCHAR(16) NULL','AllowRestricted BOOLEAN NOT NULL']),('RolePermission',320,440,500,160,['PK/FK RoleCode VARCHAR(16)','PK/FK PermissionCode VARCHAR(40)','ScopeCode VARCHAR(16) NOT NULL','PK (RoleCode, PermissionCode)'])]
root=E.Element('mxfile');d=E.SubElement(root,'diagram',name='Entitlements');g=E.SubElement(d,'mxGraphModel',pageWidth='1100',pageHeight='740');r=E.SubElement(g,'root');E.SubElement(r,'mxCell',id='0');E.SubElement(r,'mxCell',id='1',parent='0')
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="740" viewBox="0 0 1100 740"><rect width="1100" height="740" fill="white"/>','<text x="40" y="40" font-family="sans-serif" font-size="24">Entitlement extension — 17 tables / 126 columns / 29 FKs overall</text>']
for i,(name,x,y,w,h,lines) in enumerate(boxes):
 c=E.SubElement(r,'mxCell',id=name,value='\n'.join([name]+lines),vertex='1',parent='1',style='whiteSpace=wrap;html=0;fontSize=18;align=left;spacing=12;fillColor=#eef5fa;')
 E.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'})
 svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#eef5fa" stroke="#235983"/>')
 for j,line in enumerate([name]+lines):svg.append(f'<text x="{x+12}" y="{y+30+j*28}" font-family="sans-serif" font-size="18">{escape(line)}</text>')
for name,points,label in [('Role',[(240,320),(440,440)],'Role 0..N grants; each grant exactly 1 role'),('Permission',[(810,320),(700,440)],'Permission 0..N grants; each grant exactly 1 permission')]:
 c=E.SubElement(r,'mxCell',id='edge'+name,value=label,edge='1',parent='1',source=name,target='RolePermission',style='endArrow=none;fontSize=14;');E.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
 a,b=points;svg.append(f'<path d="M {a[0]} {a[1]} L {b[0]} {b[1]}" stroke="#235983" fill="none"/>');svg.append(f'<text x="{40 if name=="Role" else 850}" y="360" font-family="sans-serif" font-size="14">{name}: 0..N grants</text>');svg.append(f'<text x="{40 if name=="Role" else 850}" y="380" font-family="sans-serif" font-size="14">Each grant: 1 parent</text>')
svg.append('<text x="40" y="650" font-family="sans-serif" font-size="17">UserRole still maps users to roles. Existing 27 FKs remain unchanged.</text><text x="40" y="680" font-family="sans-serif" font-size="17">Scopes: SELF / OWN / PARTICIPATING / ALL. Business rules remain procedural.</text></svg>')
E.ElementTree(root).write(p/'Entitlements.drawio',encoding='utf-8',xml_declaration=True)
(p/'06-entitlements.svg').write_text(''.join(svg))
