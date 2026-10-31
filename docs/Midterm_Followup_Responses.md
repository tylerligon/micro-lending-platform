# Midterm follow-up: consolidated responses 1–24

**Prepared jointly by Tyler Ligon and Anuvik Das.** Updated October 30, 2026.

**Implementation snapshot:** the table-driven workflow follow-up to commit `189ed0f`. The extended build has **20 tables, 136 columns and 33 foreign keys**. The original lending model remains the 15-entity baseline. Current validation passed nine Python unit tests, 5,023 design assertions, the existing 45 midterm and 87 early-workflow checks, and the expanded disposable integration suite on installed MySQL 26.7.0. The workflow follow-up is source-controlled separately from the earlier demo; it has not been applied to the development database. “Planned” identifies an unimplemented behavior, not an executed test result.

## Follow-up deliverables requested by the professor

| Request | Current response and evidence |
| --- | --- |
| Implementation of audit | Implemented account/profile/request and administration commands commit success audits with their changes. Failure observations and local fallback exist. Failure-role/target attribution and protected general audit-history reads remain open; see Q15–16. |
| Scalable entitlement design | Role membership, permissions and scoped grants are stored in tables; dual-role grant selection is corrected. [Entitlement contract](Entitlements.md). The global policy lock remains a throughput limitation. |
| Scalable workflow-management design | Existing create/edit/submit/cancel actions resolve rules from state/action/transition tables, with audited versioned administration. [Implemented workflow contract](Table_Driven_Workflows.md). The [worker scheduling/recovery proposal](Post_Interview_Audit.md#proposed-scalable-workflow-design-for-review) covers future background processing; that worker is not implemented. |
| Logging, observability and alert hierarchy | Structured logs, metrics, local traces, monitoring and Critical/High/Warning rules exist. [Operational design](../ops/README.md), [alert thresholds](../ops/alerts.json). The severity hierarchy is our implemented proposal; the available written feedback does not establish the professor's exact verbal thresholds. Alert delivery is local. |
| Repository organization | `docs/` contains the maintained FRD/TDD and this response set. Root duplicate specifications were removed. Model extensions and historical baselines are identified; see Q23. |

## A. Design and data model

## 1. Which entity would we cut first if forced from 15 to 12, and what breaks?

From the original 15 lending entities, we would consider OversightNote first because its removal affects administrative follow-up rather than the representation of contributions, repayments or balances. It would remove FR-23's dated follow-up notes and the ability to append a correction referencing an earlier note.

AuditEvent would not replace it: audit records describe system actions, while oversight notes capture administrative follow-up. This would require an explicit reduction in requirements. Removing one entity leaves 14, so reaching 12 requires two more separately justified decisions. The current 20-table count includes subsequent entitlement/workflow extensions; it does not change the basis of the original question.

Evidence: [OversightNote schema](../database/schema.sql), [FRD FR-23](Functional_Requirements_Document.md), [current extensions](Table_Driven_Workflows.md).

## 2. Why identify repayments within a loan instead of giving each a global ID?

A repayment belongs to one loan, so `(LoanID, RepaymentNumber)` gives it a useful local identity, such as repayment 501/2. More importantly, RepaymentAllocation references both the repayment and installment through composite foreign keys sharing LoanID. That prevents allocating a payment to a different loan's installment.

A global RepaymentID would also work, but retaining the same-loan guarantee would require an appropriate composite unique-key/FK arrangement or additional validation. We chose loan-scoped identity and structural integrity at the cost of wider keys and more verbose joins. The planned repayment routine must allocate the next number while holding the loan lock; an unlocked `MAX(RepaymentNumber)+1` would be unsafe.

Evidence: [Repayment and RepaymentAllocation definitions](../database/schema.sql), [TDD §§4.11–4.12 and 6.2](Technical_Design_Document.md).

## 3. What stops 50 concurrent requests from passing evaluation in isolation?

There is deliberately no request-count limit or unique BorrowerID constraint on requests. The protection is combined affordability: the proposed largest installment, external obligations and exposure from other live requests/outstanding loans are evaluated together.

Implemented submission operations acquire the policy mutex and borrower User lock before capturing exposure through `sp_submission_exposure`. A later submission therefore includes earlier committed live requests. The borrower row is the intended exposure serialization point; the global policy mutex currently serializes unrelated protected actions as well. The table-driven SubmitRequest rule adds an explicit action/state/permission gate; it does not replace the exposure calculation or its locks.

For income $1,000, external obligations $100 and existing platform burden $300, a proposed $400 installment fits at $800 total. A second $400 installment brings the total to $1,200 and should fail assessment. Submission currently retains the evidence without rejecting unaffordability itself. Automated assessment and approval/funding rechecks remain unimplemented. We can demonstrate exposure capture, not the completed 50-request underwriting workflow. If all 50 requests actually fit the combined policy, the design permits them.

Evidence: [exposure and submission routines](../database/02_programmability/030_procedures.sql), [workflow rules](../database/04_seed/016_request_workflow.sql), [two-connection walkthrough](../tests/sql/submission_concurrency.sql).

## 4. What breaks with interest-bearing D2, and why was a CHECK appropriate for D1?

The immediate failure is that the schema rejects `PolicyCode='D2'`: its CHECK permits only D1. Relaxing that constraint would not implement interest. Our schedule, allocations and balances model principal only, without interest-rate or interest-allocation fields/rules.

D2 requires an explicit policy/version design, retained accepted terms, revised schedules, allocation rules and reporting. Existing D1 loans must keep their original terms. A CHECK was reasonable for the fixed classroom D1 scope because coexisting policy versions were excluded. Table-driven entitlements and request transitions now address the professor's configurability concern in those areas; they do not make the financial product policy configurable or implement D2.

Evidence: [LoanRequest and payment schema](../database/schema.sql), [TDD scope and rounding rules](Technical_Design_Document.md), [workflow contract](Table_Driven_Workflows.md).

## 5. What happens to request 103's $100 commitment when funding expires?

The fixture's request 103 asks for $300 and has commitment 205 for $100. The commitment is Pending, with AppliedAt and ReleasedAt both NULL. Receipt 1005 identifies lender 2's contribution. No loan exists for request 103.

This is a simulated funding promise, not money held in a wallet or transferred to the borrower. At the recorded deadline, **November 1, 2026, 00:00 UTC**, the planned expiration transaction must lock the relevant borrower/request records, confirm the request is still incompletely funded, and atomically change it to Expired, change Pending commitments to Released with ReleasedAt, and write request-expiration/commitment-release audit events. It creates no loan or schedule. The commitment amount and original receipt remain as history. Failure rolls back the changes and success audits.

Expiration remains unimplemented. The current CancelDraft action is explicitly Draft-only, and no executable expiration rule is seeded until its handler exists. Merely reaching the deadline does not execute an expiration transaction.

Evidence: [fixture records](diagrams/sample-records.json), [TDD §6](Technical_Design_Document.md), [implemented workflow rules](../database/04_seed/016_request_workflow.sql).

## 6. Where is rounding enforced, and how does reconciliation handle the extra cent?

The documented rounding rule belongs in the activation transaction's schedule-generation logic. Convert principal to cents; use integer floor division for the first n−1 installments; put the remainder in the last installment. For $100 over three installments, 10,000 cents produces 3,333, 3,333 and 3,334 cents: **$33.33 + $33.33 + $33.34 = $100.00**.

DECIMAL(18,2) stores amounts but does not enforce the distribution or cross-row schedule total. The implemented exposure procedure calculates the corresponding largest installment. Actual activation/schedule generation remains unimplemented.

Allocation reconciliation is separate: allocations must sum exactly to the posted repayment and cannot exceed installment balances. A full $100 repayment would allocate $33.33, $33.33 and $33.34. Paying only $33.33 against the last installment leaves $0.01 outstanding; it cannot be rounded away or treated as completion. Current row CHECKs do not enforce full allocation or oldest-first order; those need the planned locked repayment transaction.

Evidence: [TDD §§6 and 6.3](Technical_Design_Document.md), [exposure calculation](../database/02_programmability/030_procedures.sql), [schema](../database/schema.sql).

## B. Integrity, transactions and concurrency

## 7. Two rules that foreign keys cannot enforce

First, accepted funding must not exceed a request's principal. A foreign key proves that each commitment references an existing request; it does not compare the sum of commitments with that request's principal. The planned `sp_commit_funding` transaction must lock the participants and request, reread the funding total, reject excess capacity, and commit the commitment, receipt, audit and any activation together.

Second, a repayment must be allocated in full without overpaying any installment. The composite foreign keys prevent cross-loan allocations, but they do not prove that allocation amounts sum to the repayment or stay within each installment's remaining balance. The planned `sp_post_repayment` transaction must lock the loan/schedule, allocate oldest-first, and reconcile the totals before commit. An error rolls back the whole action.

**Current boundary:** neither financial write routine is implemented. These are documented enforcement locations, not guarantees supplied by the current schema alone.

Evidence: [TDD §§6 and 6.3](Technical_Design_Document.md), [FK matrix](ERD.md), [current procedure inventory](../database/02_programmability/030_procedures.sql).

## 8. The actual submission lock and the failed evaluation

The implemented submission preparation explicitly sets **READ COMMITTED**, starts a transaction, and locks the canonical `Role` row whose RoleCode is `Administrator`. The permission helper then locks the borrower's `User` row with `SELECT ... FOR UPDATE`; preparation also locks that borrower's profile and target request. The shared workflow helper also requires an enabled SubmitRequest transition and resolves its required permission from the action table. The same connection retains these locks through `sp_submit_request` and commit. A concurrent submission waits, then reads exposure including the earlier committed request. The borrower row is the intended per-borrower serialization point; the new global policy lock currently serializes even unrelated borrowers.

The example has existing burden $300, external obligations $100 and income $1,000. A $1,200/3 request adds $400: the first check totals $800; the second sees $700 of other platform burden and totals $1,200. It is the **later assessment** of the second retained snapshot that should fail affordability.

An important correction: submission itself does not reject unaffordability. It writes a Submission evaluation with captured burden and delinquency, but NULL affordability/completion fields. The planned assessment fills those fields once, retains Result=Fail for the second submission and changes its request state atomically with the audit. That assessment is not implemented yet.

For a different case—a blocked Review or Funding action—the design requires rollback of business effects followed by a separate transaction retaining the completed failed evaluation with a newly allocated attempt number. The current `sp_record_failure` only inserts an AuditEvent; it does not implement that evaluation-retention protocol.

Evidence: [prepare/finish and exposure routines](../database/02_programmability/030_procedures.sql), [workflow helper](../database/02_programmability/026_request_workflow.sql), [policy/permission/failure helpers](../database/02_programmability/025_entitlements.sql), TDD §§4.7, 6.1–6.2 and 7.1.

## 9. Same reference, changed amount: what the caller and audit see

The planned observable result is **HTTP 409, `OPERATION_CONFLICT`**, with a safe error message, server context ID and `retryable=false`. Under the caller lock, the service finds the existing `(CallerUserID, OperationReference)` receipt and compares action, target and amount. Changing $300 to $301 fails that comparison; it does not replay the old success or create another contribution.

The original successful receipt remains. “No receipt” here means **no new receipt**. After rollback, the denial should produce `AuditEvent(EventType=AttemptRejected, Outcome=Denied, ReasonCode=OPERATION_CONFLICT)`, with the verified caller/acting role, technical account, context and a safe attempted reference. The Attempt subject identifies the action/target; OperationID stays NULL when the denied attempt committed no receipt. There is no new success event.

**Current boundary:** receipt structure and fixture examples exist, but funding/repayment endpoints and receipt-replay routines do not. The administration application's existing 409 stale-version response is a separate implemented behavior, not proof of financial idempotency.

Evidence: TDD §§2.2, 6, 8.1; [receipt/schema definitions](../database/schema.sql); [worked retry example](ERD.md).

## 10. Why repayment completion has one owner

If the repayment procedure and allocation trigger could both complete a loan, the final allocation could cause two competing completion actions or duplicate `LoanCompleted`/delinquency-clearing audits. One transaction should have exactly one owner of that transition.

The design assigns Active → Repaid exclusively to `trg_allocation_after_insert`. It requires a complete valid schedule, no overallocated installment, all repayments fully allocated, and total repayments = allocations = principal. A conditional update must change the loan from Active exactly once. The trigger sets completion/observation fields and writes one completion event. The procedure subsequently checks reconciliation and must not repeat that transition or audit.

Partial payment produces zero completions; the final payment produces one; an exact retry still leaves one; failure after the final allocation rolls back the payment, allocations, completion and success audits together.

**Current boundary:** this completion trigger and the repayment routine remain planned. The existing triggers guard frozen request terms and prevent request deletion.

Evidence: TDD §6.3; [implemented triggers](../database/02_programmability/040_triggers.sql), [delete guard](../database/02_programmability/041_request_delete_guard.sql).

## 11. Stored derived loan fields and drift prevention

`ObservedCondition` is a stored Current/Delinquent observation derived from due dates and unpaid installment amounts. `LastEvaluatedAt` records when that observation was made; it is not a claim that the observation remains current. `LoanState` and `CompletedAt` are also maintained lifecycle facts whose transition to Repaid depends on the reconciled payment/schedule facts. Outstanding principal and current overdue amount should be calculated from installments and allocations, rather than maintained as additional balance columns.

The design prevents inconsistent updates by routing repayment and scheduled/manual delinquency evaluation through the same loan-locking protocol and due-date rule: **DueDate < UTC DATE(T)** and remaining principal > 0. Due today is not overdue. Reports and eligibility checks recalculate current delinquency using one explicit evaluation time instead of trusting the last observation. The completion trigger owns Repaid/CompletedAt; the observation worker updates condition/time and audits an actual condition change.

**Current boundary:** allocation-based balance views exist, but the repayment completion and delinquency workers do not. Seeded Loan observations are historical fixture data and should not be presented as automatically maintained current facts.

Evidence: TDD §§4.9, 6 and 6.3; [balance report](../database/02_programmability/011_midterm_reports.sql), [remaining-installment view](../database/02_programmability/010_views.sql).

## C. Security, audit and privacy

## 12. Key ownership, authenticated context and wrong-AAD failure

The design places encryption keys in the trusted service, injected outside source control. MySQL and the browser do not hold those keys. The service authenticates/decrypts values locally and passes short-lived validated financial parameters to controlled SQL on the same reserved connection. SQL cannot independently prove that the service supplied the true decryption; that trusted boundary must be stated explicitly.

AES-256-GCM uses a fresh nonce and versioned key identifier. AAD is compact UTF-8 JSON `[table, recordBinding, column]`: BorrowerProfile binds to UserID; LoanRequest binds to RequestID; RequestEvaluation binds to `RequestID/EvaluationKind/ContextIDhex`. Consequently, copying an income envelope into another user's profile or into an obligations column fails authentication. Request snapshots must be re-encrypted under their new context.

A wrong-AAD attempt must stop before finish, roll back, clear preparation context, and retain a separate failure observation using `CIPHER_INVALID`. No private value, ciphertext, key or raw cryptographic exception should be copied into the audit. **Proposed explicit mapping for the missing coordinator:** `TransactionFailed`/`Failed` for an internally encountered envelope-authentication failure, with verified actor when available, technical account, action/target and context. The TDD names the reason code but the complete production failure path still needs implementation and a test.

**Current boundary:** SQL prepare/finish exists and trusts service-supplied plaintext/envelopes. The production encryption coordinator and its wrong-AAD audit path do not exist. The admin console does not supply this lending encryption workflow.

Evidence: TDD §7.1 and audit reason catalogue; [submission routines](../database/02_programmability/030_procedures.sql).

## 13. Which reports require more than SQL?

**RQ-01, the currently fundable request listing**, needs the trusted service because it reevaluates affordability using encrypted frozen income/obligations. SQL can compute pending funding, outstanding loans and overdue installments, but cannot decrypt those private inputs under our key-separation design.

This costs us a coordinated report transaction: collect candidates, lock/revalidate them in a consistent order, decrypt locally, calculate eligibility on the reserved connection, then filter/page the safe projection. It also adds key availability, failure handling and lock-duration/performance concerns. The design calls for a 10/100/1,000-candidate measurement gate; that is still outstanding. A failed decryption must not silently turn a candidate into a fundable request.

RQ-02–08's listed balance, schedule, participation, monthly, queue and redacted audit summaries can use SQL over nonprivate amounts and retained decisions. An authorized private-input drill-down associated with a report additionally requires the service; that does not mean every report aggregate requires decryption.

Evidence: [FRD §10 report contracts](Functional_Requirements_Document.md), TDD §7.1 RQ-01 contract.

## 14. Why lender 2 sees loan 501 once and user 7 sees neither loan

For the Lender branch, access is based on an Applied commitment to **that loan's request**, attributed to the caller through its OperationReceipt:

```sql
SELECT l.LoanID
FROM Loan l
WHERE EXISTS (
    SELECT 1
    FROM FundingCommitment c
    JOIN OperationReceipt o ON o.OperationID = c.OperationID
    WHERE c.RequestID = l.RequestID
      AND c.CommitmentState = 'Applied'
      AND o.CallerUserID = :verified_lender_id
);
```

This illustrates the record predicate; an authenticated current account, active role and appropriate capability must also be checked. EXISTS returns a Boolean per outer loan, so lender 2's two contributions do not duplicate loan 501. Lender 2 has no Applied participation in 502. User 7 owns request 104, but neither owns loans 501/502 nor has Applied contributions to them. Having both Borrower and Lender roles grants no access to another borrower's loans by itself.

**Current implementation:** `sp_read_loan` uses `sp_require_permission` and its PARTICIPATING predicate, then reads already aggregated loan/schedule views. Permission selection now evaluates the scope of each eligible grant before choosing a role. A Borrower role therefore does not mask a valid Lender participation grant. Executed regression tests add Borrower membership to lender 2 and verify that loan 501 remains readable, loan 502 remains denied, and user 7 still cannot read loan 501. This fixes the earlier dual-role denial defect; it does not bypass current account/role/capability checks.

Evidence: [permission and loan-read procedures](../database/02_programmability/025_entitlements.sql), [entitlement tests](../tests/sql/entitlements.sql), [dual-role regression](../tests/sql/request_workflow.sql), ERD worked cases 4 and 7.

## 15. Is self-funding denial audited?

Under the design, yes: user 7's funding attempt must produce `AttemptRejected`/`Denied` with `ReasonCode=SELF_FUNDING`, `ActorUserID=7`, and the verified Lender acting role for that funding attempt. Its Attempt subject identifies CommitFunding/request 104, with a server context and safe attempted reference. No receipt or commitment is created, and no `CommitmentAccepted` success audit is written.

Success evidence commits with its business action and rolls back if that action fails. Failure evidence is written separately after rollback so the rejected attempt remains observable without falsely implying that money was accepted. If that separate evidence write fails, the operation remains denied and the observability fallback must expose the evidence problem.

**Current boundary:** self-funding enforcement/audit cannot yet be demonstrated through an implemented funding command. Separate failure logging exists for implemented actions. Its helper currently chooses the user's first active membership rather than retaining the verified acting role; for user 7 that can select Borrower instead of Lender. The helper must be revised before claiming correct funding-denial attribution.

Evidence: TDD §8.1; [current failure helper](../database/02_programmability/025_entitlements.sql); ERD worked case 7.

## 16. Why status explanations live in AuditChange and who reads them

An explanation belongs to a particular status transition, not to the user's current status alone. A mutable `User.StatusReason` column would overwrite the reason for an earlier restriction when the account is reactivated or restricted again. Each `AccountStatusChanged` event instead retains the old/new status plus a `StatusReason` change, with its actor and timestamp. The explanation has NULL OldValue because it is new context for that event, not an edit of the previous event's reason.

The planned Administrator audit projection may return the explanation. The Auditor projection keeps the field name but redacts both values to NULL; Borrowers and Lenders cannot read the general audit feed. Raw audit tables are not directly granted to runtime business roles. Privileged database operators can technically read underlying data; this application projection is not a cryptographic protection against a database administrator.

The status routine implements bounded, nonblank reason validation and atomic status/audit persistence. The required Administrator-versus-Auditor audit-history read projection remains unimplemented; the administration console's configuration screen is not that history endpoint.

Evidence: [status routine](../database/02_programmability/030_procedures.sql), TDD §8.1 StatusReason contract, [runtime grants](../database/entitlements_console_grants.sql).

## 17. Why use a generated ActiveMarker?

For an active membership the generated value is 1; for a revoked episode it is NULL. `UNIQUE(UserID, RoleCode, ActiveMarker)` therefore permits only one `(user, role, 1)` while retaining multiple historical `(user, role, NULL)` episodes. The caller cannot independently set a marker inconsistent with RevokedAt.

A simple unique `(UserID, RoleCode)` would prevent retaining multiple grant/revoke episodes. Adding a Boolean active flag to that key would permit only one inactive episode as well. Making RevokedAt the third unique column would not prevent multiple active memberships because all their RevokedAt values are NULL. This schema uses the generated nullable marker to encode the conditional uniqueness rule.

This protects one active membership **per named role**. It does not enforce compatible role categories, grant authority, last-administrator protection, or live-obligation rules; controlled membership operations handle those separately.

Evidence: [UserRole definition](../database/schema.sql), [membership procedure](../database/02_programmability/030_procedures.sql), [entitlement contract](Entitlements.md).


## D. Evidence and validation

## 18. What do the design assertions prove, and what can they miss?

One assertion class checks referential integrity in the fixture. Changing a commitment's RequestID to nonexistent request 999 produces `FK10 orphan FK`; a supposedly valid fixture containing that reference fails validation. However, the validator evaluates Python data and design artifacts. It cannot prove that MySQL enforces funding caps under simultaneous transactions, or catch a flawed runtime authorization path solely because the fixture's relationships are correct.

The latest run reports **5,023 design assertions**, including **57 targeted audit-contract regression cases**. The original 4,976 figure in the question and the partial PDF's 5,040 count are earlier snapshots. The validator still checks the original 15-entity lending dictionary/diagrams and the audit catalogue; it does not fully validate the extended 20-table runtime schema. Many assertions check diagram fields, documented links and export consistency, so the count changes with documentation cleanup and is not 5,023 independent business scenarios. Runtime SQL/HTTP integration is separate evidence.

Evidence: [design validator](diagrams/tools/validate_erd.py), [audit rules](diagrams/tools/audit_rules.py), [current integration suite](../tests/entitlements/integration.py).

## 19. Give two audit regression inputs and their exact rejection

| Invalid input | Exact reference-validator result | Reason |
| --- | --- | --- |
| Change CommitmentAccepted event 823 to ActingRoleCode='Borrower' | `(823, 'actor_rule')` | The successful funding event must satisfy its permitted role and attribution contract. |
| Put plaintext '1000.00' in an AuditChange.NewValue for ProfileSaved event 816 | `(816, 'private_value')` | Protected financial values must not enter the audit feed. |

These are reference-validator rejection codes, not SQL errors or HTTP responses. The 57 targeted cases include positive, boundary and redaction checks as well as negative cases. Separate runtime tests inject audit-write failures and verify rollback for implemented actions, including workflow configuration.

Evidence: [targeted regression driver](diagrams/tools/validate_erd.py), [audit-contract implementation](diagrams/tools/audit_rules.py), [workflow rollback test](../tests/sql/request_workflow.sql).

## 20. Which acceptance gate would fail first when the fixture runs?

The original premise is outdated: the executable historical fixture has now loaded into isolated MySQL, followed by passing **45 midterm and 87 early-workflow checks**, entitlement/workflow tests and real HTTP integration. The earlier local Draft-edit binary-to-text conversion failure was fixed by the binary-returning `fn_action_context`; the expanded suite now passes on installed MySQL **26.7.0**. That run is separate from the earlier commit's recorded MySQL 8.4.6 evidence.

The historical fixture uses placeholder protected bytes. It does not prove the original encrypted materializer output is fully integrated. For that materializer, **P1**—fresh schema, SQL loading, constraint/count verification and working encrypted fixtures—still needs establishment. We would not predict a specific load failure without running it. A known mismatch is that the original materializer produces Argon2id password hashes while current administration authentication accepts scrypt: SQL loading can succeed while login fails.

The first known incomplete lending-workflow gate is **P2**, because assessment, review/approval, funding and activation are not implemented. The new table-driven policy controls existing request actions; it does not complete those financial workflows.

Evidence: [TDD §10.1 gates](Technical_Design_Document.md), [integration suite](../tests/entitlements/integration.py), [fixture materializer](diagrams/tools/materialize_fixture.py), [password verification](../app/security.py), [binary context function](../database/02_programmability/020_functions.sql).

## 21. What do modules retain or sacrifice compared with microservices, and what forces a split?

Separate command/query modules preserve clear responsibilities and interfaces. A single deployment gives up independent deployment, scaling and process-level fault isolation: releasing or scaling one component generally affects the entire service.

A split becomes justified if scheduled assessment or delinquency processing measurably degrades interactive latency and requires independent resources/releases. An explicit instructor requirement for separate deployables also requires a split regardless of traffic.

The current administration application uses Python's standard-library HTTP server; FastAPI remains part of the proposed full-system architecture. We have not established that modules alone satisfy the professor's microservices requirement. Workflow policy now lives in relational state/action/transition tables, while durable background-worker claiming, recovery and deployment remain future work. Table-driven configurability is separate from measured throughput: the global policy mutex and single-process session storage remain scaling boundaries.

Evidence: [TDD §§2.1 and 11.1](Technical_Design_Document.md), [HTTP application](../app/admin_console.py), [workflow contract](Table_Driven_Workflows.md), [proposed worker design](Post_Interview_Audit.md#proposed-scalable-workflow-design-for-review).

## E. Process and attribution

## 22. Which parts did each partner personally work on?

**Tyler Ligon wrote the initial FRD and TDD drafts. Tyler and Anuvik Das then worked together on the revised design delivered in the October 19 commit. After that shared revision, the division of work generally follows the repository's commit history.**

| Date | Contributor(s) | Work and supporting commits |
| --- | --- | --- |
| October 14 | Tyler | Initial FRD (`da0af8e`) and TDD draft (`7d46092`). |
| October 19 | Tyler and Anuvik | Joint revisions to the design and reviewed deliverable submitted in `fc6e09d` under Anuvik's commit authorship. |
| October 20 | Tyler | Repository/document cleanup (`5f6a194`, `3327a4f`), initial account schema (`05fd24e`), complete lending schema and audited Draft creation (`947ad55`), and early SQL workflows/build organization (`a9303d5`). |
| October 20 | Anuvik | Professor-review artifact labels and deliverable snapshot (`4f1c2c4`). |
| October 21 | Anuvik | Midterm request-management database demonstration (`1deed92`). |
| October 30 | Anuvik | Configurable entitlements, multiuser administration and observability (`189ed0f`). |

The shared October 19 revision is the explicit exception to attributing later work by commit author. Importing the design package from `anuvikdas/CS-437-Database-Systems-Implementation` at `39c00d7` records its repository provenance; it does not change who drafted and jointly revised the documents. We used AI assistance and remain responsible for understanding and explaining the submitted work.

The table-driven workflow follow-up is identified separately in this response's implementation snapshot. It is later work, not part of those earlier commits; its submission is recorded in the current Git history. The FRD identification and TDD §2.5 use this same contribution account.

Evidence: team clarification; commit history; [FRD identification](Functional_Requirements_Document.md); [TDD §2.5](Technical_Design_Document.md).

## 23. Which document wins when copies disagree, and why are stale versions present?

The duplicate root FRD/TDD files were removed in **3327a4f**; they are no longer tracked current specifications. The maintained FRD and TDD are under `docs/`. The FRD defines business requirements; the TDD defines technical design. Newer instructor directions take precedence over our design assumptions.

For implemented entitlements and request workflows, the explicit current amendments and their linked contracts supersede older fixed-role/no-workflow-table assumptions. The **original 15-table** lending dictionary, **17-table** entitlement increment and **current 20-table** build are successive scopes, not competing current schema totals. The current build has 136 columns and 33 FKs. Historical implementation paragraphs and milestone logs must be read as their labelled snapshots; they do not override the current contract.

This consolidated response is the maintained answer set. The earlier partial response PDF remains an external historical source; the separate responses 7–17 were folded into this document. Editable diagrams and their SVG exports are source/export pairs required for review, not separate competing designs. Earlier versions belong in Git history. If code contradicts an agreed requirement, we identify and resolve the discrepancy rather than simply choosing the convenient value. README and current design-status paragraphs have been consolidated; the dated milestone/review logs preserve historical evidence explicitly.

Evidence: [README current document policy](../README.md), [FRD](Functional_Requirements_Document.md), [TDD](Technical_Design_Document.md), [entitlements](Entitlements.md), [current workflow contract](Table_Driven_Workflows.md), commit 3327a4f.

## 24. Name a remaining race and its mitigation

A remaining unimplemented lending race is concurrent funding. With $100 capacity remaining, two lenders could each read that value and independently accept an $80 contribution, overfunding the request.

The planned mitigation is to lock participant User rows in ascending ID order, lock the request, then recalculate current committed funding before accepting the contribution. The first $80 succeeds; the second sees $20 capacity and is rejected. Contribution, receipt, audit and any full-funding activation must commit atomically. All authorized funding/exposure writers must follow that protocol.

The funding routine is not implemented, so this is a documented race requirement, not a race proven resolved by executed funding tests. Existing administration and workflow-configuration edit races are implemented separately: shared policy locking and RowVersion checks make two edits based on the same version produce one success and one 409 conflict. The disposable integration suite exercises concurrent workflow-policy edits. It does not demonstrate concurrent financial funding.

Evidence: [TDD §6 lock/transaction design](Technical_Design_Document.md), [workflow configuration](../database/02_programmability/026_request_workflow.sql), [concurrent HTTP integration](../tests/entitlements/integration.py).

## Verification record for this response set

| Evidence | Observed result and limit |
| --- | --- |
| Python unit tests | Nine passed for administration/session/telemetry behavior. |
| Design validator | 5,023 assertions passed, including 57 targeted audit cases; original lending baseline and audit contracts, not full runtime proof. |
| Disposable MySQL integration | Passed existing 45 midterm / 87 early-workflow checks, entitlement/workflow regressions, migration preservation, upgraded commands, runtime privileges, real authenticated HTTP, concurrent edits and observability checks on MySQL 26.7.0. |
| Extended schema | INFORMATION_SCHEMA confirmed 20 tables, 136 columns, 33 FKs, 58 CHECKs, 28 procedures, two functions, four views and two triggers. |
| Release/deployment scope | The workflow follow-up extends 189ed0f; Git history identifies its source revision. Integration used a disposable server; the development database has not been migrated. |

Pending work remains explicit: assessment/review/funding/activation/expiration/repayment/delinquency handlers, production lending encryption coordination, durable worker execution, general failure-role/target attribution and Administrator/Auditor audit-history projections. These limitations are not removed by consolidating the answers.
