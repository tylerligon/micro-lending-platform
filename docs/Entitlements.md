# Configurable entitlements and administration

> **Follow-up implementation:** [Table-driven request workflows](Table_Driven_Workflows.md) adds three policy tables, console controls and audited versioned changes. It also corrects grant selection to consider resource scope across all eligible roles. Current model: 20 tables / 136 columns / 33 FKs; the 17-table counts below describe the prior entitlement increment.

October 30, 2026 — implemented entitlement contract, with the subsequent workflow amendment linked above.

The entitlement increment added Permission and RolePermission, taking the original
model to **17 tables, 126 columns and 29 FKs**. The current workflow extension brings
the complete build to **20 tables, 136 columns and 33 FKs**. Sessions and telemetry are
single-instance operational memory/files, not additional application tables. The
[editable extension](diagrams/Entitlements.drawio) and [SVG](diagrams/06-entitlements.svg)
define the additions to the original three-page lending model.

## Authorization contract

UserRole retains grant/revocation episodes. Role adds an immutable RoleClass
(Borrower/Lender/Administrator/Auditor), IsActive and RowVersion. Category preserves
business separation and permitted privacy boundaries; it does not automatically grant
action permissions. A new role starts with no grants. Administrators may create named
roles, edit descriptions, retire unassigned roles, and grant/revoke supported capabilities.

Permission defines implemented capability codes with supported scopes per business
category and AllowRestricted. RolePermission maps (RoleCode, PermissionCode) to ScopeCode.
Both columns form its PK and reference their respective parent PKs. Each grant has
exactly one role/permission parent; either parent may have zero or many grants.
The six Permission columns and three RolePermission columns are defined in
[025_entitlements.sql](../database/02_programmability/025_entitlements.sql).

Supported scopes: SELF compares actor/target; OWN checks request ownership (loan owner
through LoanRequest); PARTICIPATING checks Applied commitments via OperationReceipt;
ALL applies to the named action only. Scoped loan/request SQL reads expose fixed safe
fields, never income, private email, passwords, private notes or other lenders' identities.
There is no administrator-configurable arbitrary SQL, dynamic field expression, new
business category or unimplemented lending action. Permission contracts remain
version-controlled developer code/data; administrators configure grants within them.

Existing account/profile/Draft/submission/cancellation actions use sp_require_permission.
Membership assignment remains subject to separation of duties and live-obligation checks.
permission.manage is a protected bootstrap capability: it cannot be modified through the
UI; assigning/removing a role containing it requires that capability. The last active
access administrator cannot be removed/restricted/deactivated. Retire roles only after
all memberships are revoked. Category cannot change after creation.

Configuration updates require current Role.RowVersion and increment it. Conflicting
same-role edits return HTTP 409; the caller refreshes instead of overwriting newer work.
Grant/revoke takes effect on subsequent protected actions even in existing sessions.
An action already holding the policy lock may commit before a waiting revocation.

## Authentication and sessions

The former single environment credential/actor ID is removed. Each administrator signs
in independently using User.LoginName and a real password hash. The accepted implemented
hash format is salted scrypt (N=16384,r=8,p=1), using Python's standard library. Existing
fixture markers are deliberately not valid passwords. Other hash formats, including the
older TDD's proposed Argon2 target, are not silently accepted. Passwords are never placed
in arguments, cookies, logs, responses or committed fixtures.

Server-side sessions store SHA-256 token hashes, UserID, creation/last-use times and a
per-session CSRF secret. The opaque cookie is HttpOnly, SameSite=Strict, Path=/; enable
Secure when serving through HTTPS. Sessions have a 30-minute idle and 8-hour absolute
expiry, a 1,000-session process cap, rotation on login and independent logout. Login is
limited to ten attempts per client address per minute. Unknown credentials receive
identical safe errors; unauthenticated attempts are not attributed to claimed user IDs.

The server derives actors from sessions, never browser payloads. Current account status
is rechecked on every protected request; current roles/grants are checked by controlled
SQL operations. A role revocation does not have to erase the session to stop its actions.
The matrix and monitoring require live permission.manage. The application currently
provides administration, not Borrower/Lender screens or new lending workflows.

## Concurrency and transactions

A bounded executor processes up to eight requests, with at most sixteen admitted/queued
requests. Database work is bounded to four concurrent mysql-client connections. Each
invocation has its own connection and actor/context; no pooled/shared transaction or
mutable global actor is reused. This is connection admission control, not a persistent
connection pool. Requests have socket/SQL/connect/lock time bounds; overload is rejected.

Protected actions acquire the canonical Administrator Role policy lock before User locks,
then relevant membership/record locks. User pairs are ordered by ID. The global lock
still serializes protected DB actions; concurrent sessions and HTTP requests remain
independent. This is a deliberate correctness baseline, not a throughput scaling claim.
Measure wait/hold times and prove a finer per-role protocol before removing it.

Procedures own whole-action transactions, helpers do not commit, and callers must not
nest transactions. Submission still requires prepare/finish on the same reserved
connection; it is not exposed by this console. The CLI adapter is for these short
administration commands, not the two-call submission protocol. Before a future application
submission endpoint, use a reserved real connector connection across that sequence.

Only explicit deadlock/lock-timeout failures with rollback are retried, at most three
attempts. Each attempt has its own context linked to the request retry log. Validation
conflicts are not retried. Lost responses/process timeouts are returned as uncertain;
no blind transport retry is attempted because configuration lacks durable command receipts.
Runtime procedures execute as their trusted installer (DEFINER). Review that account;
the dedicated runtime account receives narrow public routine grants and metadata reads,
never general table writes/raw audit reads/helper execution.

## Audit, failure evidence and privacy

Business changes and success AuditEvent/AuditChange writes commit atomically. Configuration
uses RoleConfigured/PermissionConfigured with Role/RolePermission subjects and a safe
Configuration field, recording the actual actor/role and before/after grant values.
Existing early-workflow audit helper checks role category while retaining actual role.

All implemented public action/read procedures roll back before recording a separate
AttemptRejected or TransactionFailed observation. The HTTP boundary also covers missing
sessions, failed login, CSRF, input errors, and unavailable SQL. It checks the context for
existing SQL failure evidence to avoid duplication. The trusted gateway owns a request
context; clients cannot supply it. SQL-only demonstrations generate their own contexts.
Failure inserts do not contain private payloads. SQL failure logging errors cannot replace
the original exception. GET STACKED DIAGNOSTICS preserves the initiating SQL error.

Stable external errors distinguish 401 authentication, 403 permission/scope, 409 stale
version, 400 invalid input and 503 infrastructure failures. Context and uncertainty/retry
flags are returned without SQL text or private data. Some business validation failures
share INVALID_INPUT; this is not a full error-per-invariant taxonomy.

When database failure evidence cannot be persisted, a protected local fallback record
and High alert are produced. If fallback also fails, Critical remains latched until a
successful fallback write; an alert signal is printed if the alert file itself cannot
be written. This is bounded best-effort evidence, not guaranteed delivery through a
process/host crash. There is no automatic replay of fallback rows into MySQL. Required
success-audit failures still roll back business writes. Raw table changes by a build
administrator are outside application-controlled audit; runtime privileges deny them.

## Logging, observability and alerts

[ops/alerts.json](../ops/alerts.json) defines actual thresholds. The protected monitoring
screen shows counters, active alerts and active-session count. Structured request and
MySQL span events share contexts; retry events link attempt contexts. Span duration gives
request-to-database timing without SQL arguments or private financial inputs. This is a
local trace implementation, not an external tracing backend.

Logs/fallback/alert events use a 0700 directory and 0600 files. Each stream rotates at
5 MB with one prior file (approximately 10 MB per stream); counters and alert windows
are bounded process memory. No secrets or unrestricted request bodies are logged. IDs
are used for context lookup in evidence, not unbounded metric labels. Files remain local
and require deliberate cleanup; no time-based retention or off-host archival is claimed.

A background evaluator checks rules every second. Repeated alerts are grouped by rule,
and firing/resolved transitions are written to the local receiver alerts.jsonl. There
are no external messages. Audit-unavailable state remains latched until successful
persistence is observed; evidence-loss state requires successful fallback recovery.
Threshold/window details and response actions are in [ops/README.md](../ops/README.md).
These levels are the team's proposal pending professor confirmation, not a claimed
verbatim reconstruction of the earlier alerting discussion.

## Run, upgrade and test

1. Fresh demonstration: `bash build/demo_midterm.sh`. It refuses an existing dedicated
   demo DB. No development reset/fixture is automatic.
2. Existing committed 1deed92 database: back up and stop callers, inspect
   `build/upgrade_entitlements.sh`, then run once with the appropriate private login.
   DDL is not atomic; inspect a partial failure instead of blindly retrying. Upgrade
   preserves existing users, requests, memberships and audit records.
3. With a separate **setup administrator** login path, run
   `python3 app/provision_admin.py USER_ID` to set a fictional administrator's real
   application password at private prompts. A second administrator requires its own
   User row and Administrator membership through existing controlled setup operations.
4. Create a private MySQL runtime account; apply the reviewed example
   `database/entitlements_console_grants.sql`, adapting only the database/account names.
   Save its connection in mysql_config_editor. Do not expose installer credentials.
5. Set MYSQL_BIN, MYSQL_LOGIN_PATH, ENTITLEMENTS_DATABASE and ENTITLEMENTS_LOG_DIR as
   needed. Start `python3 app/admin_console.py`, open http://127.0.0.1:8765, and sign in
   with separate accounts in separate browser profiles. There is no environment actor ID.
6. Behind a trusted HTTPS terminator, set ENTITLEMENTS_SECURE_COOKIE=1 and
   ENTITLEMENTS_PUBLIC_ORIGIN to the exact public origin; this application binds loopback.
   Remote/public deployment and proxy trust require separate review.

Unit tests: `python3 -m unittest discover -s tests/entitlements -v`.
SQL tests: `bash build/test_entitlements.sh` creates only a fresh dedicated test database.
Full integration: set MYSQLD_BIN and MYSQL_CLIENT_BIN to installed MySQL 8.4 binaries,
then `python3 tests/entitlements/integration.py`. It starts/stops its own disposable
server and does not connect to a development database. Linux binaries may need their
library paths configured externally. No MySQL distribution is committed.

## Evidence and remaining boundaries

Isolated MySQL 8.4.6 testing covers the revised 45 midterm and 87 early-workflow checks,
new SQL entitlement cases, the upgrade from 1deed92, and real HTTP requests through the
least-privilege runtime account. Concurrency cases include two distinct administrators,
same-role conflict, different-role updates, immediate revocation, and last-admin removal
races. Authentication/CSRF denials, one failure observation per attempt, real connection
failure/fallback, recovery writes, and absence of credentials/CSRF secrets in logs are
checked. Unit tests cover password verification, expiry/logout, SQL encoding, verified
actor binding, bounded retry rules and alert firing/recovery/fallback failure.

Sessions are in-memory for one application process; restart signs everyone out. Horizontal
replicas require a shared session store and coordinated rate limiting. Global policy
serialization and the CLI connection adapter are not a high-throughput deployment.
The original JSON model verifier is a design-baseline tool, not runtime/security evidence.
The actual application schema extension is recorded here and tested in MySQL. No developer
database, real money, assessment/funding/repayment workflow or external notification was
added. Sustained load, public deployment and native diagrams.net round-trip are not claimed.

## Observability handout alignment — October 30

The supplied [Observability_DB.pdf](course/Observability_DB.pdf), pp.31–33, now supplies
explicit observability acceptance goals. The implementation uses manual instrumentation;
OpenTelemetry SDK, a collector, Prometheus server and Grafana are examples/options in
the handout, not dependencies added to this classroom application.

| PDF deliverable | Current artifact and evidence |
| --- | --- |
| 1. ERD and normalized schema | Original lending ERD plus permission/workflow extensions; current 20-table schema |
| 2. DDL and representative seed | database/schema.sql, 024_entitlement_tables.sql, 026_request_workflow.sql, reference/policy and fictional seed SQL |
| 3. Four database-backed operations | Sign-in lookup, permission matrix, role configuration, grant configuration and membership management |
| 4. Structured request/database-error logs | operations.jsonl includes time, level, service, outcome, context/trace ID, span ID, safe operation name and timing |
| 5. Counter, histogram and gauge | db_operations_total; db_client_duration_seconds and http_request_duration_seconds histograms; db_connection_slots_in_use/capacity and http_requests_in_progress gauges |
| 6. Application + database trace | Root request span with child db.acquire_slot and mysql.client_round_trip spans, start/end times and explicit parent_span_id |
| 7. Introduced issue | Disposable-server diagnostic adds a redundant 150 ms server wait to a constant-data SELECT |
| 8. Diagnosis and before/after remediation | Recorded ten samples per phase, p50/p95, identical outputs and a correlated trace in docs/evidence/observability-before-after.json |
| 9. Run/traffic/telemetry instructions | Commands here and ops/README.md; repeatable HTTP and diagnostic workload in integration.py |

Authenticated administrators can open `/metrics` for Prometheus text exposition,
`/monitoring` for the JSON monitoring screen, and `/trace?context=TRACE_ID` to retrieve
up to 100 retained events for a trace. The latter requires a 32-character hexadecimal ID
from the operational log. Session cookies authenticate these endpoints; do not copy
session tokens into reports, scrape configs or committed files. A production scraper
needs a separately reviewed machine authentication mechanism. No scrape backend is claimed.

Histograms have cumulative finite buckets, +Inf, sum and count. Connection admission
wait and the client/server round trip are timed separately. Round-trip duration includes
CLI process/connection setup and server SQL/lock time; it must not be called pure SQL
engine execution time. This adapter bounds concurrent connections but does not reuse
connections, so its gauges are admission slots, not a real driver's connection pool.
The handout's pooling discussion remains guidance for a future driver/pool implementation.

The measured demonstration changed only the injected wait (SLEEP(0.15) to SLEEP(0));
it returned identical values and used one client, the same database and the same telemetry
in both phases. Observed p50 was **181.68 → 30.07 ms**, p95 **224.68 → 38.36 ms** on isolated
MySQL 8.4.6. This proves diagnosis/remediation of the controlled delay, not a production
speedup or index benchmark. Detailed samples, timing boundaries and source hashes are
retained in the JSON evidence. Durations will vary on another machine.

Reproduce and refresh evidence deliberately:

```bash
# MYSQLD_BIN and MYSQL_CLIENT_BIN must already point to installed MySQL 8.4 binaries.
OBSERVABILITY_REPORT=docs/evidence/observability-before-after.json python3 tests/entitlements/integration.py
```

Without OBSERVABILITY_REPORT the test prints measurements but does not replace the
checked-in candidate evidence. Tests now include nine unit cases plus the 45/87 SQL
checks, real protected metrics/trace endpoint checks, and the measured diagnosis workload.
Alert payloads include condition, rolling window, sustained duration, service/route,
severity and investigation links. Ordinary repeated-denial/contention/database-error
alerts require a five-second sustained breach; evidence-loss alerts are explicit
immediate exceptions. The named severity hierarchy is still a team proposal, not a
hierarchy prescribed by the PDF.
