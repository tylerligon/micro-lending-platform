"""Bounded local telemetry, protected rotating evidence, and alert/recovery events."""
from collections import Counter, deque
import json
import os
from pathlib import Path
import threading
import time


class Telemetry:
    def __init__(self, directory, clock=time.time, rules=None):
        self.directory = Path(directory)
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self.clock, self.lock = clock, threading.RLock()
        self.gauges, self.histograms, self.pending = {}, {}, {}
        self.events, self.counts, self.active = deque(maxlen=10000), Counter(), set()
        self.rules = rules or json.loads((Path(__file__).parents[1]/'ops/alerts.json').read_text())
        self.fallback_broken = False
        self.audit_broken = False

    def write(self, filename, payload):
        path = self.directory/filename
        with self.lock:
            if path.exists() and path.stat().st_size >= 5_000_000:
                older = path.with_suffix(path.suffix+'.1')
                os.replace(path, older)
            fd = os.open(path, os.O_WRONLY|os.O_CREAT|os.O_APPEND, 0o600)
            try:
                os.fchmod(fd, 0o600)
                os.write(fd, (json.dumps(payload, separators=(',', ':'))+'\n').encode())
                os.fsync(fd)
            finally:
                os.close(fd)

    def log(self, kind, context, **fields):
        # Callers supply only approved technical fields, never bodies/SQL/passwords.
        record = {'time':self.clock(), 'level':'ERROR' if fields.get('outcome') in ('error','failed') else 'INFO', 'service':'lending-admin', 'kind':kind, 'context_id':context, 'trace_id':fields.pop('trace_id',context), **fields}
        try:
            self.write('operations.jsonl', record)
        except OSError:
            self.counts['operational_log_failures'] += 1
        return record

    def count(self, name):
        with self.lock:
            if name == 'audit_failures': self.audit_broken = True
            self.counts[name] += 1
            self.events.append((self.clock(), name))
            self.evaluate()

    def gauge(self, name, value=None, delta=0):
        with self.lock:
            self.gauges[name] = value if value is not None else self.gauges.get(name,0)+delta

    def observe(self, name, seconds):
        with self.lock:
            h = self.histograms.setdefault(name, {'bounds':[.005,.01,.025,.05,.1,.25,.5,1,2.5,5,10],
                                                  'buckets':[0]*11,'count':0,'sum':0.0})
            h['count'] += 1
            h['sum'] += seconds
            for i,bound in enumerate(h['bounds']):
                if seconds <= bound: h['buckets'][i] += 1

    def prometheus(self):
        with self.lock:
            lines=[]
            for name,value in sorted(self.counts.items()):
                lines += [f'# TYPE {name} counter', f'{name} {value}']
            for name,value in sorted(self.gauges.items()):
                lines += [f'# TYPE {name} gauge', f'{name} {value}']
            for name,h in sorted(self.histograms.items()):
                lines += [f'# TYPE {name} histogram']
                lines += [f'{name}_bucket{{le="{b}"}} {n}' for b,n in zip(h['bounds'],h['buckets'])]
                lines += [f'{name}_bucket{{le="+Inf"}} {h["count"]}',f'{name}_count {h["count"]}',f'{name}_sum {h["sum"]}']
            return '\n'.join(lines)+'\n'

    def trace(self, context):
        records=[]
        with self.lock:
            for path in [self.directory/'operations.jsonl.1', self.directory/'operations.jsonl']:
                if not path.exists(): continue
                for line in path.read_text().splitlines():
                    try: record=json.loads(line)
                    except ValueError: continue
                    if record.get('trace_id')==context: records.append(record)
        return records[-100:]

    def fallback(self, record):
        try:
            self.write('audit-fallback.jsonl', record)
            self.fallback_broken = False
        except OSError:
            self.fallback_broken = True
            self.count('audit_fallback_failures')

    def evaluate(self):
        now = self.clock()
        recent = Counter(name for at,name in self.events if now-at < self.rules['window_seconds'])
        for rule in self.rules['rules']:
            firing = recent[rule['metric']] >= rule['threshold']
            if rule['name'] == 'audit_database_unavailable' and self.audit_broken:
                firing = True
            if rule['name'] == 'audit_evidence_lost' and self.fallback_broken:
                firing = True
            if firing:
                since=self.pending.setdefault(rule['name'],now)
                firing=now-since >= rule.get('for_seconds',0)
            else: self.pending.pop(rule['name'],None)
            was = rule['name'] in self.active
            if firing != was:
                event = {'time':now, 'alert':rule['name'], 'severity':rule['severity'],
                         'state':'firing' if firing else 'resolved',
                         'service':'lending-admin','route':rule.get('route','all protected operations'),
                         'condition':f'{rule["metric"]} >= {rule["threshold"]}',
                         'window_seconds':self.rules['window_seconds'],'for_seconds':rule.get('for_seconds',0),
                         'dashboard':'/monitoring','trace_search':'/trace?context=<trace_id>'}
                try:
                    self.write('alerts.jsonl', event)
                except OSError:
                    # A terminal signal remains visible even if local disk evidence fails.
                    print(json.dumps(event), flush=True)
                if firing: self.active.add(rule['name'])
                else: self.active.discard(rule['name'])

    def audit_recovered(self):
        with self.lock:
            self.audit_broken = False
            self.evaluate()

    def snapshot(self):
        with self.lock:
            self.evaluate()
            return {'counters':dict(self.counts), 'gauges':dict(self.gauges),
                    'histograms':json.loads(json.dumps(self.histograms)), 'active_alerts':sorted(self.active),
                    'window_seconds':self.rules['window_seconds']}
