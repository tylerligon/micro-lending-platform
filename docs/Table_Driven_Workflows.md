# Table-driven request workflows

Implemented October 30, 2026, following the professor's request for table-driven entitlements and workflow management. This extends `189ed0f`; it does not implement the remaining lending stages. The current build has **20 tables, 136 columns and 33 foreign keys**: the original 15 lending tables, two permission tables, and three workflow tables.

## What changed

Previously the request procedures each chose their permission, checked a literal allowed state, and wrote a literal destination state. Now a common helper reads those decisions from relational tables. Procedures still implement their named business effect and enforce ownership, account eligibility, versions, money constraints, frozen snapshots, locks and atomic audit. No database row contains executable SQL or a Python function path.

| ActionCode | FromState | ToState | PermissionCode | SuccessEventType |
| --- | --- | --- | --- | --- |
| CreateDraft | NotCreated | Draft | request.create | RequestSaved |
| EditDraft | Draft | Draft | request.edit | RequestSaved |
| SubmitRequest | Draft | Submitted | request.submit | RequestSubmitted |
| CancelDraft | Draft | Cancelled | request.cancel | RequestCancelled |

`NotCreated` is a rule source for creation, not a valid stored LoanRequest status. Disabled or absent transitions are rejected. States needed by historical fixtures are listed, but there are no executable assessment, approval, funding, expiration or repayment action rows: their handlers do not exist yet.

This implements table-driven policy for the existing request commands. It does not claim that inserting a row implements a new financial operation, that every business rule can be expressed as a foreign key, or that a durable background workflow engine is finished.

## Tables and integrity

Definitions: [workflow SQL](../database/02_programmability/026_request_workflow.sql). Initial rules: [seed SQL](../database/04_seed/016_request_workflow.sql). [Editable diagram](diagrams/Request_Workflow.drawio) · [SVG](diagrams/07-request-workflow.svg).

| Table | Columns and purpose | Keys and relationships |
| --- | --- | --- |
| RequestWorkflowState | StateCode VARCHAR(20); Description VARCHAR(255), nonblank | StateCode PK. Referenced separately as source and destination. |
| RequestWorkflowAction | ActionCode VARCHAR(32); PermissionCode VARCHAR(40); SuccessEventType VARCHAR(40) | ActionCode PK; PermissionCode FK to Permission. One implemented action has one required capability and success-event type. |
| RequestWorkflowTransition | ActionCode VARCHAR(32); FromState VARCHAR(20); ToState VARCHAR(20); IsEnabled BOOLEAN; RowVersion BIGINT UNSIGNED | Composite PK(ActionCode, FromState); FKs to action, source and destination. Exactly one destination per action/source pair. IsEnabled must be 0/1; destination cannot be NotCreated. |

All columns are NOT NULL. Code columns use `utf8mb4_0900_bin`. Configuration relationships use restrictive FK behavior. An action may have zero or more transition rows; a state may have zero or more incoming/outgoing rules. The existing LoanRequest CHECK continues to enforce its approved D1 state domain. These three tables add four FKs and three CHECKs; the full build has 58 CHECKs, 28 procedures, two functions, four views and two triggers.

The schema rejects unknown capabilities, unknown states, duplicate action/source rules and invalid enabled flags. Permission-to-role-category scope compatibility remains checked by the existing controlled permission procedure; this increment does not claim to normalize that separate contract into additional FK tables.

## Enforcement and authorization

`sp_require_request_transition` is an internal helper, with no runtime EXECUTE grant. Each existing public command passes its fixed action identifier. The helper reads the required permission from RequestWorkflowAction, applies the current scoped grants, locks the request, checks RowVersion, and resolves an enabled rule for its current state. It returns the selected role, destination and success-event type to the handler. Creation uses the synthetic NotCreated source.

The helper does not commit. Public procedures retain ownership of the whole action transaction. The existing policy mutex is taken first; request changes and required success audits commit together. Preparation and finish both check the submission rule on the same reserved connection while retaining the policy lock. An already-started command may commit before a waiting policy change; subsequent commands observe the changed policy.

The permission helper now selects a role whose **permission and resource scope both match**. It no longer selects Borrower first and rejects a dual-role user before considering their valid Lender participation. Explicit chosen-role calls still constrain evaluation to that role; they do not silently substitute another role.

The financial guards stay in executable handlers: principal limits, allowed installment counts, authenticated encryption coordination, freezing submitted inputs and rejecting inconsistent Draft children. The frozen-terms trigger still protects financial history. These are correctness controls, not configurable routes around the workflow rules.

## Administration and audit

The existing administrator console now shows the four workflow rows and an Enable/Disable button for each. `GET /workflow` and `POST /workflow` require a live `permission.manage` grant. POST additionally requires the existing session CSRF token. Actors come from the authenticated session, not the payload.

`sp_set_request_transition(actor, action, sourceState, enabled, expectedVersion)` updates only IsEnabled and RowVersion. It cannot create actions, change required permissions, redirect destinations or choose arbitrary audit events. Those definition changes require a reviewed migration together with handler/tests. This keeps a configuration administrator from enabling unfinished lending effects.

Every successful policy update writes `WorkflowConfigured` / `Success`, subject `WorkflowTransition`, key `ActionCode/FromState`, verified administrator role and context. One Configuration detail stores old/new enabled values as 0 or 1. Audit failure rolls back the policy update and version increment. Denials/SQL failures follow the existing post-rollback observation/fallback path. The previously noted general failure-role/target attribution gaps remain separate follow-up work; this change does not claim to fix those throughout the system.

Stale policy versions return 409 through the console; refresh before another edit. Concurrent changes using the same version have one winner. Runtime grants allow reading nonprivate policy metadata and executing the controlled setter, not direct configuration-table writes or transition-helper calls.

## Demonstrate table-driven behavior

In an isolated demo database with current objects and runtime grants:

1. Sign into the administration console. Read the workflow table: the required permission and destination are visible as stored data.
2. Create a fictional Draft using the existing SQL command; retain its returned ID and RowVersion.
3. Disable EditDraft in the console. Calling `sp_update_loan_request` now fails with `Workflow transition unavailable`. The request terms and version remain unchanged.
4. Enable EditDraft again. The same valid edit now succeeds without deploying different procedure code.
5. Inspect the two WorkflowConfigured events and their 1→0 / 0→1 Configuration changes using a privileged demonstration connection. Runtime users cannot read raw audit tables.
6. Cancel the Draft. Editing or submitting it fails because no rule exists for those actions from Cancelled.

For a read-only SQL view of the rules:

```sql
SELECT t.ActionCode, t.FromState, t.ToState,
       a.PermissionCode, a.SuccessEventType, t.IsEnabled, t.RowVersion
FROM RequestWorkflowTransition t
JOIN RequestWorkflowAction a USING (ActionCode)
ORDER BY t.ActionCode, t.FromState;
```

The automated version is [request_workflow.sql](../tests/sql/request_workflow.sql); do not run that destructive test fixture against development data.

## Build and upgrade

Fresh builds include the new files through [manifest.txt](../database/manifest.txt) and the current build/demo/test scripts. Permission table creation has been split into `024_entitlement_tables.sql`; `025_entitlements.sql` contains routines, allowing upgrades to replace routines without trying to recreate existing permission tables.

For a database at **189ed0f**, take a backup, stop callers, and run `bash build/upgrade_request_workflow.sh` from the repository root with the intended MYSQL_BIN / MYSQL_LOGIN_PATH / MYSQL_DATABASE. The migration preserves business records and existing role grants. It adds workflow tables, seeds rules, extends audit vocabulary, and replaces affected routines. Reapply the reviewed [runtime grant file](../database/entitlements_console_grants.sql), adapting its database/account names, before restarting the console. Replacing routines can discard routine-specific grants.

This is one-time DDL, not an atomic or retry-safe migration. Inspect a partial failure instead of rerunning blindly. Earlier upgrade scripts are now pinned to their historical target commit so they do not accidentally install current routines before their dependencies; run the appropriate stages in order. No migration was applied to the user's development or demo database during this task.

`fn_action_context` also replaces mixed-type COALESCE expressions: it returns a binary UUID or an explicitly binary existing context. This fixes the observed random binary-to-UTF-8 conversion failure during Draft editing on the installed MySQL 26.7.0.

## Validation and remaining scaling work

The disposable integration suite covers the existing 45 midterm and 87 early-workflow checks, workflow FK constraints, enabling/disabling each action, missing/terminal rules, stale versions, unauthorized changes, forced audit rollback, valid dual-role participation, upgrade preservation, narrow runtime privileges, real HTTP/CSRF checks and concurrent policy edits. It starts its own local MySQL server and removes only that temporary server's data.

Run:

```bash
python3 -m unittest discover -s tests/entitlements -v
MYSQLD_BIN=/usr/local/mysql/bin/mysqld MYSQL_CLIENT_BIN=/usr/local/mysql/bin/mysql \
  python3 tests/entitlements/integration.py
```

Observed validation: nine Python unit tests passed; the design validator passed 5,023 assertions including its 57 audit regression cases; the expanded disposable integration suite passed completely. INFORMATION_SCHEMA confirmed 20 tables, 136 columns, 33 FKs, 58 CHECKs, 28 procedures, two functions, four views and two triggers.

Local validation uses the installed MySQL 26.7.0. The previous commit's recorded 8.4.6 evidence is not evidence that this new increment was tested on 8.4.6.

Table-driven policy makes the state/action model inspectable and extensible without duplicating checks across handlers. It does **not** remove the global policy mutex, implement durable job leasing/retry/recovery, or demonstrate high-throughput scaling. The [post-interview audit](Post_Interview_Audit.md) retains the proposed worker design for future assessment/expiration/delinquency work. New financial stages still require their transaction/audit/idempotency implementations and acceptance tests.

Requirement trace: existing FR-06/07/10 request operations and FR-28 audit; existing ownership/scope/version rules; professor's table-driven workflow clarification. This supersedes the earlier “no workflow policy tables” assumption only for this documented implementation.
