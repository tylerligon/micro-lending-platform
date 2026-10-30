"""Controlled performance diagnosis: redundant server delay, same returned data.
Called by the disposable-server integration suite; never loads or resets development.
"""
from datetime import datetime,timezone
import hashlib,json,math,platform,secrets,statistics,time
from pathlib import Path
import sys
ROOT=Path(__file__).parents[2]
sys.path.insert(0,str(ROOT/'app'))
from admin_console import Database


def run(telemetry,samples=10):
    report={'scenario':'Unnecessary server-side wait in a read operation',
            'injected_issue':'An explicitly added SELECT SLEEP(0.15) delays the response without changing its data',
            'diagnosis':'The database round-trip child span dominates; admission waiting remains separately visible',
            'remediation':'Remove the redundant wait; leave the response and database constraints unchanged',
            'controls':'One client, same isolated MySQL server, same result, same instrumentation, no concurrent load',
            'timing_boundary':'mysql CLI connection establishment plus server execution, not SQL engine time alone',
            'percentile_method':'nearest-rank p95; p50 is median',
            'samples_per_phase':samples,'recorded_at':datetime.now(timezone.utc).isoformat(),
            'python':platform.python_version(),'platform':platform.system(),
            'source_hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in
                             [ROOT/'app/admin_console.py',ROOT/'app/telemetry.py',Path(__file__)]}}
    Database(telemetry=telemetry).query('SELECT 1;') # Warm client/server path before timing.
    example=None
    for phase,wait in [('before',.15),('after',0)]:
        durations=[]
        for i in range(samples):
            context,span=secrets.token_hex(16),secrets.token_hex(8)
            db=Database(context=context,telemetry=telemetry,parent_span=span)
            start,at=time.monotonic(),time.time()
            rows=db.query(f'SELECT 42 AS value,SLEEP({wait}) AS pause;')
            elapsed=time.monotonic()-start
            assert rows==[{'value':'42','pause':'0'}],rows
            durations.append(elapsed*1000)
            telemetry.observe('http_request_duration_seconds',elapsed)
            telemetry.log('request',context,span_id=span,parent_span_id=None,name='diagnostic_read',
                          component='application',action='diagnostic_read',start_time=at,end_time=time.time(),
                          duration_ms=elapsed*1000,outcome='success')
            if phase=='before' and i==0:example=context
        report[phase]={'durations_ms':durations,'p50_ms':statistics.median(durations),
                       'p95_ms':sorted(durations)[math.ceil(.95*len(durations))-1]}
    assert report['before']['p50_ms']-report['after']['p50_ms']>80,report
    trace=telemetry.trace(example)
    app=next(x for x in trace if x.get('parent_span_id') is None and x['kind']=='request')
    child=next(x for x in trace if x.get('component')=='mysql')
    assert child['parent_span_id']==app['span_id'] and child['trace_id']==app['trace_id']
    report['example_trace']=trace
    report['metrics']=telemetry.snapshot()
    return report
