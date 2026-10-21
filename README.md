# Micro-Lending Platform

[SQL build order](database/manifest.txt) · [SQL walkthroughs and tests](tests/sql)

## Local MySQL setup

The current Mac has MySQL Community Server 26.7.0 and MySQL Workbench installed.
The command-line client is `/usr/local/mysql/bin/mysql`. This is the local
development version; the earlier MySQL 8.4.12 candidate remains untested.

Save the local administrator login once in Terminal. Enter the MySQL password
at the private prompt; do not put it in a script or commit it:

```bash
/usr/local/mysql/bin/mysql_config_editor set --login-path=cs437 --host=127.0.0.1 --port=3306 --user=root --password
```

From the repository root, create the development database and check transactions:

```bash
bash build/setup_local.sh
```

This creates `micro_lending_dev` with `utf8mb4` text support, then verifies
InnoDB commit/rollback and exact decimal storage using temporary tables.
Compare the displayed results with the expected values in the SQL comments.
If the database already exists, setup stops without replacing it. This script
is local environment setup, not the final tagged build or application schema.
The saved root login is for development setup, not an application runtime account.
These small local scripts use the installed MySQL path and saved `cs437` profile
directly. Run them from the repository root. Another computer may need a different
client path or its own saved profile.

Verified locally on October 20, 2026: MySQL 26.7.0, InnoDB, successful commit and
rollback checks, and rejection of a repeated setup with error 1007 (database
already exists). No permanent tables were left by those environment checks.
The full table schema and early account/request SQL operations are described below;
assessment, funding, repayment, and application integration remain pending.

Connect from Terminal:

```bash
/usr/local/mysql/bin/mysql --login-path=cs437 --database=micro_lending_dev
```

In MySQL Workbench, use host `127.0.0.1`, port `3306`, user `root`, and default
schema `micro_lending_dev`; enter the password through Workbench's own prompt.
To repeat only the temporary-table checks on an existing development database:

```bash
/usr/local/mysql/bin/mysql --login-path=cs437 --database=micro_lending_dev < tests/sql/environment.sql
```

## Complete table schema

[schema.sql](database/schema.sql) now creates all **15 application tables, 114
columns, and 27 foreign keys**, with 52 CHECK constraints. The table definitions
and early account/request operations are implemented; the full lending workflow
and application security remain pending.

The schema now focuses on keys, valid values, financial bounds, basic consistency,
and private-data redaction. Detailed submission/review field combinations and
audit event/actor/subject matching have been removed from table CHECKs by user
approval. Submission is now validated by the early workflow routines below; review
and the remaining audit combinations still need controlled operations. Direct-table
workflow validation remains reduced;
it is not equivalent to the earlier 61-check schema. See
[Milestone 10](docs/Milestones.md#milestone-10-basic-schema-checks) for the exact boundary.

| Area | Tables |
| --- | --- |
| Accounts | User, Role, UserRole, BorrowerProfile |
| Requests and assessment | LoanRequest, RequestEvaluation |
| Funding and loans | OperationReceipt, FundingCommitment, Loan, Installment |
| Payments | Repayment, RepaymentAllocation |
| Oversight and audit | OversightNote, AuditEvent, AuditChange |

From the repository root, after creating an empty development database, build once:

```bash
bash build/build_database.sh
```

The runner creates the tables, then installs views, functions, procedures and
triggers in order. It inserts the
[four role definitions](database/04_seed/010_reference_data.sql), then displays the
[schema overview](database/05_validation/010_object_validation.sql). It stops on SQL errors
and does not drop or replace existing objects. DDL is not rolled back as a group;
inspect any failed build before retrying.

The existing development database has already been extended to all 15 tables,
without rebuilding the original four. It contains only the four seeded Role rows;
all other tables are empty. Do not rerun the fresh-build command against it.
The earlier username update is preserved in
[alter_username_collation.sql](database/alter_username_collation.sql).

## SQL walkthroughs and tests

Run the schema overview and valid examples against the existing database:

```bash
bash build/test_database.sh
```

The runners were renamed from build_accounts.sh/test_accounts.sh because their
scope now covers the full database. They remain simple, direct MySQL commands.

| File | Expected valid results | Commented invalid examples |
| --- | --- | --- |
| [accounts.sql](tests/sql/accounts.sql) | Account defaults, case-insensitive login lookup, UTC grants, retained membership history | 28 (N01–N28) |
| [borrower_profile.sql](tests/sql/borrower_profile.sql) | Shared account/profile key, UTC/default version, explicit profile update | 10 (B01–B10) |
| [schema.sql](tests/sql/schema.sql) | Two requests for one borrower, repeated contributions, final-review marker, weak installment keys, allocations, redacted audit fields | 59 (retained S IDs) |

Read each file's expected results and compare them with the displayed values.
Execution errors stop the command, but unexpected query values require a person
to notice the mismatch. Each full-file walkthrough ends in ROLLBACK.

**Invalid examples are manual:** select micro_lending_dev as the default schema in
Workbench. Run Section 1 of the relevant file, stopping on any setup error. Select
the SQL after `--` for ONE invalid statement and execute it without the comment
prefix. Compare its error with the comment, then execute `ROLLBACK;` in the same
connection. Repeat setup for each case; do not run Section 3 between setup and an
invalid case. A rejected statement does not itself end the transaction.

Section 2B of tests/sql/schema.sql has **12 deferred-rule examples W01–W12**. W01/W02 now fail
with error 1644 under the frozen-request trigger; the remaining ten still succeed
at table level but are not valid application actions. They document
the reduced enforcement, rather than pretending the previous tests still reject
them. Inspect them individually with fresh setup and rollback. The remaining future workflows must validate their cases before accepting real actions.

Reserved names are demo_member, demo_admin, demo_other, profile_demo, and the three
schema_demo_ usernames. Existing conflicting names cause errors, not replacement.
Dummy protected fields/credentials are constraint-test placeholders, not usable
application values. A failed batch connection rolls back its uncommitted work;
auto-increment IDs may still have gaps. Oversize-value cases expect strict SQL mode.

Verified locally on MySQL 26.7.0: fresh build and role seed, all column/type/nullability
and key mappings, valid walkthrough outputs, all **97** remaining documented invalid errors,
and rollback with no retained test rows. A separate disposable test loaded all 343
fictional design-fixture rows with placeholder protected values and verified counts
and generated values. This is structural fixture evidence, not encryption or
application-security evidence. The repository scripts do not automatically run or
grade the commented invalid cases. Detailed evidence is in
[Milestones](docs/Milestones.md#milestone-8-complete-table-schema).

Usernames compare case-insensitively under the database default, which is also
accent-insensitive. Role/status codes remain case-sensitive. Future application
code must use canonical codes and enforce permissions. The schema alone does not
validate the deferred workflow combinations, encrypt data, authorize callers,
freeze history, prevent concurrent overfunding,
allocate repayments oldest-first, or append audit events for direct table writes.
The Draft-creation procedure below records its own success audit. Other procedures,
triggers, technical grants, full safe seed data, and workflow integration remain work.

## First stored procedure: create a Draft

[sp_create_loan_request](database/02_programmability/030_procedures.sql)
implements the creation part of FR-06. It checks the account is Active, its Borrower
role is current, its profile exists, and its purpose, amount ($100–$2,000), and term
(3 or 6 installments) are valid. It creates a Draft with version 0 and records one
RequestSaved audit event plus four field changes in the same transaction. Any SQL
error rolls back the entire action. It does not submit or evaluate the request.

The procedure is already installed in micro_lending_dev. It is grouped with the
other procedures in 030_procedures.sql. Use the complete fresh build or the
one-time upgrade described below; this file depends on the views and function.

Example, after an eligible borrower with UserID 1 actually exists:

```sql
CALL sp_create_loan_request(1, 'Equipment purchase', 300.00, 3);
```

It returns RequestID, RequestState = Draft, and RowVersion = 0. **Call it outside an
existing transaction:** it starts and commits its own transaction; an outer
ROLLBACK cannot undo the committed action. Never use guessed IDs in development.

Run the separate procedure walkthrough without retaining demo data:

```bash
bash build/test_create_loan_request.sh
```

This creates micro_lending_procedure_test, installs the schema and SQL objects, loads
roles, runs
three valid calls, displays their expected results, and drops that test database.
It refuses to replace an existing database. If a later step fails, it stops and
leaves the test database for inspection. The script checks execution errors;
compare displayed values with comments. The 17 invalid calls and optional forced
audit-failure demonstration in [create_loan_request.sql](tests/sql/create_loan_request.sql)
are commented out for individual execution before the test database is dropped.
To inspect those manually, run the runner's setup commands through role seed
loading, then Section 1 of that file; run each desired example and finally
drop only micro_lending_procedure_test.

Verified separately: all 17 invalid calls and their messages, three successful
calls, matching audit rows, and forced audit failure with complete rollback.
The table walkthroughs also still pass; development retains only four Role rows.

This is a local SQL demonstration, not completed application authorization.
The future trusted caller must obtain BorrowerID from the authenticated session;
the procedure cannot prove that a supplied ID belongs to the caller. SQL SECURITY
INVOKER uses the caller's database privileges. Runtime grants, failure auditing, and application integration are pending.
Draft editing and submission are now implemented on the SQL side below. Monetary
inputs are read as text and checked by fn_money before conversion to DECIMAL(18,2),
so fractional cents are rejected instead of rounded.
See [Milestone 11](docs/Milestones.md#milestone-11-first-stored-procedure).

## Account, profile, Draft editing, and submission operations

The SQL side of steps 1–3 is implemented. These are trusted-caller building blocks;
a sign-in system, runtime database grants, and the production encryption coordinator
are still pending. Do not expose these routines directly to a browser or accept
actor IDs, plaintext/ciphertext pairs, or prepared context from an untrusted client.

| Operation | Routine | Main behavior |
| --- | --- | --- |
| Create account | sp_create_user | Active Administrator required; creates Active account and redacted audit |
| Grant/revoke role | sp_set_role | Canonical roles, compatible combinations, retained membership history, live-participation protection |
| Change status | sp_set_account_status | Administrator, current version, reason; protects live participation from deactivation |
| Save profile | sp_save_profile | Own Borrower profile, valid income/obligations, encrypted values, version check; Restricted permitted |
| Edit Draft | sp_update_loan_request | Active owner, Draft state, current version, valid terms, atomic audit |
| Prepare submission | sp_prepare_submission | Starts transaction, locks borrower/profile/request, calculates exposure and delinquency, returns context and source envelopes |
| Finish submission | sp_submit_request | Same connection/context/transaction, validated inputs, frozen D1 snapshot and incomplete Submission evaluation, atomic audit/commit |

The SQL is grouped by object type:

| Build file | Contents |
| --- | --- |
| [schema.sql](database/schema.sql) | All 15 tables and their constraints |
| [010_views.sql](database/02_programmability/010_views.sql) | Remaining-installment view |
| [020_functions.sql](database/02_programmability/020_functions.sql) | Money-validation function |
| [030_procedures.sql](database/02_programmability/030_procedures.sql) | All 14 procedures, with helpers first |
| [040_triggers.sql](database/02_programmability/040_triggers.sql) | Frozen-request guard trigger |
| [010_reference_data.sql](database/04_seed/010_reference_data.sql) | Four business-role definitions |
| [010_object_validation.sql](database/05_validation/010_object_validation.sql) | Table, key, routine, view and trigger overview |

[manifest.txt](database/manifest.txt) lists the current SQL build order, starting
with database creation. setup_local.sh creates the empty database and checks the
environment; build_database.sh runs the remaining files. Walkthroughs and test-only
fixtures live under [tests/sql](tests/sql), separate from the build. Technical
security grants, full sample data and the final release-tag build remain pending;
no empty placeholder files are included for unfinished work.

The table schema and SQL behavior are unchanged by this grouping. Internal helpers
do not commit. All public actions except preparation commit their own action.
Call them outside an existing transaction.

Example signatures, using IDs/versions retrieved from the actual database:

```sql
-- NULL expected profile version means create; 0 means update version 0.
CALL sp_save_profile(borrower_id, NULL, '1000.00', '100.00', income_envelope, obligations_envelope);
CALL sp_update_loan_request(borrower_id, request_id, current_version, 'Equipment', '600.00', 3);
```

For submission the trusted caller must keep one connection reserved:

1. Call sp_prepare_submission with the authenticated borrower, owned request and
   current request version. SQL retains the borrower lock and returns profile
   envelopes, context, snapshot time, combined platform burden, and delinquency flag.
2. Authenticate/decrypt the profile, validate its numeric values, and encrypt fresh
   request-bound snapshots plus the calculated burden bound to
   RequestID/Submission/ContextHex. Use the returned uppercase ContextHex consistently.
   Keep keys out of SQL, source control, logs and audit values.
3. Call sp_submit_request on that connection with the matching binary context,
   decrypted income/obligations and prepared envelopes. It writes Submitted/D1,
   freezes input envelopes/time, adds the incomplete Submission evaluation and audit,
   then commits and clears context. On any coordinator failure, ROLLBACK and call
   sp_clear_submission before returning/discarding the connection.

Do not issue another command, commit/rollback, change connections, or wait for user
input between preparation and finish. An intervening commit loses the savepoint and
finish fails. Submission records eligibility inputs; **it does not perform assessment
or approval**, and does not reject solely for insufficient income or delinquency.
Later stages must use those retained facts. All future exposure writers must use the
same borrower lock. The guard trigger freezes terms/snapshots after Draft, including
case-only purpose edits; it does not implement every later lifecycle transition.

For a fresh empty development database use build/build_database.sh. The existing
local micro_lending_dev was upgraded without changing table data. To upgrade another
copy still at commit 947ad55, run **once**, from the repository root:

```bash
bash build/upgrade_early_workflows.sh
```

It creates the view and function first, replaces only the old Draft routine to
fix money rounding, then installs the grouped procedures and trigger. DDL is not
atomic. It stops on errors; inspect a partial upgrade before retrying. A normal
repeated run fails on the existing view before replacing the Draft routine. Do not rerun the fresh table build on
an existing database.

Run the automatic SQL checks in a disposable database:

```bash
bash build/test_early_workflows.sh
```

[early_workflows.sql](tests/sql/early_workflows.sql) contains **86 checks**
that stop on mismatches, including expected rejections, ownership/version/state
checks, redaction, and forced audit-failure rollback for all new writing actions.
Its explicit bootstrap and fictional bytes are test-only. The shell runner refuses
to overwrite an existing test DB, drops it on success, and leaves it on failure.
A [two-connection walkthrough](tests/sql/submission_concurrency.sql) reproduces
borrower-level submission ordering. Separately verified a real AES-256-GCM round trip
using a temporary test coordinator; that check is not a production sign-in/encryption
service. The committed build and workflow tests require Bash/MySQL, not Python.

Other evidence: fresh build/upgrade, repeated-upgrade safe stop, eight legacy
frozen-field examples, original Draft walkthrough, original table walkthroughs,
and a live two-connection submission race. The development database still contains
only four Role rows. See [Milestone 12](docs/Milestones.md#milestone-12-account-profile-draft-editing-and-submission).

## Current project documents

Use the documents under `docs/` for review and implementation. This repository
maintains one copy of each current document in that directory. Superseded
root-level drafts have been removed; their contents remain in Git history.

| Review order | Current document | Purpose |
| --- | --- | --- |
| 1 | [Functional Requirements Document](docs/Functional_Requirements_Document.md) | Business scope, actors, rules, permissions, reports, and acceptance criteria |
| 2 | [Technical Design Document](docs/Technical_Design_Document.md) | Architecture, complete data dictionary, transactions, security, and implementation plan |
| 3 | [ERD guide](docs/ERD.md) | Diagram navigation, requirement checklist, relationships, and worked examples |

The TDD and ERD guide remain at their committed design baseline for now. Track
current implementation progress and proposed future documentation updates in
[Milestones](docs/Milestones.md); earlier implementation-status statements in the
design documents describe their original snapshot. When we decide to revise the
design documents, update them in place and use Git history for earlier revisions.

## Diagrams

The course requires editable sources, SVG exports, and Markdown explanations.
Each SVG below represents a page in its corresponding source, not a separate
version of the design.

| Editable source | Page exports | Explanation |
| --- | --- | --- |
| [Micro_Lending_ERD.drawio](docs/diagrams/Micro_Lending_ERD.drawio) | [Conceptual](docs/diagrams/01-conceptual.svg), [accounts/funding](docs/diagrams/02-accounts-funding.svg), [repayments/oversight](docs/diagrams/03-repayments-oversight.svg) | [ERD guide](docs/ERD.md) |
| [Application_Design.drawio](docs/diagrams/Application_Design.drawio) | [Application flow](docs/diagrams/04-application-flow.svg), [wireframes](docs/diagrams/05-wireframes.svg) | [TDD §§2.1–2.3](docs/Technical_Design_Document.md#21-architecture-decision-and-editable-views) |

## Supporting material and implementation status

The model contains **15 application entities, 114 attributes, and 27 foreign keys**.
The initial design package was imported from the team repository's
[39c00d7 revision](https://github.com/anuvikdas/CS-437-Database-Systems-Implementation/commit/39c00d7558166178393ce3d549aabb4e3f17b724).
The documents linked above are the maintained review set in this repository.

[Course handouts](docs/course) are instructor references. JSON files under
`docs/diagrams/` describe model metadata, the audit catalogue, and fictional sample
records. Python tools maintain and validate these design artifacts; they do not
constitute a working MySQL schema or application.

Run the design checks with Python 3 and the standard library:

```bash
python3 docs/diagrams/tools/validate_erd.py
```

These checks cover artifact consistency, fixture calculations, and audit contracts.
All 15 table definitions have real MySQL schema/constraint evidence. A running
API/UI, funding/payment concurrency, complete application authorization, and
rollback for workflows beyond these early account/request operations remain
unverified. The local environment checks above verify basic database connectivity,
decimal storage, commit, and rollback.
The [TDD acceptance gates](docs/Technical_Design_Document.md#101-fixture-and-implementation-acceptance-gates)
identify the remaining implementation work and fixture materialization requirements.

The professor's architecture decision is still pending: whether one deployable
FastAPI service with command/update and query/extraction modules satisfies the
microservices requirement, or separate deployables are needed.
