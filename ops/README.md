# Local monitoring and response

Receiver: alerts.jsonl in ENTITLEMENTS_LOG_DIR. Request/SQL span events are in
operations.jsonl; failed database audit persistence falls back to audit-fallback.jsonl.
All files are private, bounded and local. No email/Slack is sent. The monitoring screen
requires a current permission.manage grant. Primary project reviewers: Anuvik and Tyler;
actual operational/on-call escalation ownership must be agreed before deployment.

| Rule | Level | Condition in rolling 60 seconds | Response |
| --- | --- | --- | --- |
| audit_evidence_lost | Critical | 1 fallback-write failure; latched until fallback works | Check disk/permissions and database audit; stop affected administration if evidence cannot be retained |
| audit_database_unavailable | High | 1 database-audit failure; additionally latched until persistence recovers | Check database connectivity/grants; preserve local evidence and reconcile uncertain actions |
| database_errors | High | 3 infrastructure failures | Inspect correlated SQL spans and server health; never blindly retry uncertain commits |
| repeated_denials | Warning | 10 denied attempts | Inspect safe reason/context; distinguish user mistakes from suspicious activity |
| database_contention | Warning | 3 SQL calls taking at least 500 ms | Inspect policy-lock contention/pool admission; keep transactions short |

One event per firing/resolved transition is emitted, grouped by rule; repeated occurrences
update counters without sending duplicate firing events. Background evaluation runs each
second. Window-only alerts resolve below threshold; latched audit alerts also require a
successful recovery observation. There is no automated external escalation or acknowledgement
workflow. An individual validation or stale-version conflict does not trigger Critical.

Thresholds are classroom defaults, not measured production SLOs. To configure, edit
alerts.json after review, restart the process and run the unit/integration tests. Protected
metrics report active alerts, total counters and active sessions. Local span/request timing
supports diagnosis; there is no remote tracing dependency. Retention is size-based (5 MB
plus one backup per file), not indefinite or tamper-proof evidence storage.

## Handout implementation and demonstration

Source: [Observability_DB.pdf](../docs/course/Observability_DB.pdf), especially pp.31–33.
The JSON rule configuration now declares `for_seconds`: zero for audit-evidence alerts,
five for ordinary database-error/denial/contention alerts. All retain their rolling
60-second occurrence window. A threshold must remain breached for the sustained duration;
one ordinary error is not an alert. Immediate audit-evidence alerts are intentional
integrity exceptions. Alert records include the service, route scope, condition, both
durations, severity, `/monitoring` link and a trace-search URL template.

After signing in to the administrator UI:

- Open `/monitoring` to inspect counters, capacity gauges, histogram buckets and alerts.
- Open `/metrics` to inspect authenticated Prometheus text exposition (counter/gauge/histogram).
- Copy a non-secret trace_id from operations.jsonl and open `/trace?context=TRACE_ID`.
  This displays root application and database/admission child spans with parent IDs.

The integration test generates representative traffic and injects/removes a controlled
SQL delay without touching development. Run it with installed MySQL binaries selected
by MYSQLD_BIN/MYSQL_CLIENT_BIN. Set OBSERVABILITY_REPORT to deliberately save the result;
see [recorded measurements](../docs/evidence/observability-before-after.json).

The diagnostic uses ten timed reads per phase. It checks identical results and that
removing the redundant wait improves median round-trip time by at least 80 ms. This is
an intentionally artificial delay, not an optimizer/index performance claim. A real
workload should instead compare query plans and latency distributions under the same
representative data/load before accepting an index or capacity change.

Metrics use bounded names and no user/loan/trace IDs as labels. Traces are manual local
records, not an installed OTel exporter. MySQL timing includes CLI/connection overhead;
local admission wait is separate. A real connection pool is not implemented. External
scraping, notification receivers and production sampling remain deployment choices.
