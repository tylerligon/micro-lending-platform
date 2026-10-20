# Micro-Lending Platform

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
The first three application tables were then created as described below; lending
workflows are still pending.

Connect from Terminal:

```bash
/usr/local/mysql/bin/mysql --login-path=cs437 --database=micro_lending_dev
```

In MySQL Workbench, use host `127.0.0.1`, port `3306`, user `root`, and default
schema `micro_lending_dev`; enter the password through Workbench's own prompt.
To repeat only the temporary-table checks on an existing development database:

```bash
/usr/local/mysql/bin/mysql --login-path=cs437 --database=micro_lending_dev < database/05_validation/000_environment.sql
```

## First three tables

`User`, `Role`, and `UserRole` are implemented and tested on local MySQL 26.7.0.
The four business-role definitions are loaded. No permanent sample users or
memberships have been created yet.

After creating an empty development database, build these tables once:

```bash
bash build/build_accounts.sh
```

Read [schema.sql](database/schema.sql): it creates `User`, `Role`, then
`UserRole`, with comments explaining the design choices. The build runner loads
the [four role definitions](database/04_seed/010_roles.sql) afterward. Existing tables cause an error;
the script never drops or replaces them. DDL is not rolled back as a group, so a
failed build can leave earlier tables in place and must be inspected before retrying.

Run the valid SQL examples on the existing tables:

```bash
bash build/test_accounts.sh
```

The runner executes [tests.sql](database/tests.sql). Read its comments and compare
the displayed query results: four roles, defaults of Active/0, an uppercase login
lookup finding the existing lowercase account, UTC check = 1, two revoked Borrower
episodes plus one active episode,
and zero test rows after rollback. SQL execution errors stop the command;
unexpected query values require you to notice the mismatch.

**Invalid examples are manual:** the 28 statements in Section 2 are commented out.
In Workbench, select `micro_lending_dev` as the default schema. Run Section 1 to
create the test records, stopping if setup reports any error. Select the SQL after
`--` for one invalid example and execute it without the comment prefix. Compare
its error with the expected code, then run `ROLLBACK;` in the same connection.
Repeat Section 1 for each example. Do not run Section 3 during an invalid example.

The examples reserve `demo_member`, `demo_admin`, and `demo_other`;
existing conflicting names cause an error rather than being overwritten. Always
roll back when running selected statements in Workbench, including after errors.
A failed batch command closes its connection and rolls back uncommitted work.
Auto-increment IDs may still have gaps. Dummy email/hash fields are not valid
application credentials.

Verified on October 20, 2026: the simplified valid examples produced the expected
results; each of the 28 invalid examples was separately executed and returned its
expected error. Permanent row counts stayed User = 0, Role = 4, UserRole = 0.
The new runner does not automatically execute or grade the invalid examples.

Usernames now use the database's case-insensitive default: `Alex` and `alex`
identify the same account, and UNIQUE prevents both from being registered separately.
The stored spelling is preserved. Role/status codes retain binary collations and
reject incorrect capitalization. This database default is also accent-insensitive.

Fresh builds use schema.sql. The existing development database was updated once
using [alter_username_collation.sql](database/alter_username_collation.sql), after
checking for conflicting names. Do not rebuild existing tables to apply this change.

For implementation progress and a SQL walkthrough, use
[Milestones](docs/Milestones.md#milestone-2-account-tables-and-sql-walkthrough).
These tables enforce structural rules; administrator authorization, allowed role
combinations, immutable history, encryption/hashing, audit, and runtime grants
still need their planned service/routine implementations.

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
Only the three account tables have real MySQL schema/constraint evidence so far.
The remaining schema, a running API/UI, concurrent lending actions, and
business-workflow rollback remain unverified. The local environment checks above
verify basic database connectivity, decimal storage, commit, and rollback.
The [TDD acceptance gates](docs/Technical_Design_Document.md#101-fixture-and-implementation-acceptance-gates)
identify the remaining implementation work and fixture materialization requirements.

The professor's architecture decision is still pending: whether one deployable
FastAPI service with command/update and query/extraction modules satisfies the
microservices requirement, or separate deployables are needed.
