import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[2]/'app'))
import tempfile
import unittest
from unittest.mock import patch
from admin_console import Database,ActionError,literal
from security import Sessions,hash_password,verify_password
from telemetry import Telemetry

class ConsoleTests(unittest.TestCase):
    def test_literals_never_interpolate_sql(self):
        value="'); DROP TABLE User; --"
        self.assertNotIn(value,literal(value))
        self.assertIn(value.encode().hex(),literal(value))
        self.assertEqual(literal(None),'NULL')

    def test_actor_comes_from_session_not_payload(self):
        db=Database(actor=5)
        with patch.object(db,'query',return_value=[]) as query:
            db.action('/permission',dict(actor=1,role='Borrower',permission='request.cancel',scope=None,version=0))
            self.assertTrue(query.call_args.args[0].startswith('CALL sp_configure_permission(5,'))

    def test_version_type(self):
        with self.assertRaises(ValueError):
            Database(actor=5).action('/permission',dict(role='Borrower',permission='request.cancel',scope=None,version='0;DROP'))

    def test_passwords_and_placeholder_rejection(self):
        encoded=hash_password('a fictional password')
        self.assertTrue(verify_password('a fictional password',encoded))
        self.assertFalse(verify_password('wrong password',encoded))
        self.assertFalse(verify_password('a fictional password','fixture-not-a-login'))

    def test_independent_hashed_sessions_and_expiry(self):
        now=[0];sessions=Sessions(clock=lambda:now[0],idle=10,absolute=20)
        a,_=sessions.create(5);b,_=sessions.create(9)
        self.assertNotIn(a,sessions.rows)
        sessions.revoke(a);self.assertIsNone(sessions.get(a))
        self.assertEqual(sessions.get(b)['user'],9)
        now[0]=11;self.assertIsNone(sessions.get(b))
        c,_=sessions.create(5)
        now[0]=19;self.assertIsNotNone(sessions.get(c))
        now[0]=27;self.assertIsNotNone(sessions.get(c))
        now[0]=31;self.assertIsNone(sessions.get(c))

    def test_retry_only_explicit_rollback_errors(self):
        db=Database(actor=5)
        data=dict(role='Borrower',permission='request.cancel',scope=None,version=0)
        with patch.object(db,'query',side_effect=[ActionError('DB_DEADLOCK',503,1213),[]]) as q:
            db.action('/permission',data);self.assertEqual(q.call_count,2)
        with patch.object(db,'query',side_effect=ActionError('CONNECTION_LOST',503,2013,True)) as q:
            with self.assertRaises(ActionError):db.action('/permission',data)
            self.assertEqual(q.call_count,1)

    def test_alerts_fire_recover_and_fallback_failure_stays_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            now=[0];telemetry=Telemetry(directory,clock=lambda:now[0])
            telemetry.count('audit_failures')
            self.assertIn('audit_database_unavailable',telemetry.snapshot()['active_alerts'])
            now[0]=61
            self.assertIn('audit_database_unavailable',telemetry.snapshot()['active_alerts'])
            telemetry.audit_recovered()
            self.assertNotIn('audit_database_unavailable',telemetry.snapshot()['active_alerts'])
            original=telemetry.write
            def broken(name,payload):
                if name=='audit-fallback.jsonl':raise OSError('test sink failure')
                return original(name,payload)
            with patch.object(telemetry,'write',side_effect=broken):telemetry.fallback({'reason':'DB_ERROR'})
            now[0]=200
            self.assertIn('audit_evidence_lost',telemetry.snapshot()['active_alerts'])
            telemetry.fallback({'reason':'DB_ERROR'})
            self.assertNotIn('audit_evidence_lost',telemetry.snapshot()['active_alerts'])
            self.assertIn('resolved',Path(directory,'alerts.jsonl').read_text())

    def test_histogram_gauge_and_prometheus_export(self):
        with tempfile.TemporaryDirectory() as directory:
            telemetry=Telemetry(directory)
            telemetry.count('db_operations_total')
            telemetry.gauge('db_connection_slots_in_use',1)
            telemetry.observe('db_client_duration_seconds',.02)
            telemetry.observe('db_client_duration_seconds',.2)
            exported=telemetry.prometheus()
            self.assertIn('# TYPE db_operations_total counter',exported)
            self.assertIn('# TYPE db_connection_slots_in_use gauge',exported)
            self.assertIn('db_client_duration_seconds_bucket{le="0.025"} 1',exported)
            self.assertIn('db_client_duration_seconds_bucket{le="+Inf"} 2',exported)
            self.assertIn('db_client_duration_seconds_count 2',exported)

    def test_alert_requires_sustained_condition_and_has_investigation_links(self):
        with tempfile.TemporaryDirectory() as directory:
            now=[0]
            rules={'window_seconds':60,'rules':[dict(name='sustained_error',severity='warning',metric='errors',threshold=2,for_seconds=5)]}
            telemetry=Telemetry(directory,clock=lambda:now[0],rules=rules)
            telemetry.count('errors');telemetry.count('errors')
            self.assertNotIn('sustained_error',telemetry.snapshot()['active_alerts'])
            now[0]=5
            self.assertIn('sustained_error',telemetry.snapshot()['active_alerts'])
            import json
            alert=json.loads(Path(directory,'alerts.jsonl').read_text().splitlines()[0])
            self.assertEqual(alert['for_seconds'],5)
            self.assertEqual(alert['dashboard'],'/monitoring')
            self.assertIn('trace_search',alert)
            now[0]=61
            self.assertNotIn('sustained_error',telemetry.snapshot()['active_alerts'])

if __name__=='__main__':unittest.main()
