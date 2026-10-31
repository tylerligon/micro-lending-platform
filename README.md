# Micro-Lending Platform

CS 437 Database Systems Implementation · Tyler Ligon and Anuvik Das

A classroom lending database with fictional money, controlled SQL operations, an
administrator console, configurable entitlements, table-driven request workflows,
and local observability.

## Current review documents

| Document | Purpose |
| --- | --- |
| [Professor follow-up responses, questions 1–24](docs/Midterm_Followup_Responses.md) | Consolidated answers, contribution timeline and current evidence |
| [Functional Requirements Document](docs/Functional_Requirements_Document.md) | Business requirements and full-release acceptance criteria |
| [Technical Design Document](docs/Technical_Design_Document.md) | Lending design baseline and current implementation amendments |
| [Entitlements and administration](docs/Entitlements.md) | Roles, scoped permissions, authentication, audit and operational boundaries |
| [Table-driven request workflows](docs/Table_Driven_Workflows.md) | Implemented state/action/transition rules, demonstration and upgrade instructions |
| [ERD guide](docs/ERD.md) | Original lending model and linked entitlement/workflow extensions |
| [Milestones](docs/Milestones.md) | Dated historical implementation and verification records |

`docs/` holds the maintained FRD/TDD; superseded root copies are retained only in Git
history. The consolidated response document replaces the earlier partial answer set.
[Course handouts](docs/course) are instructor references. Editable diagrams and SVGs
are source/export pairs, not competing specifications.

## Implemented scope

The current complete build has **20 tables, 136 columns, 33 foreign keys, 58 CHECKs,
28 procedures, two functions, four views and two triggers**. This comprises the
original 15 lending tables, two permission tables and three request-workflow tables.
The JSON dictionary and original lending diagram verifier retain the 15-table baseline;
the extension contracts and executable build describe the additional objects.

Implemented operations include account/role/status management, borrower profile saving,
Draft creation/editing/cancellation, and same-connection submission preparation/finish.
The administrator console provides independent sign-in sessions, role and permission
management, membership changes, and audited/versioned workflow Enable/Disable controls.
Request procedures resolve required permissions and allowed transitions from tables.
Business changes and required success audits commit atomically; failures are observed
separately after rollback, with local fallback when database evidence cannot be written.

**Remaining work:** automated assessment, review/approval, funding, activation,
expiration, repayment allocation/completion, delinquency workers, the full lending
API/UI and production encryption coordination. Seeded financial records demonstrate
reports, not executable financial workflows. General failure-role/target attribution
and protected Administrator/Auditor audit-history reads also remain open. The global
policy mutex and single-process sessions are documented scaling boundaries.

## Validation

Run from the repository root:

```bash
python3 -m unittest discover -s tests/entitlements -v
python3 docs/diagrams/tools/validate_erd.py
MYSQLD_BIN=/usr/local/mysql/bin/mysqld MYSQL_CLIENT_BIN=/usr/local/mysql/bin/mysql \
  python3 tests/entitlements/integration.py
```

Current recorded results: nine unit tests; 5,023 design assertions including 57 audit
regressions; 45 midterm and 87 early-workflow checks plus entitlement/workflow SQL,
migration preservation, real authenticated HTTP, concurrent policy edits, runtime
privileges and observability checks. The integration suite starts its own disposable
MySQL server and does not connect to development. Installed **MySQL 26.7.0** passed
the current increment. MySQL **8.4.6** evidence in older milestones belongs to the
previous administration/midterm implementation, not a new test of this increment.
The design-assertion count is artifact consistency evidence, not that many independent
business scenarios. Full financial workflow tests remain outstanding.

## Fresh build and demonstration

Use a privately saved MySQL login path; never put passwords in source or commands.
The small local setup scripts use `/usr/local/mysql/bin/mysql` and login path `cs437`.
For a new empty development database:

```bash
bash build/setup_local.sh
bash build/build_database.sh
```

Setup refuses an existing database. Do not rebuild existing development data.
[manifest.txt](database/manifest.txt) lists the SQL order; the main schema is followed
by functions, permission/workflow definitions, routines, triggers and reference seeds.
The fictional financial fixture is optional and restricted to dedicated demo/test DBs.

For a fresh dedicated presentation database:

```bash
bash build/demo_midterm.sh
```

This refuses an existing `micro_lending_midterm_demo`, builds it, loads the 343-row
historical fixture, runs 45 midterm assertions and demonstrates GRANT/REVOKE. It leaves
the demo database for inspection and never resets development. MYSQL_BIN and
MYSQL_LOGIN_PATH can select another client/private connection for this command.
Fixture protected fields are placeholders and its password markers cannot sign in.

For a narrated Workbench demonstration, use [the numbered SQL walkthrough](tests/sql/midterm_walkthrough.sql)
and [its speaking guide](docs/Midterm_Demo_Guide.md). Run the intentional error blocks
individually. Commands create fresh fictional requests rather than resetting prior runs.
The [workflow guide](docs/Table_Driven_Workflows.md#demonstrate-table-driven-behavior)
explains how to disable an action through stored policy and show that it is rejected.

## Existing databases and administration console

For an existing database at **189ed0f**, back up and stop callers before the one-time
`bash build/upgrade_request_workflow.sh` migration. It preserves business/history rows;
DDL is not atomic, so inspect a partial failure before retrying. Earlier upgrade scripts
are pinned to their historical target commits and must be used in the documented order.
Reapply reviewed [runtime grants](database/entitlements_console_grants.sql) after
routine replacement, adapting database/account names. No development database was
migrated as part of the current follow-up implementation.

Follow [private provisioning and runtime setup](docs/Entitlements.md#run-upgrade-and-test)
to create a fictional administrator password and a narrowly privileged database account.
Start `python3 app/admin_console.py` and open `http://127.0.0.1:8765`. Set MYSQL_BIN,
MYSQL_LOGIN_PATH, ENTITLEMENTS_DATABASE and ENTITLEMENTS_LOG_DIR as needed. The console
binds loopback; HTTPS/public deployment requires the documented deployment review.

Logging/metrics/traces and the proposed Critical/High/Warning alert hierarchy are
specified in [ops/README.md](ops/README.md) and [alerts.json](ops/alerts.json).
Alert delivery is local. The [post-interview review](docs/Post_Interview_Audit.md)
retains historical findings, resolutions and the proposed durable worker design.

## Diagram and source organization

| Editable source | Exports |
| --- | --- |
| [Micro_Lending_ERD.drawio](docs/diagrams/Micro_Lending_ERD.drawio) | Original conceptual, accounts/funding and repayments/oversight SVGs described in the ERD guide |
| [Application_Design.drawio](docs/diagrams/Application_Design.drawio) | Proposed full-system flow and wireframes |
| [Entitlements.drawio](docs/diagrams/Entitlements.drawio) | [Entitlement extension](docs/diagrams/06-entitlements.svg) |
| [Request_Workflow.drawio](docs/diagrams/Request_Workflow.drawio) | [Workflow extension](docs/diagrams/07-request-workflow.svg) |

The initial reviewed design package was imported from the team repository at
[39c00d7](https://github.com/anuvikdas/CS-437-Database-Systems-Implementation/commit/39c00d7558166178393ce3d549aabb4e3f17b724).
Tyler wrote the initial FRD/TDD drafts; both partners revised the October 19 deliverable.
Later responsibility follows the commit history, as detailed in response Q22.
The professor's decision on modular services versus separately deployable microservices
remains open; configurable tables alone do not establish that architecture requirement.
