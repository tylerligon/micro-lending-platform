# Post-interview implementation audit

> **Implementation follow-up:** [Table-driven workflows](Table_Driven_Workflows.md) now implements request transition policy and console administration. The dual-role defect and local binary-context error below have been fixed and integration-tested. General failure attribution and durable worker execution remain open. This audit retains its original review findings as history.

October 30, 2026 · reviewed commit `189ed0f` plus existing local documentation edits.

The partner's earlier seven-page PDF covered questions **1–6 and 18–24**. All answers are now maintained in [consolidated responses 1–24](Midterm_Followup_Responses.md), updated for the workflow increment and the team's clarified contributions. This audit retains its original review findings as history.

## Historical assessment at 189ed0f (before the workflow follow-up)

| Request | Assessment | Evidence and remaining work |
| --- | --- | --- |
| Implement audit | Substantial implementation for existing operations; incomplete end to end | Account/profile/Draft/submission and configuration successes write audit atomically. Error handlers roll back before separate failure evidence; HTTP fallback is present. Missing financial commands mean their audits are still design contracts. Acting-role and target attribution issues remain below. Administrator/Auditor audit-history projections are not implemented. |
| Scalable entitlements | Configurable design implemented; throughput scaling not established | RoleClass, Permission and RolePermission separate role names from supported capabilities/scopes. Current privileges, RowVersion conflicts, last-admin safeguards, sessions and runtime grants exist. A global Administrator-row mutex serializes protected SQL actions; sessions/rate limits remain single-process. Scope-selection defect needs correction. |
| Scalable workflow management | Main outstanding design deliverable | Existing request commands and TDD transitions provide a foundation. There is no implemented assessment/review/funding/expiration/repayment/delinquency execution layer, and no complete durable worker claim/retry/recovery design. See the proposed design below. |
| Logging, observability, alert hierarchy | Implemented local administration baseline | Structured local logs, manual parent/child spans, counters/gauges/histograms, protected monitoring/metrics/trace endpoints and threshold evaluation exist. Local alert receiver only; no external notification or cross-process coordination. Severity hierarchy is explicitly a team proposal, not verified against a transcript of the professor's discussion. |
| Repository organization | Duplicate root documents resolved; internal contradictions remain | `3327a4f` removed root FRD/TDD copies. `docs/` is the maintained set. README and baseline design paragraphs still mix old and current counts, authentication status and test counts. Adjacent local repository clones/backups are not duplicate tracked artifacts inside this repository. |

## Original findings and subsequent disposition

### 1. Resolved: local integration binary-context failure

I ran `tests/entitlements/integration.py` against a disposable server using `/usr/local/mysql/bin/mysqld` and `/usr/local/mysql/bin/mysql`. The fresh schema and historical fixture loaded, and Draft creation succeeded. The run stopped at `tests/sql/midterm_demo.sql:45`, the call to `sp_update_loan_request`, with **ERROR 3854 (HY000): Cannot convert string ... from binary to utf8mb4**.

The installed server identifies itself as **MySQL 26.7.0**; the partner's recorded evidence specifies **8.4.6**. This is a reproduced local compatibility failure, not a conclusion that the 8.4.6 record is false. The failure occurs before entitlement SQL, upgrade and HTTP integration checks, so those stages were not reverified here. Binary context handling around `COALESCE(@ml_context, UUID_TO_BIN(UUID()))` is a candidate to isolate, not an established root cause.

Next step: reproduce on the documented 8.4.6 version, pin/check the supported runtime, then isolate the local conversion failure. Do not claim the local demonstration passes until rerun successfully. No development database was used or reset.

### 2. Resolved: valid dual-role access was denied

In `025_entitlements.sql`, `sp_require_permission` selects `ORDER BY ur.RoleCode LIMIT 1` before testing OWN/SELF/PARTICIPATING scope. A Borrower+Lender user requesting another borrower's loan that they funded selects Borrower/OWN first and gets `Owner required`, even though Lender/PARTICIPATING would allow access.

This is a static code finding: it follows directly from selection order and the scope branch. The current test rejects user 7 for an unfunded loan, but does not test a dual-role user's valid funded loan. Select a role whose capability **and resource scope** match, or require an explicit verified acting role consistently at the trusted boundary. Test owner-only, participant-only, both and neither, plus multiple custom roles.

### 3. High priority: failure evidence does not retain the attempted role or target

`sp_record_failure` selects the first active UserRole alphabetically rather than receiving the role verified for the failed action. It also stores only `p_Action` as the Attempt SubjectKey. SQL handlers supply a procedure name; HTTP calls supply a route. Neither supplies the requested record ID or a validated attempted operation reference.

For a dual-role user this can misattribute the role, and two failures against different requests become indistinguishable by subject. It falls short of TDD §8.1's action/target and verified-role contract. Carry trusted attempt metadata through the command context, permit NULL when no role was verified, and retain safe typed targets/references after rollback. Do not recover attribution by trusting arbitrary browser actor/role fields. The current helper also lacks TDD §6.2's retained failed Review/Funding evaluation behavior.

### 4. Medium priority: workflow scalability needs its own concrete design

Adding configurable permissions is not the same as defining durable workflow execution. Funding deadlines, delayed assessment, delinquency scans, crash recovery and repeated deliveries need explicit ownership, claims, transaction boundaries and idempotency. The proposed design below answers that missing professor request without asserting an unapproved generic workflow engine is already built.

### 5. Resolved in current documents: status and evidence consolidation

README's opening amendment says 17 tables and implemented administrator sign-in/runtime grants; later paragraphs still say 15 entities and sign-in/runtime grants pending. Older sections cite 44/86 checks, while current integration expects 45/87. The full release design also describes application-owned transactions while current procedures own whole-action transactions. Explain each as historical/full-release scope or update it in place; readers should not need to guess which statement applies.

The partner PDF's Q18 says **5,040** assertions. This local run reports **5,042** with 57 targeted audit-contract cases. Use the actual run output and identify the baseline: this validator still checks the original 15-entity design, not every extended runtime object. The PDF appropriately discloses unimplemented workflows and distinguishes fixture/design checks from execution.

Q22 attribution has since been clarified by the team: Tyler wrote the initial FRD/TDD drafts; Tyler and Anuvik jointly revised the design for the October 19 commit; later responsibility generally follows the recorded commits. The consolidated responses and TDD §2.5 now contain that corrected timeline.

## Proposed scalable workflow design for review

**Status: proposal, not an implemented or professor-approved amendment.** Preserve the existing business entities and D1 rules. The goal is independently schedulable work, repeatable recovery and bounded concurrency without duplicating financial truth in an unrestricted configurable workflow engine.

1. **Explicit transition contracts.** Maintain a version-controlled matrix for each action: source state, target state, permission/scope, preconditions, locks, business time, audit events and failure behavior. Commands are the only state writers. RowVersion protects edits; borrower/request/loan locks protect monetary and exposure invariants. Do not let administrators configure arbitrary SQL transitions.
2. **Separate command handlers from scheduling.** Interactive actions invoke a controlled command. Workers invoke the same domain handler for assessment, expiration and delinquency. Partition work by borrower so that exposure-changing actions for one borrower serialize while independent borrowers can proceed. Keep the current policy mutex initially; a measured, tested finer policy-lock protocol is needed before claiming concurrent transaction throughput.
3. **Durable work tracking.** Propose a separate operational work-item table with job type, subject ID, immutable deduplication key, due time, state, attempt count, lease owner/expiry, lease generation and safe last-error code. This is a schema addition requiring an ERD/build/migration amendment; it is not part of today's 17-table count. Financial amounts and lifecycle truth remain in the existing business tables.
4. **Atomic scheduling and bounded claims.** Insert required work in the same transaction as the triggering business change. Workers claim small due batches in a short locking transaction, then release scheduling locks. Execute the domain action in a new bounded transaction that rechecks the job's lease generation and business state. Expired leases may be reclaimed; a stale worker must not commit after losing its claim. Specify and test one lock order across job/domain locks to avoid introducing deadlocks.
5. **At-least-once delivery, idempotent effects.** Expect duplicate claims after crashes. Financial commands resolve durable caller/reference receipts; worker actions use an immutable job identity plus a guarded state transition and unique deduplication rule. Commit domain changes, success audits and job completion together where possible. Do not claim exactly-once delivery; prove one committed business effect across retries.
6. **Failure and recovery rules.** Roll back all business effects before separate failed-attempt evidence. Retry confirmed transient deadlocks/timeouts with bounded backoff and a fresh attempt context. Do not automatically retry invalid policy, authorization, ciphertext or stale-intent errors. On uncertain commit outcome, reconcile job/receipt/state before another effect. Exhausted jobs move to a visible failed state with a controlled operator retry.
7. **Observable backlog and escalation.** Track queue depth, oldest due age, processing latency, attempts, expired leases and failed jobs without user IDs as metric labels. Link request/job/attempt contexts in logs. Reuse the existing evidence-loss Critical and audit-unavailable High alerts; propose High for overdue expiration backlog and Warning for sustained queue growth. Exact thresholds and ownership need the team's agreement.

Acceptance evidence should include two workers claiming the same item, crash before/after commit, lease expiry with an old worker resuming, duplicate delivery, overdue funding deadlines, concurrent exposure changes and audit-write failure. A successful recovery must leave one business effect with traceable attempts. Measure wait/hold time and backlog under multiple borrowers before changing locks or splitting deployments.

## Current alert hierarchy to explain to the professor

| Severity | Implemented trigger | Response |
| --- | --- | --- |
| Critical | At least one failure of local fallback evidence, immediate | Investigate loss of both database and fallback evidence; failure state remains latched until fallback recovery. |
| High | Database audit persistence unavailable, immediate; or at least three database failures in a 60-second window sustained for five seconds | Investigate evidence persistence/database health and verify recovery. |
| Warning | At least ten denials or three slow database calls in a 60-second window, sustained for five seconds | Inspect correlated traces for access misuse, contention or capacity problems. |

Source: `ops/alerts.json`, `app/telemetry.py`, `ops/README.md`. Alerts fire/resolve into a local JSONL receiver, with dashboard/trace links. No external notification delivery is configured. The available feedback does not specify the professor's exact hierarchy, so present this as the implemented proposal and resolve any mismatch with that discussion.

## Historical verification performed before fixes

| Check | Observed result |
| --- | --- |
| `python3 -m unittest discover -s tests/entitlements -v` | 9 tests passed. |
| `python3 docs/diagrams/tools/validate_erd.py` | 5,042 design assertions passed; 57 targeted audit-contract regression cases; original 15 entities / 114 attributes / 27 FKs. |
| Disposable MySQL integration | Fresh build/fixture and Draft creation succeeded; failed during Draft edit with error 3854 on installed MySQL 26.7.0. Later integration stages not reached. |
| Partner PDF | Read all seven pages; covers 1–6 and 18–24. Inspected the rendered Q19/Q20 page. |
| Prior context | Consulted the earlier project audit/demo discussion and review-email context; the pasted professor feedback is the direct requirement source for this review. |

This section records the initial read-only review. Subsequent implementation, current
responses and release validation are described in the workflow contract and README.
