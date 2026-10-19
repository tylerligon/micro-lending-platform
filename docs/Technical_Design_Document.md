# Micro-Lending Platform — Technical Design Document

Version: **1.2** · October 19, 2026 · Requirements baseline: **FRD 1.2**  
Course: CS 437 Database Systems Implementation

Start with [ERD and interview walkthrough](ERD.md). The [reusable work prompt](ERD_Work_Prompt.md)
records the approved simplification. This document is the implementation blueprint;
SQL, a running application, and MySQL integration results are not yet present.

## 1. Scope and source decisions

The model has **15 application tables, 114 attributes (including three generated
attributes), and 27 foreign-key constraints**. Two operational build tables are
separate. There is one editable draw.io file with three pages and three SVG exports.
The professor requires meaningful relationships and 3NF, not the former 23-table count.

Approved changes from TDD 1.0: frozen private submission inputs move into LoanRequest;
RequestEvaluation combines observations, assessment completion, and review decisions;
the two fixed eligibility conditions become columns. D1 is fixed release configuration,
so there are no policy-version/option or generic status-label tables. Each check retains
a total exposure burden and delinquency result rather than component-level history.
No structured loan IDs are hidden in JSON/CSV to imitate the deleted component table.

The retained total proves the numerical basis used for a decision. It does **not**
reconstruct the exact historical membership of that total. Current source records
still determine each new check. Different policy versions in one dataset are excluded;
a changed policy requires a separately built dataset. FRD 1.2 explicitly records both
scope reductions. They are project decisions, not professor requirements.

Multiple requests/loans per borrower, repeated contributions, exact-result retries,
full-principal activation, partial/early repayment, scope-limited lender access,
private input protection, and immutable audit/financial history remain required.
Money is fictional, interest-free USD. No wallets, real transfers, payouts, reversals,
refinancing, external scoring, cache, failover, or production disaster recovery is added.

Repository sources: [project requirements](course/Course_Project_Requirements.pdf) pp.6–7/12;
[deliverables and demo](course/Deliverables_and_Demo.pdf);
[semester plan](course/Semester_Plan.pdf) p.1 and Week 7;
[build requirements](course/Build_Script_Requirements.pdf);
[TDD template](course/TDD_Template.pdf); [FRD 1.2](Functional_Requirements_Document.md).
These are unchanged copies of the supplied course handouts, not new project rules.
The [KOHA-Lite sample](https://github.com/Yash1907/dbms/tree/b663e59ca3250f0be17a814a0f8b0e3a6fe21c51)
is a secondary organizational example, not authority for omitted requirements.

## 2. Architecture and technology

Use one repository and MySQL 8.4 LTS with InnoDB. A small Python 3.12/FastAPI service
has Command and Query entrypoints with shared identity, encryption, and database
modules. A worker invokes assessment, expiration, and daily delinquency evaluation.
A basic same-origin HTML/JavaScript UI demonstrates FR-33. These are planned choices;
§2.4 pins candidate direct versions and distinguishes them from tested implementation versions.

Browser → authenticated Command/Query API → MySQL; worker → restricted routines → MySQL.
There is no distributed transaction or independent service database. No transaction
stays open while waiting for a reviewer, lender, or user input. The application owns
one connection/transaction per action; mutation procedures never independently commit.
Any error rolls back the whole business action. Denial/failure evidence is separate.

Use strict SQL mode, including ONLY_FULL_GROUP_BY. Keep DECIMAL money exact; reject
fractional cents before conversion. Timestamps are server UTC; due dates are UTC dates.
Use password hashing, protected keys, authenticated encryption for private columns,
TLS for DB traffic and HTTPS for the UI. No credentials or private plaintext in Git/logs.

### 2.1 Architecture decision and editable views

The course [semester plan](course/Semester_Plan.pdf), p.1 and Week 7, explicitly calls
for a microservice architecture and extraction/update services. The supplied
[TDD template](course/TDD_Template.pdf), §4, also permits a simple database-centered
architecture. **One deployable service with Command/Query modules is a proposal, not
confirmed satisfaction of the microservices wording.** Instructor/TA confirmation is an
open P0 decision. Ask: “May our two-person project use one deployable FastAPI service
with separate extraction/query and update/command boundaries over one MySQL database?”
If separate deployables are required, revise deployment/session/credential boundaries
before implementation; the ERD and business transactions need not change. No approval
or extra subsystem is invented by this deliverable.

[Application_Design.drawio](diagrams/Application_Design.drawio) has two editable views:
[architecture and transaction data flow](diagrams/04-application-flow.svg) and
[basic UI wireframes](diagrams/05-wireframes.svg). These are **application-design views,
not additional ERDs or implemented screens**. TDD §§2.1–2.3 are their explanation.
The first distinguishes browser, trusted service, worker and DB, and shows the
prepare→decrypt→calculate→write→commit sequence. The second sketches the borrower,
lender and oversight workspaces. Assumptions: same-origin HTTPS, one service process
pending instructor review, no direct browser DB access, fictional money and no external
credit/payment calls. Workers share the same transaction/encryption implementation and
use their own restricted DB credentials.

### 2.2 API and session contract

All public paths below have prefix `/api/v1`. JSON uses decimal **strings** for money,
positive decimal strings for BIGINT IDs, ISO UTC timestamps ending in Z, calendar dates
for dues, and integer installment counts. Unknown input fields fail validation. Text
limits match §4 (purpose 1000, login 80, display 120, note 4000 API limit); trim required
text and reject blanks. Operation references are 1–64 ASCII letters/digits/`_-`, generated
once by the client for a funding/payment intent. They are caller-scoped and never changed
when retrying that intent. The server derives actor and active role from the session.
Role selection for a dual account is permitted only among its current memberships;
it never changes ownership or removes the self-funding prohibition.

| Method / path | Required input and permission | Successful response / routine / traceability |
| --- | --- | --- |
| GET `/session/csrf` | Same-origin unauthenticated request; issue ephemeral pre-login CSRF cookie/token | 200 csrfToken; login bootstrap only; no business data |
| PATCH `/session` | Authenticated; roleCode must be a current own role; CSRF required | 200 selectedRole and new csrfToken; rotate session token; dual-role navigation only |
| POST `/session` | loginName, password (12–128 characters for created sample accounts); active or Restricted account; generic invalid-credentials response | 200: userID, allowed roles, status, CSRF token, expiresAt; secure session cookie; FR-04, AC-01 |
| GET `/session`; DELETE `/session` | Authenticated; DELETE requires CSRF | 200 current user/roles/status; 204 logout; FR-04, SEC-01/14 |
| PUT `/me/profile` | Borrower; monthlyIncome, externalObligations, expectedVersion (0 on first create) | 200 userID, rowVersion, updatedAt; sp_save_profile; FR-05, AC-02 |
| POST `/requests`; PATCH `/requests/{id}` | Active Borrower; purpose, principal, installmentCount; PATCH also expectedVersion and owned Draft | 201/200 requestID, state, rowVersion; sp_save_draft; FR-06, AC-03 |
| POST `/requests/{id}/submit` | Owning active Borrower; expectedVersion | 200 requestID, Submitted, submissionEvaluationID; sp_submit_request; FR-07, AC-04/29 |
| POST `/requests/{id}/review` | Administrator; decision Approve/Reject, nonblank reason (<=1000), expectedVersion | 200 requestID, evaluationID, state, deadline if approved; sp_review_request; FR-09, AC-05/30 |
| POST `/requests/{id}/contributions` | Active Lender; amount; `Idempotency-Key` header required | 201 stored receipt body: operationID, commitmentID, requestID, own amount/state, pendingTotal, remainingAmount, loanID if activated; sp_commit_funding; FR-11–14/30, AC-07–10/15/16 |
| POST `/requests/{id}/cancel` | Owner or Administrator; reason <=1000, expectedVersion; permitted pre-funding state | 200 requestID, Cancelled, releasedCount; sp_cancel_request; FR-15, AC-09 |
| POST `/loans/{id}/repayments` | Owning Borrower (Active or Restricted); amount; `Idempotency-Key` required | 201 stored receipt: operationID, loanID, repaymentNumber, amount, allocations[{installmentNumber, amount}], outstandingAfter, loanState; sp_post_repayment; FR-17–21/30, AC-11–16/27 |
| GET `/operations/{reference}` | Authenticated caller owns reference; current account permits own history | 200 original receipt/action; 404 if absent; lookup is read-only; FR-30, AC-15 |
| POST `/admin/users` | Administrator; loginName, displayName, privateEmail, initialPassword, roles array of valid allowed combination | 201 userID; sp_create_user; FR-01/02, AC-01 |
| POST `/admin/users/{id}/roles` | Administrator; roleCode, action Grant/Revoke, reason <=1000 | 200 userRoleID/current roles; sp_set_role; FR-02, AC-01 |
| PATCH `/admin/users/{id}/status` | Administrator; status, reason <=1000, expectedVersion | 200 userID, status, rowVersion; sp_set_account_status; FR-03, AC-18/24 |
| POST `/notes` | Administrator; exactly one requestID/loanID, noteText, optional correctsNoteID | 201 noteID, createdAt; sp_append_note; FR-23, AC-18 |
| POST `/admin/loans/{id}/evaluate` | Administrator; empty body; time assigned by server | 200 loanID, asOf, condition and overdue fields; sp_evaluate_delinquency; FR-22, AC-17 |

Worker assessment/expiry/delinquency entrypoints are internal authenticated calls, not
public endpoints accepting client time. Poll request detail to observe assessment
completion; returning Submitted does not claim that review/funding is already allowed.
All actions in §6 exist behind the documented routines; no generic table CRUD endpoint.

Reports use GET and return `{asOf, items, totals, nextCursor}`; a detail result uses a
`data` object with separately grouped children. `totals` cover all authorized filtered
rows, not only the displayed page. `limit` defaults to 25, allowed 1–100; `cursor` is an
opaque signed tuple of the stable order columns + filter hash, not an authorization
credential or stored reporting entity. A new page re-evaluates current data/time; it
is not a frozen export. Clients needing an exact single-snapshot demo use one response.
Reject unknown filters; never accept actor IDs, scope overrides or client AsOf.

| GET path | Filters / order | Projection and permission authority |
| --- | --- | --- |
| `/fundable-requests` | minPrincipal, maxPrincipal, installmentCount; deadline, requestID | Exactly FRD RQ-01; Lender; no borrowerID/private inputs/eligibility details |
| `/me/requests`; `/me/loans`; `/requests/{id}`; `/loans/{id}` | requestID/loanID, state, from/to; newest then ID | FRD RQ-02 owner detail; participating Lender loan detail uses RQ-03; Administrator review detail, Auditor redacted only |
| `/me/contributions` | from/to, state, borrowerID, loanID; newest then commitmentID | RQ-03; own commitment events, separate distinct-loan summaries |
| `/installments` | borrowerID, loanID, dueFrom/dueTo; due date, loanID, number | RQ-04; owner/participant/Administrator/Auditor scoped |
| `/delinquency` | borrowerID, loanID, minDaysPastDue; days desc, loanID | RQ-05; participant/Administrator/Auditor scoped |
| `/reports/monthly` | monthFrom/monthTo (inclusive); month ascending | RQ-06; Administrator/Auditor |
| `/review-queue` | category, submittedFrom/submittedTo; oldest state time, requestID | RQ-07; Administrator/Auditor with redaction |
| `/history` | exactly one requestID/loanID, from/to, eventType, outcome; time, eventID | RQ-08; Administrator/Auditor |

FRD §10 is the exact field allowlist for each RQ; these references are part of this
contract. No ORM/base-table dump is a response schema. Private owner/reviewer inputs
are returned only by authorized detail routes. Unknown or out-of-scope record IDs
return the same 404 public shape; internal audits distinguish the actual reason.
Dates/intervals are inclusive as calendar filters; timestamp end bounds are exclusive.

Errors: `{error:{code,message,contextID,retryable}}` with no SQL text, private values,
other lenders, or target existence hints. 401 invalid/missing session; 403 authenticated
role/action denial; 404 unavailable target; 409 stale version, invalid state, funding
capacity, conflicting reference, current eligibility failure; 422 malformed input or
policy-range violation; 503 exhausted transient DB retries/unknown outcome. Owner/admin
eligibility failure may include failed condition **names**, never private numeric inputs
in a general error. Lenders receive only `REQUEST_NOT_FUNDABLE`. Actual HTTP status and
serialized JSON body for a committed financial operation are retained in ReceiptSnapshot
as UTF-8 `statusCode + newline + body`; replay returns those original bytes/status.
An optional `Idempotent-Replay: true` header does not alter the receipt. Session cookies,
CSRF tokens and transport headers are never stored in that snapshot.

Session design: server-generated random 256-bit token in an HttpOnly, Secure,
SameSite=Lax cookie, Path=/; store only its SHA-256 lookup digest server-side. One
service-process memory store holds userID, selected role, CSRF token, creation/last-use
and expiry; it is ephemeral authentication infrastructure, not an application ERD table.
30-minute idle/8-hour absolute expiry, rotate on login and role switch, invalidate on
logout; restart logs everyone out. Recheck User status and active roles every protected
request, including retries. For mutations require matching CSRF header and same-origin
Origin validation (including login); no permissive credentialed CORS. Inactive accounts
cannot sign in; restriction still permits FRD history/profile/cancellation/repayment.
Authentication throttle: five failed attempts per login+source in 15 minutes, then 429
until window expiry; no passwords or full credentials in failure logs. If deployables
or process count change, session ownership must be redesigned under the open decision.

### 2.3 Basic UI scope and study path

The wireframes are design sketches, not evidence of a running UI. A shared sign-in form
and role navigation lead to three workspaces:

- Borrower: edit private profile, create/edit/submit drafts, list multiple requests and
  loans, inspect schedules/allocations, enter a repayment, and see a committed receipt.
- Lender: filter eligible public requests, contribute again using a new reference,
  inspect own commitments and funded-loan schedules/delinquency. A retry reuses the
  original reference; “new contribution” creates a new intent/reference.
- Oversight: Administrator review/approve/reject, account restrictions/roles and
  append-only notes; Administrator/Auditor scoped reports/history. Auditor controls
  are read-only and private inputs are absent. Server authorization remains mandatory.

Every action shows validation/error/loading/empty/success states. Disable duplicate
submit while pending but rely on server retry protection. Unknown outcome shows “Check
result / retry same payment,” never a success banner. Tables label loan-level repayment
as loan progress, not lender payouts. Due dates remain dates; timestamps display UTC.
During implementation, turn wireframe lists into actual request/loan/installment tables,
make the selected LoanID and repayment amount prominent, and distinguish each screen's
primary action. Put developer explanations outside user-facing screens.
This is FR-33 / C-08 / AC-25; it adds no wallet or disbursement behavior.

### 2.4 Exact environment targets and evidence boundary

| Component | Exact target | Status |
| --- | --- | --- |
| Python | 3.12.14 | Used for this design verifier |
| Inkscape | 1.2.2 | Used to inspect these SVG renders |
| MySQL server/client | 8.4.12, InnoDB | Candidate implementation baseline; not executed |
| FastAPI | 0.149.0 | Candidate, not integration-tested |
| Uvicorn | 0.54.0 | Candidate, single process pending architecture approval |
| mysql-connector-python | 26.7.0 | Candidate, not integration-tested |
| cryptography | 50.0.2 | Fixture encryption tool; application boundary still unimplemented |
| argon2-cffi | 25.1.0 | Fixture password hashing tool; application login still unimplemented |
| Browser UI | Native HTML/CSS/JavaScript | No JS framework dependency |

Release existence was checked against [MySQL release notes](https://dev.mysql.com/doc/relnotes/mysql/8.4/en/)
and package-maintainer PyPI pages: [FastAPI](https://pypi.org/project/fastapi/0.149.0/),
[Uvicorn](https://pypi.org/project/uvicorn/0.54.0/),
[connector](https://pypi.org/project/mysql-connector-python/26.7.0/),
[cryptography](https://pypi.org/project/cryptography/50.0.2/),
[argon2-cffi](https://pypi.org/project/argon2-cffi/25.1.0/). These direct-version choices
are **not a resolved application lockfile**. P1 must resolve/pin all transitive packages,
record wheel hashes/OS/architecture and MySQL image digest, scan the resolved set, and
run clean-build tests before calling any baseline tested. Exact targets may change with
that evidence without changing the lending model; record changes in this section.

### 2.5 Contributor responsibility and unresolved submission metadata

Anuvik Das is identified by the project repository. The second contributor's name and
course section have not been verified; the local path in the review is not sufficient
proof of identity. FRD identification now states this explicitly instead of template
brackets. The team must supply those two facts before final submission.

Proposed work split (assign actual names before implementation): database lead owns
P1 schema/build/security and P2 funding transactions; application lead owns API/session,
UI and P3 repayment/report integration. Both pair-review authorization, trigger/rollback
and race evidence, and each can explain every ERD relationship. P4 reports/UI and P5
performance/demo are joint acceptance gates. This assigns responsibilities to workstreams,
not invented contributions. The semester plan's individual contribution history must
reflect actual student work; AI-generated commits are not proof of each person's work.

## 3. Conventions and fixed reference data

- PK/UNIQUE/FK/NOT NULL/CHECK are schema constraints. All application FKs use restrictive
  update/delete behavior; identities never change. A FK validates parent existence,
  not the parent's business role or minimum child count.
- `Role` is the reference table: Borrower, Lender, Administrator, Auditor. Technical
  service identities are not human business roles. UserRole retains grant/revoke episodes.
- D1: principal $100–$2,000 inclusive; 3 or 6 monthly installments; no interest; funding
  deadline exactly 14 days after approval. PolicyCode is NULL before submission and D1
  afterward. There is no policy FK and no mutable policy interface.
- Status values are explicit CHECK whitelists, with matching version-controlled UI
  labels. Legal transitions also require action routines/guards: a valid code alone
  does not authorize changing Draft directly to Funded.
- Generated attributes are derived at query time and cannot be independently edited.
  `ActiveMarker` and `FinalReviewMarker` use MySQL's NULL-allowing unique-index behavior.
- Nullable lifecycle fields are constrained as groups: submitted inputs/policy/time;
  final decision/reason/time; and completed loan state/time. No placeholder empty strings.

## 4. Complete application data dictionary

The relational ERD contains these exact declarations. Every FK is listed in the
[relationship matrix](ERD.md#relationship-matrix). `Generated nullable` means a virtual
expression, not an optional caller-supplied field. PK columns are non-null.

### 4.1 User

Application identity, account status, and the existing row used to serialize a borrower’s exposure changes. **Strong.** Basis: FR-01–FR-04; BR-01, BR-03; SEC-01.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| UserID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Stable application identity; also exposed as BorrowerID when this user owns a request. |
| LoginName | `VARCHAR(80)` | No | UNIQUE; binary collation | Case-sensitive login; no uniqueness rule on private email. |
| DisplayName | `VARCHAR(120)` | No | Nonblank | Account display information, not the marketplace alias. |
| PublicAlias | `VARCHAR(40)` | No | UNIQUE; nonblank | Immutable random nonidentifying marketplace alias; also binds encrypted private email before UserID allocation. Never generated from email/name. |
| PrivateEmailCipher | `VARBINARY(512)` | No | Authenticated-encryption envelope | SEC-12 protected contact value. |
| PasswordHash | `VARCHAR(255)` | No | Argon2id encoded hash | Local sample-account sign-in; never a readable password or audit value. |
| AccountStatus | `VARCHAR(16)` | No | CHECK; default Active | Current account entitlement state. |
| CreatedAt | `DATETIME(6)` | No | Server UTC | Account creation time. |
| RowVersion | `BIGINT UNSIGNED` | No | Default 0; increment on update | Reject stale profile/account edit inputs and help validate preparation reads. |

**PK:** UserID. **Other UNIQUE:** LoginName; PublicAlias. **Checks:** AccountStatus in Active/Restricted/Inactive; trimmed LoginName and DisplayName nonempty.

AccountStatus is Active/Restricted/Inactive. RowVersion increments on every account edit. The User row exists before a first loan and serves as the borrower-level lock target. Login and public alias are unique; private email is not an identity key.

### 4.2 Role

The four human business roles. **Lookup/reference.** Basis: FR-02; SEC-06, SEC-13.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| RoleCode | `VARCHAR(16)` | No | PK; CHECK | Canonical business role name. |
| Description | `VARCHAR(255)` | No | Nonblank | Responsibility described in FRD Section 4. |

**PK:** RoleCode. **Other UNIQUE:** None. **Checks:** RoleCode in Borrower/Lender/Administrator/Auditor.

Role codes are fixed release-managed reference rows; runtime roles cannot rewrite definitions.

### 4.3 UserRole

Retained grant/revocation episodes with at most one active membership per pair. **Associative/history.** Basis: FR-02; BR-01, BR-03; SEC-14.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| UserRoleID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Identity of one membership episode. |
| UserID | `BIGINT UNSIGNED` | No | FK User.UserID | Member. |
| RoleCode | `VARCHAR(16)` | No | FK Role.RoleCode | Assigned business role. |
| GrantedAt | `DATETIME(6)` | No | Server UTC | Assignment time. |
| GrantedByUserID | `BIGINT UNSIGNED` | Yes | FK User.UserID | Administrator; NULL only for documented initial bootstrap. |
| RevokedAt | `DATETIME(6)` | Yes | Paired-null CHECK | Revocation time; NULL means active membership. |
| RevokedByUserID | `BIGINT UNSIGNED` | Yes | FK User.UserID | Revoking Administrator. |
| ActiveMarker | `TINYINT` | Generated nullable | VIRTUAL generated; UNIQUE component | IF(RevokedAt IS NULL,1,NULL), allowing many revoked episodes and one active episode. |

**PK:** UserRoleID. **Other UNIQUE:** (UserID,RoleCode,ActiveMarker). **Checks:** RevokedAt and RevokedByUserID both NULL or both present; RevokedAt >= GrantedAt.

ActiveMarker = IF(RevokedAt IS NULL,1,NULL). UNIQUE(UserID,RoleCode,ActiveMarker) permits many revoked episodes and at most one active membership. RevokedAt/RevokedByUserID are both NULL or both set; RevokedAt >= GrantedAt. NULL grantor is allowed only for documented bootstrap. No in-place reuse of a revoked episode.

### 4.4 BorrowerProfile

Current protected income and external monthly obligations. **Dependent 1:1.** Basis: FR-05; BR-01, BR-05; SEC-02, SEC-12.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| UserID | `BIGINT UNSIGNED` | No | PK; FK User.UserID | Exactly one current profile per user. |
| MonthlyIncomeCipher | `VARBINARY(128)` | No | Encrypted decimal envelope | Self-reported fictional monthly income. |
| ExternalObligationsCipher | `VARBINARY(128)` | No | Encrypted decimal envelope | Monthly obligations outside the platform only. |
| UpdatedAt | `DATETIME(6)` | No | Server UTC | Latest profile change. |
| RowVersion | `BIGINT UNSIGNED` | No | Default 0 | Expected-version check prevents stale preparation/update. |

**PK:** UserID. **Other UNIQUE:** None. **Checks:** Plaintext income > 0 and external obligations >= 0 validated before encryption; required envelopes nonempty.

Decrypt only through an authorized service. Plaintext income > 0 and external obligations >= 0 are validated before encryption. RowVersion increments on change. Profile edits never overwrite LoanRequest's submitted fields.

### 4.5 LoanRequest

A funding request with immutable submitted terms and private input snapshot. **Strong.** Basis: FR-06–FR-16, FR-24; BR-04–BR-13, BR-19.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| RequestID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Stable request identifier. |
| BorrowerID | `BIGINT UNSIGNED` | No | FK User.UserID | Owner; assigned from trusted session. |
| Purpose | `VARCHAR(1000)` | No | Nonblank | Borrower-supplied request purpose. |
| Principal | `DECIMAL(18,2)` | No | CHECK 100.00 <= value <= 2000.00 | Requested principal, frozen after submission. |
| InstallmentCount | `SMALLINT UNSIGNED` | No | CHECK in (3,6) | Accepted repayment term. |
| PolicyCode | `VARCHAR(8)` | Yes | CHECK NULL or D1 | NULL before submission; fixed D1 at submission. No policy-version FK. |
| RequestState | `VARCHAR(20)` | No | CHECK; default Draft | Draft/Submitted/PendingReview/OpenFunding/Funded/Rejected/Cancelled/Expired. |
| CreatedAt | `DATETIME(6)` | No | Server UTC | Request creation. |
| SubmittedAt | `DATETIME(6)` | Yes | Set once by submission | Snapshot time, not editable client time. |
| FundingDeadlineAt | `DATETIME(6)` | Yes | Required for OpenFunding/Funded/Expired | Approval timestamp + 14 days; no extension after eligibility blocking. |
| TerminalReason | `VARCHAR(1000)` | Yes | Required for Cancelled/Rejected/Expired | Controlled procedure supplies the reason; no financial correction. |
| RowVersion | `BIGINT UNSIGNED` | No | Default 0 | Draft edit and stale-action detection. |
| SubmittedIncomeCipher | `VARBINARY(128)` | Yes | Immutable after submission | Frozen income, distinct from the mutable profile. |
| SubmittedObligationsCipher | `VARBINARY(128)` | Yes | Immutable after submission | Frozen external monthly obligations; platform burden is in each evaluation. |

**PK:** RequestID. **Other UNIQUE:** None; deliberately no unique BorrowerID. **Checks:** Principal between 100.00 and 2000.00; InstallmentCount in (3,6); fixed PolicyCode D1 on submission; lifecycle and snapshot-nullability rules.

RequestState: Draft, Submitted, PendingReview, OpenFunding, Funded, Rejected, Cancelled, Expired. Submission sets SubmittedAt, PolicyCode, SubmittedIncomeCipher, and SubmittedObligationsCipher together. A cancelled unsubmitted Draft retains all four NULL; otherwise a submitted request retains all four forever. Request terms and submitted private inputs become immutable. FundingDeadlineAt is required for OpenFunding/Funded/Expired; a cancellation may retain its earlier deadline. TerminalReason is required for Rejected/Cancelled/Expired. Every submitted request has one Submission evaluation at commit, enforced by the submission transaction, not a FK.

### 4.6 RequestEvaluation

One retained submission, review, or funding check; summaries and final decision facts remain attributable. **Dependent/history.** Basis: FR-07–FR-09, FR-12; BR-04, BR-06, BR-07; AC-04, AC-29.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| EvaluationID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Stable check ID; public AssessmentID is the Submission EvaluationID. |
| RequestID | `BIGINT UNSIGNED` | No | FK LoanRequest.RequestID; UNIQUE part | Evaluated request; repeated attempts retained. |
| EvaluationKind | `VARCHAR(16)` | No | CHECK Submission/Review/Funding; UNIQUE part | Checkpoint; never a request lifecycle state. |
| AttemptNumber | `INT UNSIGNED` | No | UNIQUE part; CHECK | 0 for Submission; positive sequence per request/kind otherwise. |
| EvaluatedAt | `DATETIME(6)` | No | Server UTC | Time when exposure/delinquency facts were observed. |
| PlatformBurdenCipher | `VARBINARY(128)` | No | Encrypted decimal >= 0 | Retained total of other live requests and outstanding-loan burdens; no per-obligation history. |
| NoDelinquencyPass | `TINYINT UNSIGNED` | No | CHECK in (0,1) | Frozen no-outstanding-delinquency condition at observation time. |
| AffordabilityPass | `TINYINT UNSIGNED` | Yes | CHECK in (0,1); set once | NULL only for an unprocessed Submission; completed check compares all retained inputs. |
| CompletedAt | `DATETIME(6)` | Yes | Set once; >= EvaluatedAt | Assessment completion time for Submission; check completion otherwise. |
| Result | `VARCHAR(4)` | Generated nullable | VIRTUAL generated Pass/Fail | NULL until complete; Pass iff both condition flags are 1. No independently editable score. |
| AdministratorID | `BIGINT UNSIGNED` | Yes | FK User.UserID | Required on Review; NULL for Submission/Funding. Actor must have Administrator role. |
| Decision | `VARCHAR(8)` | Yes | CHECK Approve/Reject | Only a completed Review may record a final decision; blocked approval leaves NULL. |
| Reason | `VARCHAR(1000)` | Yes | Required nonblank with Decision | Human final-review explanation; failed machine conditions derive stable reason codes from flags. |
| DecidedAt | `DATETIME(6)` | Yes | Paired with Decision; >= CompletedAt | Final decision timestamp; approval starts funding window. |
| ContextID | `BINARY(16)` | No | Correlation identifier | Matches the operation/audit attempt, including a failed check. |
| FinalReviewMarker | `TINYINT` | Generated nullable | VIRTUAL; UNIQUE part | 1 iff a final Review decision exists, otherwise NULL; preserves any number of blocked attempts. |

**PK:** EvaluationID. **Other UNIQUE:** (RequestID,EvaluationKind,AttemptNumber); (RequestID,FinalReviewMarker). **Checks:** Submission attempt 0 only; other attempts >0; fixed two condition flags; one final Review decision per request; conditional completion/reviewer fields.

UNIQUE(RequestID,EvaluationKind,AttemptNumber) with Submission attempt 0 and Review/Funding attempts > 0. Allocate attempts under the borrower lock. Result = CASE WHEN CompletedAt IS NULL THEN NULL WHEN AffordabilityPass=1 AND NoDelinquencyPass=1 THEN 'Pass' ELSE 'Fail' END. AffordabilityPass and CompletedAt are both NULL only for a not-yet-processed Submission. All Review/Funding checks are completed. NoDelinquencyPass, PlatformBurdenCipher, EvaluatedAt, request/kind/attempt, and ContextID are frozen on insert. A Submission may be completed exactly once by filling its affordability flag and completion time; the request transition and success audit are atomic with this write. Completed evaluations are immutable.

AdministratorID is required exactly for Review. Decision, Reason, and DecidedAt are either all NULL or all present on a completed Review; other kinds have them NULL. A rejected/blocked approval check can be retained without a final Decision. Reject may be final even if Result=Fail; Approve requires Result=Pass and an eligible active borrower. FinalReviewMarker = IF(EvaluationKind='Review' AND Decision IS NOT NULL,1,NULL). Its unique pair with RequestID allows one final review and many nonfinal attempts. Public AssessmentID is the Submission EvaluationID; public assessment time is CompletedAt. There is no separate Assessment table. Failed-condition reason codes are Affordability and NoOutstandingDelinquency; report each false flag, not a vague combined error.

### 4.7 OperationReceipt

Caller-scoped identity of one committed funding/repayment action and its original response. **Technical/history.** Basis: FR-30; BR-20; AC-15, AC-16.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| OperationID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Shared identity used by one financial event. |
| CallerUserID | `BIGINT UNSIGNED` | No | FK User.UserID; UNIQUE component | Authenticated Lender or Borrower. |
| OperationReference | `VARCHAR(64)` | No | Binary collation; UNIQUE component | Client-generated opaque reference, unique across both action kinds for this caller. |
| ActionCode | `VARCHAR(20)` | No | CHECK | Determines expected event table. |
| ReceiptSnapshot | `MEDIUMBLOB` | Yes until transaction finishes | Immutable serialized response at commit | Original receipt/summary for an exact retry; set once before commit. |

**PK:** OperationID. **Other UNIQUE:** (CallerUserID,OperationReference). **Checks:** ActionCode in CommitFunding/PostRepayment; Reference length 1–64; response snapshot nonempty at commit.

UNIQUE(CallerUserID,OperationReference) spans both financial action kinds. ActionCode is CommitFunding/PostRepayment. A receipt and exactly one matching event commit together; ReceiptSnapshot is filled once before commit and then immutable. Target and amount are read from the immutable event when comparing a retry. The opaque response snapshot is solely for exact-result replay; it never replaces queryable lending facts. A zero-event or two-event receipt is invalid at commit and must be rejected by the transaction.

### 4.8 FundingCommitment

One initial or additional promise, not one row per lender/request pair. **Associative/event.** Basis: FR-12–FR-16; BR-09–BR-12, BR-20.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| CommitmentID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Unique contribution event. |
| RequestID | `BIGINT UNSIGNED` | No | FK LoanRequest.RequestID | Request being funded. |
| OperationID | `BIGINT UNSIGNED` | No | UNIQUE; FK OperationReceipt.OperationID | Lender is derived from its CallerUserID; action must be CommitFunding. |
| EvaluationID | `BIGINT UNSIGNED` | No | UNIQUE; FK RequestEvaluation.EvaluationID | Matching completed, passing Funding evaluation. |
| Amount | `DECIMAL(18,2)` | No | CHECK > 0 | Immutable contribution amount. |
| CommitmentState | `VARCHAR(8)` | No | CHECK; default Pending | Pending/Applied/Released. |
| CreatedAt | `DATETIME(6)` | No | Server UTC | Accepted contribution time. |
| AppliedAt | `DATETIME(6)` | Yes | Only for Applied | Activation timestamp. |
| ReleasedAt | `DATETIME(6)` | Yes | Only for Released | Parent cancellation/expiration time. |

**PK:** CommitmentID. **Other UNIQUE:** OperationID; EvaluationID; deliberately NOT (Lender,Request). **Checks:** Amount > 0; state in Pending/Applied/Released; state/timestamp consistency.

CommitmentState is Pending/Applied/Released. AppliedAt is present iff Applied; ReleasedAt iff Released. Amount and original identity are immutable. LenderID is derived from OperationReceipt.CallerUserID. EvaluationID must be this request's completed passing Funding evaluation; each accepted contribution gets a distinct evaluation. There is deliberately no UNIQUE(lender,request). Runtime validates the linked receipt's action and caller, the evaluation's request, and current entitlement.

### 4.9 Loan

One activated obligation, with lifecycle and latest observation. **Strong with required 1:1 origin.** Basis: FR-14–FR-22; BR-12–BR-18.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| LoanID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Stable loan identity. |
| RequestID | `BIGINT UNSIGNED` | No | UNIQUE; FK LoanRequest.RequestID | One loan per fully funded request. |
| ActivatedAt | `DATETIME(6)` | No | Server UTC | Schedule origin. |
| LoanState | `VARCHAR(8)` | No | CHECK; default Active | Active or Repaid, never Delinquent as a lifecycle state. |
| CompletedAt | `DATETIME(6)` | Yes | Paired with Repaid | Set exactly once by repayment trigger. |
| ObservedCondition | `VARCHAR(16)` | No | CHECK; initial Current | Last detected payment condition. |
| LastEvaluatedAt | `DATETIME(6)` | No | Initial activation time | Observation freshness; current reports calculate condition anew. |

**PK:** LoanID. **Other UNIQUE:** RequestID. **Checks:** State Active/Repaid; completion NULL iff Active; observed condition Current/Delinquent.

LoanState is Active/Repaid. CompletedAt is NULL iff Active. ObservedCondition is Current/Delinquent and LastEvaluatedAt records its freshness. Borrower, principal, and terms are obtained through RequestID. Current reports recompute delinquency, rather than treating the stored observation as timeless truth. One request has zero or one loan; every committed loan has all 3 or 6 schedule rows.

### 4.10 Installment

One immutable scheduled obligation identified within its loan. **Weak/dependent.** Basis: FR-15, FR-18, FR-19; BR-13–BR-17.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| LoanID | `BIGINT UNSIGNED` | No | PK part; FK Loan.LoanID | Identifying parent. |
| InstallmentNumber | `SMALLINT UNSIGNED` | No | PK part; CHECK > 0 | Ordinal unique only within this loan. |
| DueDate | `DATE` | No | UNIQUE within loan | UTC calendar due date. |
| ScheduledPrincipal | `DECIMAL(18,2)` | No | CHECK > 0 | Fixed installment obligation. |

**PK:** (LoanID,InstallmentNumber). **Other UNIQUE:** (LoanID,DueDate). **Checks:** InstallmentNumber > 0; ScheduledPrincipal > 0.

This is the required weak entity: (LoanID,InstallmentNumber) identifies a row, and InstallmentNumber alone is only a partial key. UNIQUE(LoanID,DueDate). No independent global InstallmentID. Scheduled amounts and due dates are immutable after activation. Paid and remaining amounts are derived from allocations.

### 4.11 Repayment

One posted payment against exactly one loan. **Event/dependent.** Basis: FR-17–FR-21, FR-30; BR-14–BR-16, BR-20.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| LoanID | `BIGINT UNSIGNED` | No | PK part; FK Loan.LoanID | Explicitly selected owned loan. |
| RepaymentNumber | `INT UNSIGNED` | No | PK part; CHECK > 0 | Next local sequence allocated while Loan is locked. |
| OperationID | `BIGINT UNSIGNED` | No | UNIQUE; FK OperationReceipt.OperationID | Caller is the owning Borrower; action PostRepayment. |
| Amount | `DECIMAL(18,2)` | No | CHECK > 0 | Immutable posted amount. |
| PostedAt | `DATETIME(6)` | No | Server UTC | Users cannot supply or change this time. |

**PK:** (LoanID,RepaymentNumber). **Other UNIQUE:** OperationID. **Checks:** RepaymentNumber > 0; Amount > 0; no mutable repayment status.

The public RepaymentID is the composite (LoanID,RepaymentNumber), e.g. 501/2. Allocate the number while holding the loan lock. The linked receipt's caller must own the loan and its action must be PostRepayment. Amount, posting time, and identity are immutable. No separate mutable payment-status column.

### 4.12 RepaymentAllocation

Amount of one repayment assigned to one installment of the same loan. **Associative/dependent.** Basis: FR-18, FR-21; BR-02, BR-15.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| LoanID | `BIGINT UNSIGNED` | No | PK part; shared component of both FKs | Makes cross-loan linking impossible through the declared keys. |
| RepaymentNumber | `INT UNSIGNED` | No | PK part; composite FK (LoanID,RepaymentNumber) to Repayment | Paying event. |
| InstallmentNumber | `SMALLINT UNSIGNED` | No | PK part; composite FK (LoanID,InstallmentNumber) to Installment | Receiving obligation. |
| AllocatedPrincipal | `DECIMAL(18,2)` | No | CHECK > 0 | Depends on the full repayment/installment pair. |

**PK:** (LoanID,RepaymentNumber,InstallmentNumber). **Other UNIQUE:** None. **Checks:** AllocatedPrincipal > 0; total/cap checks in locked payment transaction.

Two composite FKs, (LoanID,RepaymentNumber) and (LoanID,InstallmentNumber), prevent allocation to another loan's installment. The amount depends on the complete payment/installment pair. A transaction enforces oldest-first order, per-installment caps, and allocation sum = repayment amount; row-level CHECKs cannot enforce those aggregates.

### 4.13 OversightNote

Append-only administrative follow-up or correction. **History.** Basis: FR-23; BR-25; SEC-06.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| NoteID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Stable note. |
| RequestID | `BIGINT UNSIGNED` | Yes | FK LoanRequest.RequestID; XOR target | Request target. |
| LoanID | `BIGINT UNSIGNED` | Yes | FK Loan.LoanID; XOR target | Loan target. |
| AdministratorID | `BIGINT UNSIGNED` | No | FK User.UserID | Author. |
| CreatedAt | `DATETIME(6)` | No | Server UTC | Append time. |
| NoteText | `TEXT` | No | Nonblank | Internal follow-up; excluded from lender/borrower responses. |
| CorrectsNoteID | `BIGINT UNSIGNED` | Yes | FK OversightNote.NoteID | Earlier note on exactly the same target. |

**PK:** NoteID. **Other UNIQUE:** None. **Checks:** Exactly one RequestID/LoanID non-NULL; NoteText nonblank. The procedure rejects self/cross-target correction; a CHECK does not refer to auto-increment NoteID.

Exactly one RequestID/LoanID is non-NULL (XOR). Author must be an Administrator. CorrectsNoteID, if set, must identify an earlier note on the same target; the FK alone cannot establish same-target correctness. All notes are append-only; they cannot alter balances or decisions.

### 4.14 AuditEvent

Append-only attributable event or observed failed/denied attempt. **Audit/history.** Basis: FR-28; Section 9.2; SEC-08, SEC-10, SEC-11.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| AuditEventID | `BIGINT UNSIGNED` | No | PK; AUTO_INCREMENT | Stable event ID; gaps after rollback are allowed. |
| OccurredAt | `DATETIME(6)` | No | Server UTC | Detection/event time, not an invented commit timestamp. |
| EventType | `VARCHAR(40)` | No | CHECK from TDD §8.1 catalogue | Audited operation. |
| Outcome | `VARCHAR(12)` | No | CHECK | Success, Denied, Failed, or observed Interrupted. |
| ActorUserID | `BIGINT UNSIGNED` | Yes | FK User.UserID | Human actor; NULL for service or unauthenticated attempts. |
| ActingRoleCode | `VARCHAR(16)` | Yes | FK Role.RoleCode | Verified business role; NULL where no human role exists. |
| ServiceActor | `VARCHAR(24)` | Yes | CHECK approved service names | Automated actor such as assessment or activation. |
| InitiatingUserID | `BIGINT UNSIGNED` | Yes | FK User.UserID | Human initiating an automated action when applicable. |
| TechnicalAccount | `VARCHAR(288)` | No | Trusted DB connection identity | USER()/SESSION_USER(), not the definer returned by CURRENT_USER(). |
| SubjectType | `VARCHAR(32)` | No | CHECK bounded subject catalogue | Business record type or Attempt. |
| SubjectKey | `VARCHAR(128)` | No | Canonical scalar/composite serialization | Affected key or attempted target; intentionally not a polymorphic FK. |
| ContextID | `BINARY(16)` | No | One value per attempt/action | Groups business effects and failure observation. |
| OperationID | `BIGINT UNSIGNED` | Yes | FK OperationReceipt.OperationID | Committed funding/payment reference, when one exists. |
| AttemptedOperationReference | `VARCHAR(64)` | Yes | Safe opaque value | Reference for failed actions that have no committed receipt. |
| ReasonCode | `VARCHAR(40)` | Yes | Bounded error/reason catalogue | Safe outcome explanation without raw private values. |

**PK:** AuditEventID. **Other UNIQUE:** None. **Checks:** Outcome Success/Denied/Failed/Interrupted; actor/service context and subject type validated by catalogue.

Outcome is Success/Denied/Failed/Interrupted (the last only when observed). Human events have a verified actor/acting role; automated effects identify ServiceActor and any initiating human. TechnicalAccount is the trusted session identity. SubjectType/SubjectKey are a bounded, validated event reference, deliberately not a fictitious polymorphic FK. This permits logging a denied attempt against a nonexistent target. ContextID ties related effects together; a failed action may have no committed OperationID. Protect the event table against operational UPDATE/DELETE.

### 4.15 AuditChange

Normalized changed-field context for an audit event. **Dependent/audit.** Basis: FRD Section 9.2; SEC-11, SEC-12.

| Attribute | MySQL type | Nullable | Key / constraint | Meaning |
| --- | --- | --- | --- | --- |
| AuditEventID | `BIGINT UNSIGNED` | No | PK part; FK AuditEvent.AuditEventID | Owning event. |
| FieldName | `VARCHAR(64)` | No | PK part; allowlist | Meaning of the change, e.g. RequestState or Amount. |
| OldValue | `VARCHAR(1000)` | Yes | Safe scalar encoding | Old nonprivate value; NULL on creation or for sensitive fields. |
| NewValue | `VARCHAR(1000)` | Yes | Safe scalar encoding | New scalar value; protected StatusReason follows §8.1; amounts/IDs remain in source records too. |

**PK:** (AuditEventID,FieldName). **Other UNIQUE:** None. **Checks:** FieldName from the event-specific allowlist; redacted private fields NULL on both sides; StatusReason bounded and access-protected (§8.1).

One safe changed field per event. Nonprivate before/after values are retained where meaningful. For private changes, retain the field name and NULL values; private snapshots remain protected elsewhere. No list of changed fields in one scalar. This small child table preserves 3NF and makes audit history explainable. The bounded StatusReason exception retains the administrative explanation in NewValue, with the access projection specified in §8.1.

## 5. Relationships and 3NF

The complete 27-FK matrix is in [ERD.md](ERD.md#relationship-matrix), with required/
optional participation in both directions. Referenced columns must be PK/UNIQUE.
Do not add a BorrowerID UNIQUE constraint or lender/request pair UNIQUE constraint.

Each table stores facts about its key: UserID → current identity; RequestID → submitted
terms and frozen private inputs; EvaluationID → one historical observation/completion;
CommitmentID → one contribution; LoanID → one activated obligation; (LoanID,number) →
one schedule/payment; complete allocation key → allocated amount. Role descriptions
depend on RoleCode and are stored only in Role. Names/income are not copied into loans.
Loan has a UNIQUE origin RequestID; its borrower/principal are obtained by joining that
origin, avoiding two independently editable sources. Lender identity is obtained from
the receipt; contribution/repayment amounts are stored in their event tables only.

Income in BorrowerProfile is a current fact; SubmittedIncomeCipher is a distinct fact
as of submission. PlatformBurdenCipher is a historical total at EvaluatedAt, not a
duplicate current balance. These snapshots preserve decision evidence deliberately.
The two condition flags are fixed properties of a single check; they are not an
unbounded repeating condition group. A future configurable rule system would require
a different model. Generated Result and marker columns have no independently stored
value. No repeating role list, unstructured exposure array, or repeated allocation group
is introduced by consolidation. Explain these dependencies when demonstrating 3NF.

## 6. State and transaction rules

FRD §8.2 is the complete state-transition authority. The principal paths are
Draft → Submitted → PendingReview → OpenFunding → Funded and Active loan → Repaid.
Assessment Fail or manual Reject ends the request as Rejected. Cancellation is allowed
only before funding and before deadline for OpenFunding; expiration releases all pending
pledges. Delinquent is a payment condition, not an alternative loan lifecycle state.
Blocked approval/funding leaves the previous request state and prior commitments intact.

| Action | Atomic unit and enforcement | Lock / failure behavior |
| --- | --- | --- |
| Submit | Validate active borrower/profile/D1; freeze request inputs; compute other exposure; insert one uncompleted Submission evaluation; set Submitted; success audit. | Lock borrower User, then target request/profile; later concurrent submissions see the earlier live request. Failure leaves Draft. |
| Assess | Read retained submission inputs/burden/delinquency; fill AffordabilityPass and CompletedAt once; derive Pass/Fail; set PendingReview/Rejected; audit. | Same borrower/request locks; failure leaves uncompleted evaluation and Submitted. Retry completes once. |
| Review | Retain current completed Review evaluation and, if final, decision/reviewer/reason/time; approve only on Pass; set OpenFunding + deadline or Rejected; audit. | Lock borrower/request and current reviewer entitlement. Blocked approval has no final decision; retained failed check is written after rollback with captured facts. |
| Commit funding | Resolve receipt retry first; validate lender/self-funding/account/request/deadline/cap; retain current passing Funding evaluation; insert receipt and commitment; audit. At exact full funding also create Loan/all installments, apply every pledge, mark Funded, fill receipt. | Lock participant User rows in increasing ID order, then request, then loan if relevant. Capture current time after lock waits. Failure of activation rolls back only this action; older Pending pledges remain. |
| Cancel/expire | Change request; release all Pending commitments with timestamps; audit. | Same borrower/request locks as funding, so only one terminal result wins. At deadline or later new funding is denied even before an expiry worker runs. |
| Repay | Resolve retry; verify borrower ownership/status; cap amount; insert receipt/Repayment; allocate oldest-first; update completion and observed condition; audit; fill original response. | Lock borrower User, request, then Loan and unpaid installments in number order. Whole action rolls back on any failure. |
| Delinquency | Derive current overdue amounts; update latest observation; audit a change only. | Coordinate through borrower/loan locks. Daily worker and manual evaluation share the same rule; accounts are restricted separately by Administrator. |
| Account/role/note | Verify Administrator; enforce ongoing-participation restrictions; retain reason/history or append note; audit. | Lock affected User plus acting User in order. No deletion, financial overrides, or impersonation. |

All actions affecting borrower exposure (including repayment, cancellation, assessment
rejection, and activation) acquire the borrower User lock. A consistent global order is
User IDs ascending → request IDs ascending → loan IDs ascending → installment numbers.
After locks, use fresh locking/current reads for decisions; do not reuse a pre-lock
snapshot. An empty collection still has its parent User as a lock target. Do not use a
COUNT query alone to decide an insertion is safe.

Exposure = sum of largest proposed installments of other Submitted/PendingReview/
OpenFunding requests + largest remaining unpaid installment of each other Active loan.
Exclude the target; count a Funded request's Loan instead of both. At submission freeze
this total and whether any outstanding loan is delinquent. At review/funding recompute
current exposure with the target's frozen income/external obligations. Affordability:
proposed largest installment + other exposure + external obligations <= income.
For each check retain the total, condition outcomes, time and context, not components.
An admin Reject may finalize even when eligibility fails. Earlier assessments never change.

For principal P in cents and n installments, allocate floor(P/n) to the first n−1 rows
and the remainder to the last; all positive and sum exactly P. Due dates are n monthly
anniversaries of activation, each independently computed from the original day, clamped
to the destination month's last day (Jan 31 → Feb 28 → Mar 31). Do not chain clamped dates.
Allocation selects oldest unpaid DueDate then number. DueDate < UTC DATE(T) and remaining
principal > 0 means overdue; due today is not overdue. A later repayment clears observed
delinquency only when no overdue amount remains, and completes the loan only at zero total.

For an exact retry, look up UNIQUE(caller,reference), verify the original action/target/
amount, authorize receipt access, and return the original response bytes. Do not reject
a committed retry merely because the request is now Funded or loan Repaid. Different
contents under that key conflict; equal amounts under new references are new actions.
Serialize the caller row as well as enforce the unique constraint. A lost response after
commit has unknown delivery, not a definite rollback; a retry resolves it. Retries add
neither a second financial event nor a second business-success audit.

### 6.1 Isolation, read consistency, and retry ownership

Commands use **InnoDB READ COMMITTED**, an explicit transaction and one reserved
connection from prepare through commit/rollback. The application starts/ends it;
no nested procedure commits. Set UTC and isolation on checkout, clear all action
context on return, and discard a broken connection. Prepared statements bind values.

Lock all involved User rows in ascending ID order (caller, borrower and affected user),
then BorrowerProfile if needed, LoanRequest IDs, Loan IDs, Installment numbers, and
existing evaluation/receipt rows. An immutable preliminary lookup may discover the
borrower ID, but every fact/entitlement is re-read after locking. All writers of profile,
roles, requests, commitments, loans, repayments and allocations follow this order;
a role edit locks its User even if its UserRole collection is empty. Borrower User is
the serialization point for new child rows, so correctness does not depend on locking
a nonexistent row or on READ COMMITTED preventing phantoms. Aggregate exposure reads
after acquiring that lock are current and stable against all authorized exposure writers.
Technical accounts have no direct DML path around this protocol.

Capture business time with `UTC_TIMESTAMP(6)` **after** all potentially blocking locks.
Each action uses that time for posting, deadline tests and audit. Reject a request at
`T >= FundingDeadlineAt`. Return success only after commit; keep the reserved connection
only for local computation and DB calls, never user interaction or external HTTP calls.

The service owns retries: error 1213 (deadlock) or 1205 (lock timeout) causes explicit
whole-transaction rollback, including on versions/configurations where only a statement
would otherwise roll back. Retry at most **three total attempts**, with bounded jitter
(50–150 ms, then 150–350 ms), new ContextID, fresh locks/time/eligibility, and the **same
caller operation reference and intent** for funding/payment. Do not retry validation,
permission, cipher-authentication or conflicting-reference errors. After exhaustion,
return `503 RETRYABLE_BUSY`. Each observed failed attempt may have one failure event;
there is still only one committed business effect. A lost connection/commit response is
`OUTCOME_UNKNOWN`, never proof of rollback. Resolve a financial action using its receipt
on a new connection; other actions require a state read before a new user action.

Multi-query reports RQ-02–08 use **REPEATABLE READ, WITH CONSISTENT SNAPSHOT**, read-only
transactions so detail/totals share one committed read view. Set server `AsOf` immediately
after establishing that snapshot and use it for all due-date arithmetic; it labels the
snapshot's evaluation time, not arbitrary time-travel access. Rows committed after the
snapshot are excluded. An authorization read in that same snapshot scopes all results;
next request rechecks revocation. RQ-01 instead uses the locking protocol in §7.1 so its
eligibility checks have one current protected basis. No paginated response claims that
its result will remain fundable after its transaction ends.

Technical basis: MySQL [isolation levels](https://dev.mysql.com/doc/refman/8.4/en/innodb-transaction-isolation-levels.html),
[error handling](https://docs.oracle.com/cd/E17952_01/mysql-8.4-en/innodb-error-handling.html),
and [trigger restrictions](https://dev.mysql.com/doc/refman/8.4/en/faqs-triggers.html).
The locking protocol is this project's design; its race behavior remains to be tested.

### 6.2 Retaining failed evaluations without reusing numbers

For a successful Review/Funding evaluation, take `1 + MAX(AttemptNumber)` for that
request/kind **while holding its borrower and request locks**, then insert it. Submission
always uses 0 and is unique. Attempt numbers are insertion order within kind, not a
promise about wall-clock order across failures. EvaluationID is a separate auto ID;
gaps after rollback are allowed.

Before a failed eligibility action is rolled back, capture only the already-computed
summary (encrypted burden with its immutable request/kind/context identity, flags, original EvaluatedAt,
kind, request, ContextID, and verified reviewer). After rollback, `sp_record_failure`
starts a **new application-owned transaction**, locks the same User/request parents,
re-reads MAX and allocates a **new** attempt number. It never reuses a number calculated
in the rolled-back action and never recalculates historical facts from changed records.
Preserve the failed attempt's original ContextID/time; CompletedAt equals its check time.
Decision, Reason and DecidedAt remain NULL for a blocked approval. No loan, commitment,
receipt or request-state effect is recreated by failure recording.

EvaluationID is assigned by AUTO_INCREMENT **when the row is actually inserted**.
Encrypt its burden using `(RequestID, EvaluationKind, ContextID)` as authenticated
identity (§7.1), all known before insertion. Do not reserve IDs using MAX(EvaluationID),
insert fake ciphertext, or assume a rolled-back ID will be reused. The after-rollback
row receives its own new EvaluationID. To retry a failure-record write after unknown
delivery, under the same parent locks first locate `(RequestID, EvaluationKind, ContextID)`;
if present, verify matching facts and return it. The parent lock serializes that
lookup/insert without a new unique column or table. RepaymentNumber is separately
allocated as `1 + MAX` within LoanID while its Loan lock is held; gaps do not alter balances.
For a completely missing target, only an Attempt event is possible; duplicate diagnostic
observations are tolerated and never counted as business success. Failure logging errors
are reported safely to operations; they cannot turn a denied action into success.

### 6.3 One owner for repayment completion

`sp_post_repayment` locks the loan/schedule, validates owner/status/amount, creates the
receipt and Repayment, then computes allocations in memory using cents. It issues
**single-row `INSERT ... VALUES`** statements into RepaymentAllocation in oldest-first
order. Do not use an allocation `INSERT ... SELECT` that also reads Loan: its trigger
updates Loan, and MySQL restricts modifying a table used by the invoking statement.

`trg_allocation_after_insert` alone performs Active → Repaid. After each allocation,
it reads the current schedule/allocation/payment sums for `NEW.LoanID` and requires:

1. Exactly the request's 3 or 6 schedule rows, positive amounts, sum = original principal.
2. Every installment has allocated sum <= its scheduled amount.
3. Every posted repayment on this loan is fully allocated, and total posted repayments
   = total allocations = original principal. Thus remaining principal is exactly zero.
4. The loan is still Active. Conditional UPDATE affects exactly one row.

Only then set LoanState=Repaid, CompletedAt=the current Repayment.PostedAt,
ObservedCondition=Current and LastEvaluatedAt=that time, and append exactly one
`LoanCompleted` event with its prior/new state/condition, operation and initiating user.
This trigger owns that transition and its audit; the procedure must not repeat either.
If remaining principal is nonzero or the current payment is not yet fully allocated,
there is no completion. Any negative remainder is an integrity error, not completion.

After its allocation loop, the procedure independently verifies reconciliation and
oldest-first allocation and raises on any mismatch (rolling back trigger effects too).
For a still-Active loan only, it refreshes observed delinquency and emits
`DelinquencyChanged` only if the condition changed. For a newly Repaid loan, the
`LoanCompleted` event already records clearing the condition; no duplicate clearing event.
Then append `RepaymentPosted`, serialize the original receipt and commit. That event's
financial details reference immutable allocations. Required trigger context comes from
the validated repayment/receipt/borrower rows; do not trust client-set session actor IDs.
A test must show partial payment: zero completions; final payment: one; exact retry:
still one; injected error after final allocation: zero new effects of any kind.

## 7. Procedures, functions, triggers, and authorization

Planned command routines: sp_create_user, sp_set_role, sp_set_account_status,
sp_save_profile, sp_save_draft, sp_submit_request, sp_assess_request,
sp_review_request, sp_commit_funding, sp_cancel_request, sp_expire_request,
sp_post_repayment, sp_evaluate_delinquency, sp_append_note, sp_append_audit,
sp_record_failure. Helpers validate current entitlements, capture a summarized evaluation,
generate monthly due dates, and calculate exact cents. These names are an implementation
plan, not implemented objects. Map final SQL names back to the same FRD IDs.

Use BEFORE UPDATE/DELETE guards for immutable submitted terms, completed evaluations,
financial event contents, schedules, notes, receipts, and audit history. Allow only
documented set-once fields and lifecycle/observation changes. The exact
`trg_allocation_after_insert` completion predicate and sole ownership of completion/audit
are specified in §6.3. Business validation errors propagate to the application-owned
rollback envelope; §6.1 defines isolation and whole-transaction retries.

The API derives actor/role from a validated session, never request body claims. Recheck
User status and active UserRole on every protected request. Administrator/Auditor are
separate from lending accounts. Role removal/deactivation cannot strand live obligations;
Restricted borrowers may still repay. Apply the complete FRD SEC-01–SEC-14 matrix.

Lender loan access uses EXISTS of an Applied FundingCommitment whose OperationReceipt
caller is the lender and whose RequestID is that Loan's origin. Do not authorize all
loans of that borrower. Expose BorrowerID/LoanID, complete schedule and permitted payment/
delinquency data; exclude contact, assessment inputs, notes, other lenders' identities
and individual contributions. Pending/Released commitments grant only their limited
receipts/request summaries. Borrowers see own records; Admin sees review data; Auditor
has redacted read-only history. Hidden UI buttons are not enforcement.

Implement at least three technical database roles and sample accounts: command service
(EXECUTE approved mutations), query service (EXECUTE scoped reads), worker (EXECUTE
assessment/expiration/evaluation only). Use a locked least-privilege routine definer and a
separate build administrator. No runtime account gets general DDL or direct table DML.
Demonstrate GRANT/REVOKE and allowed/denied access on at least three protected objects;
temporary evaluator access must be revoked. Human application roles remain separately
enforced by identity/ownership rules. Shared technical credentials are never exposed to UI.

Encrypt email, current/frozen financial inputs, and retained exposure totals in the trusted
service (authenticated envelopes, fresh nonces, key identifiers, and record/field-bound
authenticated context). Authentication failure aborts the action. Never expose plaintext
through general views, audit changes, or error bodies. Passwords are salted adaptive hashes.
Keys/configuration come from environment/secret injection, never seeded real credentials.

### 7.1 Encryption and eligibility contract

**The trusted service owns keys and decryption; SQL owns the eligibility formula and
current obligation queries.** Browser-supplied Pass/Fail, exposure, actor IDs or ciphertext
are never accepted. Private values cross the service→DB TLS connection only as bound,
short-lived DECIMAL parameters; they are never stored as plaintext columns, audit values,
receipt fields, general logs or routine diagnostics. Disable SQL/parameter tracing for
these routines, including connector/APM logging. A compromised trusted service is outside
this separation: SQL cannot independently prove that a supplied plaintext is the correct
decryption without possessing the key. Least privilege does not make that claim.

| Step | Service responsibility | Routine responsibility |
| --- | --- | --- |
| Prepare | Reserve one connection and start §6.1 transaction; supply verified actor, target and generated ContextID | `sp_prepare_eligibility` locks participants/parents; validates entitlement; resolves an existing receipt first; returns exact input envelopes, source identities/versions and locked current exposure/delinquency at T |
| Decrypt | Authenticate envelopes locally; validate income > 0 and external obligations >= 0; use frozen request fields for review/funding, current profile for submission, retained submission inputs/total for assessment | No keys, decryption function or browser-accessible private-data view |
| Calculate | Bind decrypted income/external obligations (and retained burden for assessment) to `sp_calculate_eligibility` on the **same connection/transaction** | Revalidate target/version and envelope digests; calculate cents/largest installment and Pass/Fail; use DB-derived current burden for submission/review/funding, retained burden for assessment; return summary only to service |
| Finish | Encrypt the computed summary with request/kind/ContextID; for submission re-encrypt input values with request-bound context; call action routine without releasing locks | Validate prepared identity/time/versions and matching calculation context; write frozen inputs/evaluation/action/audit atomically; never accept a client eligibility flag |
| End | Commit or rollback and discard plaintext; clear preparation context before pool reuse | Clear connection-local preparation variables after finish; a finish without the matching active prepare/calculate context fails |

Submission retains its burden and NoDelinquencyPass but leaves AffordabilityPass and
CompletedAt NULL; its later assessment completes those from retained values exactly once.
The calculate routine returns condition outcomes to the trusted coordinator before a
business eligibility rejection, so failed Review/Funding facts can be captured before
rollback. A false check blocks Approve/new funding; it does not block an Administrator's
Reject decision or silently change the submission workflow. Precondition/SQL failures
before any completed check produce only the separate Attempt event.

Preparation state is connection-local, short-lived routine state, **not another application
table**. It includes action, actor, target, ContextID, digests,
versions, T, and calculated numeric/boolean results. Routines set it; public API callers
cannot call DB routines or set DB session variables. A disconnected or pooled-to-another
connection attempt must prepare again. Returning a connection with unfinished work is an
error. Authenticated encryption cannot safely be implemented by copying a profile blob
into a request field because their authenticated contexts differ.

Use AES-256-GCM, a fresh random 12-byte nonce per encryption and a versioned key ID.
Envelope bytes: `ML1 || uint8(keyIdLength) || keyIdASCII || nonce || ciphertextWithTag`.
AAD is UTF-8 compact JSON `[table, recordBinding, column]`. Bind BorrowerProfile by
UserID and LoanRequest by RequestID (decimal strings). Bind User private email by its
immutable random PublicAlias, known before UserID allocation. Bind RequestEvaluation
by `RequestID/EvaluationKind/ContextIDhex`, all immutable and known before EvaluationID
allocation. This avoids the impossible requirement to encrypt a NOT NULL column using
an auto ID that does not yet exist. PublicAlias is generated once and never edited;
ContextID is server-generated, never supplied by the browser. Amount plaintext is a canonical decimal string with
two places. A new field-bound envelope must fit VARBINARY(128)/(512); reject oversize.
The fixture materializer uses this same wire format for fictional values. Key and sample
password arrive from environment injection; they are not written to Git. AES keys, raw
passwords, ciphertext, note/review free text and private numeric values never enter
AuditChange. General failure responses use catalogue codes only.

**RQ-01:** the query coordinator collects candidate OpenFunding request IDs, locks the
caller and all candidate borrowers in ascending ID order, then their request IDs; it
revalidates the candidate set/filters after locks and captures one T. For this classroom
scope, inspect the complete candidate set before applying the page limit. New candidates
appearing after initial selection are excluded from this response and can appear on the
next request. The service decrypts each candidate's frozen inputs internally; calculate
routine uses current locked obligations and returns eligibility. `sp_rq01_fundable`
returns **only** the FRD RQ-01 public projection for passing candidates in deadline/ID
order. No per-candidate evaluation history is inserted for a listing. Pagination filters
follow eligibility, not a client-provided list of passing IDs. Any cipher failure aborts
the report safely; it must not silently label a failed check fundable. Funding always
rechecks independently; listing does not reserve principal. This is a bounded classroom
implementation choice, with lock duration to be measured on the larger dataset.

**Early reporting gate:** before accepting this locking strategy, run 10/100/1,000 open
requests distributed across borrowers, with 1/5/10 marketplace readers plus concurrent
submission, repayment and funding writers for both overlapping and unrelated borrowers.
Compare browsing off/on; record candidate/page counts, decrypt time, transaction/lock-held
time (p50/p95/max), writer latency, lock waits, deadlocks and timeouts, alongside hardware,
DB version and isolation. Agree an acceptable classroom response/write budget before the
run and report observed results against it; no measurements exist yet. If browsing causes
unacceptable blocking, review a bounded-candidate or snapshot/revalidation approach before
changing the documented report consistency/pagination contract. Funding must always
recheck eligibility atomically. Do this with the first executable report, not only at the
final demo; an index or cache alone does not resolve holding many borrower locks.

## 8. Reports, audit, indexes, and performance

Derived helpers: v_request_funding (one request); v_installment_balance (one installment);
v_loan_balance (one loan). They are query definitions, not stored application entities.
Overdue values require an explicit report time T and are calculated in report procedures.
Aggregate payments/allocations before joining participation; use EXISTS so repeated
contributions cannot multiply loan totals. These views alone do not authorize callers.

| Report | Routine / source and grain | Access |
| --- | --- | --- |
| RQ-01 | sp_rq01_fundable + trusted decryption coordinator (§7.1): one eligible OpenFunding request; current check, capacity, deadline; deadline/ID order | Lender; approved public fields only |
| RQ-02 | sp_rq02_borrower: owned request/loan headers plus separately grouped schedule/payment details | Owning Borrower |
| RQ-03 | sp_rq03_lender: own commitment events; distinct Applied loan summaries separately | Participating Lender |
| RQ-04 | sp_rq04_worklist: unpaid installment grain at T; date/loan filters | Owner / participating Lender / Admin / Auditor |
| RQ-05 | sp_rq05_delinquency: one delinquent loan, authorized totals only; days-past-due descending | Participating Lender / Admin / Auditor |
| RQ-06 | sp_rq06_monthly: monthly repayment count, distinct loans, sum/average/running total; zero-filled months | Admin / Auditor |
| RQ-07 | sp_rq07_review_queue: PendingReview or OpenFunding without Pending contributions | Admin / redacted Auditor |
| RQ-08 | sp_rq08_history: events linked to request, resulting loan and their children; time/event ID order | Admin / redacted Auditor |

FRD §10 remains authoritative for all fields, filters and ordering. Map history through
validated typed subject keys and immutable relationships; include both request and loan
contexts. Success AuditEvent/AuditChange rows commit with the action. Failure/denial rows
are written separately after rollback using captured context; they do not resurrect the
business effects. A killed connection cannot guarantee its own failure log. Observe and
record interrupted outcomes during recovery, and inspect for committed receipts first.

Candidate indexes beyond PK/UNIQUE/FK support: LoanRequest(BorrowerID,RequestState),
LoanRequest(RequestState,FundingDeadlineAt,RequestID), FundingCommitment(RequestID,
CommitmentState), Installment(DueDate,LoanID,InstallmentNumber), Repayment(PostedAt,LoanID),
AuditEvent(SubjectType,SubjectKey,OccurredAt), AuditEvent(ContextID,OccurredAt).
Existing receipt caller/reference and evaluation request/kind/attempt indexes support
identity and history lookups. Explain each index with RQ/business use; avoid duplicates
of leading keys. Compare EXPLAIN/EXPLAIN ANALYZE, time, index bytes and write cost with
deterministic larger fixtures. Record workload/data size, parameters and cache conditions;
a small-fixture full scan can be reasonable. No unmeasured latency/throughput claim.
Batch imports/large extracts are measured separately from short interactive writes.
Tune only from evidence; a cache/replica/partition is not required for this release.

### 8.1 Audit catalogue and redaction contract

The authoritative finite catalogue is [audit-catalogue.json](diagrams/audit-catalogue.json).
It is version-controlled implementation configuration, **not an additional lookup table**.
SQL CHECKs and `sp_append_audit` must use exactly these event/outcome/subject/service/reason
sets. The table below is its readable rendering. A normal listed event has Success;
AttemptRejected has Denied, TransactionFailed has Failed, and InterruptionObserved has
Interrupted. A failed attempt never uses a business-success event name.

| EventType | SubjectType | Actor | Allowed AuditChange fields |
| --- | --- | --- | --- |
| `UserCreated` | User | Administrator / Bootstrap (fresh build) | LoginName, PublicAlias, AccountStatus, PrivateEmailCipher, PasswordHash |
| `AccountStatusChanged` | User | Administrator | AccountStatus, StatusReason |
| `RoleGranted` | UserRole | Administrator / Bootstrap (fresh build) | UserID, RoleCode, GrantedAt |
| `RoleRevoked` | UserRole | Administrator | RevokedAt |
| `ProfileSaved` | BorrowerProfile | Borrower | MonthlyIncomeCipher, ExternalObligationsCipher |
| `RequestSaved` | LoanRequest | Borrower | Purpose, Principal, InstallmentCount, RequestState |
| `RequestSubmitted` | LoanRequest | Borrower | RequestState, PolicyCode, SubmittedAt, EvaluationID, SubmittedIncomeCipher, SubmittedObligationsCipher |
| `AssessmentCompleted` | RequestEvaluation | Assessment | RequestID, Result, NoDelinquencyPass, AffordabilityPass, CompletedAt, RequestState |
| `ReviewApproved` | RequestEvaluation | Administrator | RequestID, Decision, DecidedAt, FundingDeadlineAt, RequestState |
| `ReviewRejected` | RequestEvaluation | Administrator | RequestID, Decision, DecidedAt, RequestState |
| `CommitmentAccepted` | FundingCommitment | Lender | RequestID, EvaluationID, Amount, CommitmentState, PendingTotal |
| `CommitmentApplied` | FundingCommitment | Activation | CommitmentState, AppliedAt, LoanID |
| `LoanActivated` | Loan | Activation | RequestID, LoanState, ActivatedAt, InstallmentCount, Principal, RequestState |
| `RequestCancelled` | LoanRequest | Borrower / Administrator | RequestState, TerminalReason |
| `RequestExpired` | LoanRequest | Expiration | RequestState, FundingDeadlineAt |
| `CommitmentReleased` | FundingCommitment | Release | CommitmentState, ReleasedAt |
| `RepaymentPosted` | Repayment | Borrower | Amount, AllocationCount, OutstandingBefore, OutstandingAfter |
| `LoanCompleted` | Loan | RepaymentCompletion | LoanState, CompletedAt, ObservedCondition |
| `DelinquencyChanged` | Loan | Delinquency | ObservedCondition, LastEvaluatedAt, OldestOverdueDueDate, OverduePrincipal |
| `NoteAppended` | OversightNote | Administrator | RequestID, LoanID, CorrectsNoteID |
| `AttemptRejected` | Attempt | Verified caller / unauthenticated / listed services | None |
| `TransactionFailed` | Attempt | Verified caller / unauthenticated / listed services | None |
| `InterruptionObserved` | Attempt | Recovery | None |

Actor rules are alternatives in each event's JSON `actors` list: choose one complete
human or service rule; never combine a permitted role from one with a service from another.
Successful human events require ActorUserID, the event's permitted ActingRoleCode and a
role grant active at OccurredAt; ServiceActor and InitiatingUserID are NULL. Procedures
also enforce the action's account-status rules under lock. A historical role is checked
at the event time, not against today's grants. The caller identity/role comes from trusted
session context, not the request body or an editable audit payload.

Bindings are mandatory: ProfileSaved uses the profile owner; RequestSaved/Submitted and
Borrower cancellation use Request.BorrowerID. Administrator cancellation may target any
otherwise cancellable request. Review events match the evaluation's AdministratorID,
Decision and ContextID; role events match GrantedBy/RevokedByUserID; NoteAppended matches
the note author. CommitmentAccepted matches the subject's receipt, caller, CommitFunding
action and evaluation ContextID. RepaymentPosted matches its receipt, PostRepayment action
and owning borrower. Merely having the right role is insufficient.

Services have NULL ActorUserID/ActingRoleCode and exactly the listed ServiceActor.
Activation events use the **final contribution's** committed operation and initiating
Lender, even when applying an earlier pledge from a different lender; its original receipt
identifies the activated loan and its evaluation supplies ContextID. RepaymentCompletion
and repayment-triggered Delinquency use the same repayment operation/context and initiating
Borrower as RepaymentPosted. Release matches the same-context RequestCancelled/Expired
parent: retain the cancelling human or the expiration initiator, including NULL for a
scheduled expiration. Assessment completes a Submission evaluation; its own command context
may differ from the retained submission's immutable encryption context. Scheduled
Assessment/Expiration/Delinquency has no initiator; a manual invocation retains an
Administrator. No-operation Delinquency and repayment-originated Delinquency are explicit
alternatives, not permission to attach any user to a service event.

Only UserCreated and RoleGranted permit Bootstrap, with no human actor/role/initiator.
Bootstrap RoleGranted has NULL GrantedByUserID. Both require a fresh-build execution path
and a trusted build connection; the runtime role must have no access to that path. The
reference verifier explicitly receives the allowed build identity; its default runtime
mode rejects Bootstrap. An event-provided flag or technical-account string cannot grant
that trust in the application. No other event gains a Bootstrap exception; failed fresh-build steps belong in the operational build log.

Denied/failed attempts retain a verified caller (role may be NULL if none was verified),
an unauthenticated context, or an explicitly listed originating service. JSON
`service_failure_actions` binds each such service to its actual command; e.g. Expiration
cannot explain a CommitFunding failure. Recovery is reserved for InterruptionObserved.
Failures must not fabricate a required role or reference a rolled-back receipt. Optional
failure initiators must identify verified users. TechnicalAccount is obtained from
`SESSION_USER()` on the connection, never caller JSON or definer CURRENT_USER().

SubjectType is one of the ten types in the JSON. Numeric keys are canonical unsigned
base-10 without leading zeros; Repayment uses `LoanID/RepaymentNumber`. Attempt uses
`ActionCode/target`, with target `none` if absent or `invalid` if malformed. ActionCode
is one of the command suffixes in §7 (`CreateUser`, `SetRole`, `SetAccountStatus`,
`SaveProfile`, `SaveDraft`, `SubmitRequest`, `AssessRequest`, `ReviewRequest`,
`CommitFunding`, `CancelRequest`, `ExpireRequest`, `PostRepayment`,
`EvaluateDelinquency`, `AppendNote`) or `SignIn`, `ReadReport`, `ReadDetail`.
A valid decimal/tuple attempted target is allowed even if nonexistent. Never serialize
raw URLs, SQL, passwords, login input or body strings into SubjectKey. RQ-08 follows
validated typed keys plus their immutable FK path; Attempt keys are interpreted by
ActionCode and verified target kind. They are not SQL identifiers or dynamic SQL.
ContextID is a server UUID encoded as 16 bytes, not the old fixture label strings.
OperationID is NULL if no receipt committed; AttemptedOperationReference is retained
only if it passes the opaque-reference grammar. A rolled-back receipt ID is not an FK.

Reason codes (exact whitelist): `NOT_AUTHENTICATED`, `ROLE_REQUIRED`, `OWNER_REQUIRED`,
`PARTICIPATION_REQUIRED`, `ACCOUNT_RESTRICTED`, `ACCOUNT_INACTIVE`, `ROLE_CONFLICT`,
`LIVE_PARTICIPATION`, `STALE_VERSION`, `DUPLICATE_LOGIN`, `DUPLICATE_ROLE`, `INVALID_INPUT`,
`INVALID_STATE`, `POLICY_LIMIT`, `DEADLINE_REACHED`, `SELF_FUNDING`, `CAPACITY_EXCEEDED`,
`OVERPAYMENT`, `OPERATION_CONFLICT`, `CIPHER_INVALID`, `AFFORDABILITY_FAIL`,
`DELINQUENCY_PRESENT`, `DB_DEADLOCK`, `DB_LOCK_TIMEOUT`, `DB_ERROR`, `CONNECTION_LOST`,
`ADMIN_DECISION`, `BORROWER_CANCELLED`, `WORKER_EXPIRED`, `INTEGRITY_FAILURE`, `UNKNOWN_TARGET`.
Denied/Failed/Interrupted requires a reason. Review decisions and account-status changes use ADMIN_DECISION;
owner cancellation BORROWER_CANCELLED (Administrator cancellation ADMIN_DECISION);
expiration WORKER_EXPIRED. Otherwise successful events normally have NULL reason.
If both eligibility conditions fail, retain both flags; use DELINQUENCY_PRESENT as
primary ReasonCode. Free-text review/terminal reasons stay in protected source records;
no free-text SQL exception is a reason code.

AuditChange allows only the fields listed for its event. They may be source attributes
or named derived context scalars (PendingTotal, OutstandingBefore/After, AllocationCount,
OldestOverdueDueDate, OverduePrincipal). Record each changed scalar in its own child row;
no CSV/JSON arrays in FieldName/values. Encode IDs/integers as decimal, money to two places,
bools 0/1, dates ISO date and timestamps UTC; NULL means absent on creation/clear.
PrivateEmailCipher, PasswordHash, financial input ciphers and PlatformBurdenCipher have
NULL OldValue and NewValue if a permitted private-field change is recorded; **never copy
ciphertext or hashes into the general audit feed either**. NoteText, review Reason,
DisplayName and arbitrary input strings are not in the allowlist. Purpose is a permitted
business description in request history, with its declared 1000-character bound.

**Retained account-status explanation (FR-03; FRD §9.2):** every successful restriction,
reactivation or deactivation appends exactly one AccountStatus change (old/new status)
and one `StatusReason` change. Store the API's explanation in AuditChange.NewValue with
FieldName=StatusReason and OldValue=NULL; it is new event context, not a User column or
an overwritten prior explanation. Trim before validation; require 1–1000 Unicode
characters, reject empty/oversize input without truncation, and use ReasonCode=ADMIN_DECISION.
The status update, both change rows and the event commit atomically; an append failure
rolls back the update. Each transition retains its own explanation indefinitely with
protected history. The inactive-to-restricted shortcut remains invalid under the FRD.

StatusReason is the **bounded exception** to the arbitrary-input exclusion above. It is
an administrative explanation, not a place for financial inputs, contact details,
credentials or raw request bodies. Direct application-role reads of audit tables remain
denied. The Administrator audit read projection may return this explanation; the Auditor
projection retains FieldName but returns NULL for both values, following the existing
internal-note redaction rule. Borrowers/Lenders cannot read the general audit feed.
Implement this projection in trusted read routines, never only by hiding UI text. The
reference projection in audit_rules.py specifies the result; actual SQL/API access tests
remain required. No new entity, column, FK or free-form event payload is introduced.

At minimum record prior/new state on every state-changing event, accepted amount and
source identifier on monetary events, decision/result on evaluation events, and changed
private field names with NULL values for profile saves. Referenced immutable repayment
allocations and schedules supply full child detail; per-child CommitmentApplied/Released
events identify every changed pledge. On assessment/review, RequestID and ContextID
link the request-state transition to the evaluation; their allowlists include RequestState so RQ-08 preserves its old/new value. Read routines additionally apply FRD
SEC-11/12 redaction (Auditor gets no protected input values or free-text internal notes).
General audit-feed access is Administrator/Auditor only; lender monitoring uses RQ-03–05.
Neither business role can UPDATE/DELETE AuditEvent/AuditChange. Audit append failure
rolls back the business transaction. Attempt/event append procedures themselves are not
public endpoints and cannot accept arbitrary event names/field values from the browser.

## 9. Build and operational evidence

Implement the professor's exact-tag Bash or PowerShell runner and numbered SQL manifest:
preflight tools/config/tag/files/order before changes → safe fresh schema → tables/keys/
indexes → reference/full historical sample data → views/functions/procedures/triggers →
roles/grants → object/data/smoke validation and EXPLAIN. Historical fictional seeds load
with all FK/CHECK/UNIQUE constraints enabled, before lifecycle triggers are installed;
action-driven acceptance tests run afterward through the normal service/routines. Fixed D1 checks/labels and Role rows must agree.
Stop on the first unexpected SQL failure; failed assertions must fail the build, not
merely print FAIL. Record tag + commit + per-script timestamps/results/safe errors.
Refuse replacement of an existing database without explicit opt-in. Never leak secrets.
DDL is not a single business transaction: a failed build may leave a partial schema;
log it as failed and rebuild fresh. Business transaction rollback remains required.

Keep these operational tables in `build_admin`, outside the 15 application entities:

### build_admin.BuildRun

| Attribute | Type | Nullable | Constraint |
| --- | --- | --- | --- |
| BuildRunID | `BINARY(16)` | No | PK |
| RequestedTag | `VARCHAR(100)` | No | Nonblank |
| ResolvedCommit | `CHAR(40)` | Yes | Hex SHA when resolved |
| TargetSchema | `VARCHAR(64)` | No | Identifier allowlist |
| StartedAt | `DATETIME(6)` | No | UTC |
| FinishedAt | `DATETIME(6)` | Yes | Completion time |
| Outcome | `VARCHAR(12)` | No | CHECK |
| EnvironmentManifest | `TEXT` | No | Redacted machine-readable evidence |

### build_admin.BuildStep

| Attribute | Type | Nullable | Constraint |
| --- | --- | --- | --- |
| BuildRunID | `BINARY(16)` | No | PK part; FK build_admin.BuildRun.BuildRunID |
| StepNumber | `SMALLINT UNSIGNED` | No | PK part; CHECK > 0 |
| ScriptPath | `VARCHAR(255)` | No | UNIQUE within build |
| ScriptSHA256 | `BINARY(32)` | No | Exact content digest |
| StartedAt | `DATETIME(6)` | No | UTC |
| FinishedAt | `DATETIME(6)` | Yes | Completion time |
| Outcome | `VARCHAR(12)` | No | CHECK |
| SafeError | `TEXT` | Yes | Redacted diagnostic |

BuildStep has the one operational FK BuildRunID → BuildRun.BuildRunID and is identified
by (BuildRunID,StepNumber); UNIQUE(BuildRunID,ScriptPath). A run has zero or many steps,
including zero when retrieval/preflight fails; every step has exactly one run. BuildRun's
resolved commit is nullable before retrieval. File logs exist even when DB logging is
unavailable. The operational dictionary has 16 columns and is excluded from application
counts. No separate build ERD page or audit document is needed.

## 10. Validation, demo, and traceability

The [ERD worked cases and checklist](ERD.md#worked-cases) and executable design verifier
cover schema inventory, source/export agreement, positive/negative fixture relationships,
repeated funding, retries/conflicts, multi-loan balances, allocation, and scoped delinquency.
It also runs targeted audit regressions for wrong/missing roles and services, historical
role validity, owner/reviewer/receipt/initiator mismatches, unauthorized Bootstrap,
status-explanation boundaries and redacted read projections. These checks share the
catalogue with the fixture validator; a wrong-role CommitmentAccepted must fail.
They validate the model and complete seed specification, not an application implementation.
MySQL integration remains unverified. §10.1 defines fixture materialization and open gates.

Before claiming implementation completion, execute: each PK/FK/UNIQUE/NOT NULL/CHECK
failure; immutable-update/delete denial; authorization/GRANT/REVOKE cases; positive and
boundary workflow tests; injected error after each step of activation/repayment/audit;
killed-session rollback; two-connection races for submissions/funding/repayment and
funding versus cancellation/expiration; lost-response retry; and real EXPLAIN/timing.
Record SQL/procedure, expected and actual results, before/after rows, and database version.
The demo starts from a tagged fresh build, then identity/permissions, two loans for one
borrower, repeated funding, repayment/overdue follow-up, rollback/race/retry, reports/audit,
and UI actions. Model samples are not substitutes for those demonstrations.

| FRD requirements | Implementing subjects / method | Required evidence |
| --- | --- | --- |
| FR-01–FR-04 | User/Role/UserRole, unique identity, current entitlement and status routines | Active membership uniqueness, grant/revoke, restriction and next-action denial |
| FR-05–FR-07 | BorrowerProfile, LoanRequest frozen fields, Submission RequestEvaluation | Input boundaries, profile/snapshot separation, concurrent multi-request summaries |
| FR-08–FR-09 | RequestEvaluation flags/completion/final-review marker, request state | $200 versus $199.99 affordability; delinquency rejection; blocked review retry; one final decision |
| FR-10–FR-16 | LoanRequest, FundingCommitment, receipt, evaluation, Loan, Installment | Repeat contributions, cap/deadline/self-funding, one activation, release all pledges, rollback |
| FR-17–FR-23 | Loan/Installment/Repayment/Allocation, observation, OversightNote | Partial/early/oldest-first allocation, overpayment denial, per-loan delinquency, note correction |
| FR-24–FR-26 | RQ-01–RQ-08 scoped projections and correctly grouped totals | Two loans for one borrower; repeat contributions do not multiply authorized totals |
| FR-27–FR-29 | Entitlements, audit tables, domain checks and transition routines | IDOR denial, append-only history, private-field redaction, valid-code invalid transition denial |
| FR-30–FR-32 | Caller/reference uniqueness, locks, immutable events/FKs | Exact original response, conflicting reference, concurrent cap, killed transaction, protected history |
| FR-33 | Basic web UI through trusted Command/Query entrypoints | Successful and rejected request/funding/payment/review/report actions |

All BR-01–BR-26, SEC-01–SEC-14, RQ-01–RQ-08, and AC-01–AC-30 remain in the FRD.
Its §12 acceptance criteria and this document's method tables are the implementation
test contract. Do not invent a passing test, omit a failed condition, or change a rule
to satisfy a fixture. The only approved business reductions are fixed D1 and summarized
exposure history; raise any additional behavioral contradiction before implementation.

### 10.1 Fixture and implementation acceptance gates

[sample-records.json](diagrams/sample-records.json) now specifies every attribute of every
fixture row (generated columns contain expected values). It includes seven users: two
Borrowers (1,4), two Lenders (2,3), dual Borrower/Lender (7), Administrator (5), Auditor (6).
User 7 owns eligible request 104 and a denied self-contribution example; it has no access
to loans 501/502. Loan 501's two contributions by Lender 2 still grant one loan scope;
Lender 3 participates in both loans. All 15 entities have full records, with fictional
field-encryption/password directives, valid UUID contexts and lifecycle/denial audits.
User 7's July 3–6 status history preserves four separate explanations before live
participation begins; the final account is Active. Drafts 105/106 were cancelled by their
owner and the Administrator respectively, before any submission or funding. These cases
add records only and do not alter the worked loan balances or participation scopes.

Materialize SQL for a fresh constrained schema using the fixture tool. Supply
`FIXTURE_KEY_HEX` (32-byte key as 64 hex characters) and `FIXTURE_PASSWORD` (>=12 chars)
through the test environment, and use the same values in the future isolated demo service.
Do not commit those values or print them in logs. Do not reuse fixture credentials elsewhere.

```bash
python3 -m pip install -r docs/diagrams/tools/fixture-requirements.txt
python3 docs/diagrams/tools/materialize_fixture.py --output /tmp/micro_lending_seed.sql
```

The output is complete ordered SQL INSERTs, with generated columns omitted and actual
AES-GCM envelopes/Argon2id hashes. It does not create a schema, disable constraints, run
SQL, or implement workflows. Creation fails if the output file exists. The future build
must select a fresh schema, stop/rollback on errors, install triggers after this historical
seed, and assert all expected counts. Amounts and scenarios are deterministic; secure
nonces/salts deliberately make cryptographic bytes differ on each build. Fix the isolated
test clock at 2026-10-19T12:10:00Z for expected balances; never accept backdated public API
writes. Real application tests create new actions under a controlled server test clock.

| Priority | Completion evidence still required after this design revision | FR / rules / acceptance |
| --- | --- | --- |
| P0 | Instructor architecture answer; actual contributor names/section; tested dependency lock/digest when implementation begins | C-03/04/08; FR-33; AC-25/26 |
| P1 | Actual 15-table DDL, ordered build, SQL seed load/counts, constraint/role denial tests | FR-01–05/29/32; BR-01–03/19/21/22; SEC-01/06/13/14; AC-01/03/23/24/26 |
| P2 | Submission→activation routines/API; actual same-loan/multi-loan locks, cap, self-funding, deadlines, retries and rollback | FR-07–16/30/31; BR-04–13/20/23/24; AC-04–10/15/16/29/30 |
| P3 | Allocation/completion trigger, observation and notes; final-payment once-only and injected/killed-session rollback | FR-17–23/28; BR-14–18/21/23/25; SEC-08/11/12; AC-11–18/20/27 |
| P4 | RQ-01–08 field/scope assertions, early RQ-01 lock-contention gate (§7.1), basic UI walkthrough, denied ID guesses and duplicate-join checks | FR-24–27/33; BR-26; SEC-02–07; AC-06/19/21/22/25 |
| P5 | Larger deterministic dataset, measured plans/timings, tagged fresh rebuild, expected vs actual demo record | C-05/09/10; AC-26/28 |

Each stage uses requirement → rule → schema/routine/authorization → positive/negative
execution → demo evidence. Current assertions test artifact consistency and reference
calculations; they are not MySQL concurrency, rollback, encryption-boundary or API tests.
Fixture crypto round-trips test the materializer only. No native diagrams.net editing
round-trip has been performed; source/XML and direct-export agreement are checked.
