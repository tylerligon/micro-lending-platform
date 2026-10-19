"""Export our plain-text mxGraph shapes and routed edges to standalone SVG.

Reads the editable draw.io XML, not a separately maintained picture. Unsupported
shapes fail explicitly. Native draw.io exports can also replace these exports.
"""
from pathlib import Path
import hashlib
import xml.etree.ElementTree as ET

NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
def S(tag,attrs=None): return ET.Element('{'+NS+'}'+tag, {k:str(v) for k,v in (attrs or {}).items()})
def style(cell):
    return dict(v.split('=',1) for v in cell.get('style','').split(';') if '=' in v)
def absolute_geometry(cell,cells):
    geo=cell.find('mxGeometry')
    x,y,w,h=[float(geo.get(k,'0')) for k in ('x','y','width','height')]
    parent=cells.get(cell.get('parent'))
    while parent is not None and parent.find('mxGeometry') is not None:
        pg=parent.find('mxGeometry');x+=float(pg.get('x','0'));y+=float(pg.get('y','0'))
        parent=cells.get(parent.get('parent'))
    return x,y,w,h
def text_into(parent,cell,x,y,w,h,st):
    value=cell.get('value','')
    if not value: return
    fs=float(st.get('fontSize',14)); lines=value.split('\n'); lh=fs*1.25
    align=st.get('align','center'); valign=st.get('verticalAlign','middle')
    tx=x+(0 if align=='left' else w if align=='right' else w/2)
    top=y if valign=='top' else y+h-len(lines)*lh if valign=='bottom' else y+(h-len(lines)*lh)/2
    attrs={'x':tx,'y':top+fs,'font-family':st.get('fontFamily','DejaVu Sans'),'font-size':fs,
        'fill':st.get('fontColor','#153047'),'text-anchor':{'left':'start','right':'end','center':'middle'}[align]}
    f=int(st.get('fontStyle',0))
    if f&1: attrs['font-weight']='bold'
    if f&2: attrs['font-style']='italic'
    if f&4: attrs['text-decoration']='underline'
    t=S('text',attrs)
    for i,line in enumerate(lines):
        sp=S('tspan',{'x':tx,'dy':0 if i==0 else lh});sp.text=line;t.append(sp)
    parent.append(t)

def export(path):
    path=Path(path); raw=path.read_bytes(); mx=ET.fromstring(raw)
    pages=mx.findall('diagram')
    import json
    model=json.loads(path.with_name('model.json').read_text())
    names={p['id']:p['export'] for p in model['pages']+model.get('design_pages',[])}
    outputs=[]
    for page in pages:
        outputs.append(export_page(path,raw,page,names[page.get('id')]))
    return outputs

def export_page(path,raw,page,filename):
    graph=page.find('mxGraphModel'); root=graph.find('root')
    svg=S('svg',{'width':graph.get('pageWidth'),'height':graph.get('pageHeight'),
        'viewBox':f"0 0 {graph.get('pageWidth')} {graph.get('pageHeight')}",
        'data-source':path.name,'data-source-sha256':hashlib.sha256(raw).hexdigest(),
        'data-page-id':page.get('id'),'role':'img','aria-label':page.get('name')})
    title=S('title');title.text=page.get('name');svg.append(title)
    svg.append(S('rect',{'width':'100%','height':'100%','fill':'#ffffff'}))
    defs=S('defs');marker=S('marker',{'id':'arrow','viewBox':'0 0 10 10','refX':9,'refY':5,'markerWidth':7,'markerHeight':7,'orient':'auto-start-reverse'})
    marker.append(S('path',{'d':'M 0 0 L 10 5 L 0 10 z','fill':'#235983'}));defs.append(marker);svg.append(defs)
    cells={c.get('id'):c for c in root.findall('mxCell')}
    for cell in cells.values():
        geo=cell.find('mxGeometry')
        if geo is None: continue
        st=style(cell); group=S('g',{'data-cell-id':cell.get('id')})
        stroke=st.get('strokeColor','#cbd5e1');fill=st.get('fillColor','none')
        attrs={'stroke':stroke,'fill':fill,'stroke-width':st.get('strokeWidth','1.4')}
        if st.get('dashed')=='1': attrs['stroke-dasharray']='6 4'
        if cell.get('edge')=='1':
            a=geo.find("mxPoint[@as='sourcePoint']");b=geo.find("mxPoint[@as='targetPoint']")
            def anchor(which,fallback):
                connected=cells.get(cell.get(which))
                if connected is None:
                    return float(fallback.get('x')),float(fallback.get('y'))
                x,y,w,h=absolute_geometry(connected,cells)
                prefix='exit' if which=='source' else 'entry'
                return x+w*float(st.get(prefix+'X','0.5')),y+h*float(st.get(prefix+'Y','0.5'))
            pts=[anchor('source',a)]
            arr=geo.find("Array[@as='points']")
            if arr is not None: pts += [(float(p.get('x')),float(p.get('y'))) for p in arr]
            pts += [anchor('target',b)]
            if st.get('endArrow','none')!='none':attrs['marker-end']='url(#arrow)'
            attrs['fill']='none';attrs['points']=' '.join(f'{x},{y}' for x,y in pts)
            group.append(S('polyline',attrs))
        else:
            x,y,w,h=absolute_geometry(cell,cells)
            shape=st.get('shape','rectangle')
            if shape=='text': pass
            elif shape=='rectangle':
                group.append(S('rect',dict(attrs,x=x,y=y,width=w,height=h)))
            elif shape=='ellipse':
                group.append(S('ellipse',dict(attrs,cx=x+w/2,cy=y+h/2,rx=w/2,ry=h/2)))
            elif shape=='rhombus':
                group.append(S('polygon',dict(attrs,points=f'{x+w/2},{y} {x+w},{y+h/2} {x+w/2},{y+h} {x},{y+h/2}')))
            else: raise ValueError(f'Unsupported shape {shape}')
            text_into(group,cell,x,y,w,h,st)
        svg.append(group)
    out=path.with_name(filename);ET.indent(svg)
    out.write_bytes(ET.tostring(svg,encoding='utf-8',xml_declaration=True))
    return out

if __name__=='__main__':
    import sys
    paths=[Path(p) for p in sys.argv[1:]] or sorted(Path(__file__).resolve().parents[1].glob('*.drawio'))
    for p in paths:
        for out in export(p): print(out.name)
