# Implementation milestones

Updated: October 20, 2026

This file records implementation progress, test evidence, and explanations for
our professor walkthrough. It supplements the existing design documents; it is
not a second copy of the TDD or a change to the requirements.

The TDD and ERD guide remain at their committed design baseline for now. Their
statements about implementation status describe that earlier snapshot. Use this
file for current progress. Proposed updates to those documents are collected
below for later review before incorporating them.

## Milestone 1: Local MySQL environment

Completed locally on October 20, 2026:

- Used the installed MySQL Community Server/client 26.7.0 and MySQL Workbench.
  The TDD's earlier MySQL 8.4.12 candidate has not been tested.
- Created `micro_lending_dev` with `utf8mb4` and
  `utf8mb4_0900_ai_ci` as the default collation.
- Verified InnoDB transaction commit, rollback, and exact decimal storage using
  temporary tables. These environment checks created no permanent tables.
- Confirmed that repeated setup stops with error 1007 rather than replacing an
  existing database.
- Confirmed TLS on the test connection. The macOS server reports
  `lower_case_table_names=2`; use the documented table spelling consistently and
  check portability on the eventual evaluator environment.

The local saved administrator login is used for setup and testing. Application
runtime permissions remain pending. Connection instructions are in the
[README](../README.md#local-mysql-setup).

Files: [database creation](../database/00_create_database.sql),
[environment checks](../database/05_validation/000_environment.sql), and
[setup runner](../build/setup_local.sh).

## Milestone 2: Account tables and SQL walkthrough

Implemented on October 20, 2026: User, Role, and UserRole in
[schema.sql](../database/schema.sql), plus
[four role definitions](../database/04_seed/010_roles.sql).
Run `bash build/build_accounts.sh` once after local database creation. Each table
must be absent; the scripts deliberately do not drop tables or hide existing ones
with `IF NOT EXISTS`. The full tagged build remains a later deliverable.

| SQL feature | What it does here | Why we chose it |
| --- | --- | --- |
| `BIGINT UNSIGNED` | Holds a nonnegative integer identifier | Matches the dictionary and the type of every referencing FK |
| `AUTO_INCREMENT` | Assigns an ID when omitted on insertion | Callers do not have to calculate the next identity; gaps are allowed |
| `PRIMARY KEY` | Identifies one row uniquely | Distinguishes users and separate role-assignment episodes |
| `VARCHAR(n)` | Stores variable-length text with a maximum length | Gives names and codes explicit size limits |
| `NOT NULL` | Requires a value | A user cannot have a missing login or stored credential field |
| `UNIQUE` | Rejects duplicate key values | Prevents duplicate logins/aliases and active role assignments |
| `CHECK` | Rejects rows whose condition is false | Limits status/role codes and keeps revocation fields consistent |
| `FOREIGN KEY` | Requires a referenced parent to exist | Connects memberships to real users and role definitions |
| `ON DELETE/UPDATE RESTRICT` | Rejects parent deletion/key change while referenced | Prevents orphaned memberships and loss of referenced actors |
| `DEFAULT` | Supplies a value when an INSERT omits it | New accounts start Active with RowVersion 0 |
| `UTC_TIMESTAMP(6)` | Supplies server UTC with microsecond precision | Creation/grant defaults do not depend on the client's time zone |
| `COLLATE utf8mb4_0900_bin` | Uses case-sensitive comparison for role/status columns | Keeps exact code capitalization; the earlier login override was removed in Milestone 6 |
| `ENGINE = InnoDB` | Selects the transactional engine for these tables | Supports the foreign keys and rollback used by this project |

The current login rule was changed by user approval in Milestone 6: `Alex` and
`alex` identify the same account. Earlier case-sensitive evidence below is historical.
PublicAlias also uses the database's case-insensitive collation and must be unique.
The TDD/model remain at the earlier baseline pending a later documentation update.

`UserRole` resolves the User–Role many-to-many relationship: a member can have
Borrower and Lender assignments, while many members can hold Borrower. Keeping
Role.Description in Role avoids repeating the definition on each assignment.

The generated `ActiveMarker` implements the one-active-membership rule:

| UserID | RoleCode | Episode | ActiveMarker |
| --- | --- | --- | --- |
| 10 | Borrower | Earlier, revoked | NULL |
| 10 | Borrower | Later, revoked | NULL |
| 10 | Borrower | Current | 1 |

`UNIQUE(UserID,RoleCode,ActiveMarker)` rejects a second `(10,Borrower,1)`.
MySQL permits multiple NULLs in a unique index, preserving both revoked episodes.
The column is computed from RevokedAt and is not written by callers. A simple
`UNIQUE(UserID,RoleCode)` would incorrectly prohibit regranting a revoked role.
See MySQL's [generated-column documentation](https://dev.mysql.com/doc/refman/26.7/en/create-table-generated-columns.html)
and [unique-index NULL behavior](https://dev.mysql.com/doc/refman/26.7/en/show-columns.html).

**Earlier evidence, before Milestone 4:** the original `bash build/test_accounts.sh`
automated runner passed against local MySQL
26.7.0. Positive checks covered default values, distinct case-sensitive logins,
UTC grant defaults even from a +05:00 session, multiple roles/members, and retaining
two revoked grants with one current grant. All 27 negative cases returned the
expected error: duplicate keys, missing fields, blank text, invalid codes,
nonexistent FK parents, duplicate active membership, incomplete/backdated
revocation, referenced-parent deletion, and manual generated-column writes.
The test runner also verified unchanged permanent row counts after rollback.
Its temporary fictional credential placeholders test column constraints only;
they are not valid encrypted emails or password hashes and never remain committed.

**Enforcement still pending:** FKs do not prove that a grantor/revoker is an
Administrator. These tables alone also do not enforce permitted role combinations,
bootstrap-only NULL grantors, live-obligation restrictions, append-only membership
history, immutable aliases, or RowVersion increments. Encryption/hashing, authorized
mutations, audit, and technical runtime grants remain planned. Administrator/root
test access is not evidence of application permissions. This increment partially
covers FR-01/02 and BR-01/02; it does not complete FR-01–04 or SEC-01/06/13/14.

### Additional verification

The live schema was compared with the design model: the 19 documented columns
across these three tables matched their types, order, and nullability; the
generated ActiveMarker behavior and four foreign keys were also checked.
After the tests, permanent row counts were User = 0, Role = 4, and UserRole = 0.
Rolled-back inserts can still consume auto-increment IDs; gaps are expected.

The build and test runners passed Bash syntax checks. The existing design
validator passed as well; its artifact checks are separate from the real MySQL
constraint tests described above.

Current files: [account build runner](../build/build_accounts.sh),
[test runner](../build/test_accounts.sh), and [SQL examples](../database/tests.sql).
Milestone 4 combined the former fixture and positive checks into the SQL examples
and replaced the automated Bash test framework with an explained walkthrough.

## Milestone 3: One schema file

On October 20, 2026, combined the three existing table definitions into
[database/schema.sql](../database/schema.sql) and removed their separate files.
The SQL definitions and explanatory comments are unchanged. User and Role appear
before UserRole so its foreign keys reference tables that already exist.

The account build runner now executes schema.sql, then the separate role seed
script. This is a file-organization change to the existing FR-01/02 and BR-01/02
increment; it adds no tables, business rules, or authorization/audit behavior.
The TDD remains unchanged.

Verification: compared the combined SQL with the original three files to confirm
all definitions were preserved in order, checked the build runner's Bash syntax,
and checked local documentation links. The earlier MySQL constraint results still
describe these unchanged definitions; no database rebuild or MySQL test rerun was
performed for this reorganization. The existing development database is unchanged.

## Milestone 4: Simpler commands and SQL examples

On October 20, 2026, simplified local setup, account building, and testing so the
commands can be explained line by line. This changes how we run and demonstrate
the same partial FR-01/02 and BR-01/02 increment. The schema, constraints, TDD, and
ERD guide are unchanged; no new security or audit behavior was added.

### What changed and why

- The three Bash scripts now contain direct MySQL commands. Removed configuration
  variables, loops, arrays, pipelines, and the custom expected-error function.
- Each script uses the existing local MySQL path and saved `cs437` connection.
  Run from the repository root; different computers may need a different path.
- [tests.sql](../database/tests.sql) contains its own fictional setup, 27 labeled
  invalid statements, valid examples, expected results, and final rollback.
  The old separate fixture and positive-check files were removed.
- Replaced temporary assertion tables with ordinary SELECT output. This makes the
  SQL easier to explain, but a person must compare results with the comments.
  The runner stops on SQL errors; it does not automatically grade query results.
- The invalid statements are commented out for full-file runs. Run them one at a
  time in Workbench as described below. This avoids a Bash error-handling framework
  without removing any of the 27 invalid examples.

These are local learning/demo scripts. The final tagged evaluator build and its
required reproducibility and verification work remain pending.

### Explain the build commands

Run each command from the repository root:

| Command | Purpose | When to run |
| --- | --- | --- |
| `bash build/setup_local.sh` | Creates micro_lending_dev and displays temporary-table transaction examples | Once, before the database exists |
| `bash build/build_accounts.sh` | Creates the three tables, then inserts the four roles | Once, when the database exists but the tables do not |
| `bash build/test_accounts.sh` | Runs the valid SQL walkthrough and displays results | After the tables and roles exist; can repeat after rollback |

The development database already exists and has these tables, so use the test
command now. Repeating setup or build rejects the existing objects; it does not
reset them. A failed build may leave earlier DDL statements applied.

Every MySQL command follows this pattern:

```bash
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/schema.sql
```

| Part | What it means |
| --- | --- |
| `#!/usr/bin/env bash` | Identifies Bash as the script's interpreter when executed directly |
| `# comment` | Explains a shell line; Bash does not execute the comment |
| `set -e` | Stops these straight-line scripts when a command fails |
| `/usr/local/mysql/bin/mysql` | Starts the installed MySQL command-line client |
| `--login-path=cs437` | Reads the connection settings saved privately on this Mac |
| `micro_lending_dev` | Selects our database; omitted for the command that creates it |
| `< database/schema.sql` | The shell sends this file's contents to the MySQL client |

The build runner executes schema.sql before the role inserts because Role must
exist before we insert its rows. Neither script contains a password.

### Explain and run the SQL examples

| SQL used in the walkthrough | Meaning |
| --- | --- |
| `-- comment` | Explains SQL or keeps an example from executing |
| `SET SESSION time_zone` | Changes only this connection's time zone |
| `START TRANSACTION` | Begins a group of changes that we can undo together |
| `INSERT INTO ... VALUES` | Adds the fictional test rows |
| `SET @member = LAST_INSERT_ID()` | Saves the generated user ID in a connection-local variable |
| `X'01'` | One byte of dummy test data; it does not encrypt an email |
| `SELECT ... WHERE` | Displays the rows or values relevant to the example |
| `COUNT(*)` | Counts matching rows |
| `UPDATE ... WHERE` | Changes the specified test grant when demonstrating revocation |
| `JOIN ... ON` | Matches users, assignments, and roles using their keys |
| `ORDER BY` | Makes the displayed order predictable |
| `IS NULL` | Checks for an absent value, such as no revocation date |
| `IN (...)` | Matches any listed value, used to find the test users |
| `UTC_TIMESTAMP(6)` | Supplies current UTC time with microsecond precision |
| `TIMESTAMPDIFF`, `ABS`, and `<= 2` | Check that a new grant's timestamp is within two seconds of UTC; result should be 1 |
| `ROLLBACK` | Undoes test changes since START TRANSACTION; generated ID gaps can remain |
| `COMMIT` in the environment example | Keeps the inserted value in the temporary demonstration table |
| `CREATE/DROP TEMPORARY TABLE` | Creates/removes a connection-local table without changing the application schema |

The account examples never commit their dummy credentials. Each negative test
should be run with fresh Section 1 setup in the same Workbench connection:

1. Select micro_lending_dev as the default schema and run Section 1. If setup
   fails, run ROLLBACK and investigate; do not delete existing users or continue.
2. Run the SQL after the comment prefix for one N01–N27 example in Section 2.
3. Compare the reported MySQL error with the expected code in its comment.
4. Run `ROLLBACK;`, including after the expected error. Repeat setup for the next
   example. Do not run the positive examples between setup and an invalid test.

A constraint error rejects that statement, not necessarily the entire transaction.
That is why the explicit rollback matters during an interactive demonstration.
Running the entire file skips the commented invalid statements, demonstrates the
valid cases, and rolls back at the end. Closing a failed batch connection also
rolls back its uncommitted changes.

### Verification actually performed

- Ran the simplified test runner on local MySQL 26.7.0. Observed four roles,
  Active/0 defaults, distinct demo_member/DEMO_MEMBER logins, UTC check = 1,
  three Borrower episodes with NULL/NULL/1 markers, two active role names, and
  zero remaining test users/memberships after rollback.
- Separately executed all 27 negative examples from the new SQL file with fresh
  setup for each. Every statement returned its documented MySQL error. A temporary
  verification helper checked these results; it is not part of the project scripts.
- Ran the simplified environment SQL: rollback count was 0 and the committed
  temporary-table value was 12.34.
- Ran setup/build against the existing development database: setup stopped with
  error 1007 and build stopped with error 1050. No objects were replaced.
- Permanent counts before and after: User = 0, Role = 4, UserRole = 0.
- Checked Bash syntax, local document links, and unchanged schema/TDD/ERD contents.
  No fresh empty-database rebuild was performed in this simplification step.

## Milestone 5: Simpler schema formatting

Approved and applied on October 20, 2026 after reviewing the proposal. Updated
[schema.sql](../database/schema.sql) using inline primary keys, unnamed constraints,
and fewer comments. The existing schema rules remain unchanged. The build/test
scripts, TDD, ERD, and existing development database were not modified.

### Course requirements versus our project decisions

The course-context summary lists keys, explicit data types and relationships,
3NF, meaningful entities, a weak entity, security, transactions, constraints,
auditing, and reproducible demonstrations. It does not prescribe custom constraint
names, BIGINT identifiers, case-sensitive logins, microsecond precision, or this
particular generated-column implementation. These three tables are only part of
the eventual project; simplifying them cannot establish compliance for the whole
course deliverable. Current instructor directions take precedence.

Our FRD adds project commitments: FR-02 and BR-01 address role assignments and
unique active membership; its entity discussion retains membership episodes;
SEC-07 exposes role history to auditors; BR-22 retains business history; SEC-12
protects private contact data. TDD sections 4.1–4.3 specify the detailed account
columns and the generated-marker implementation. Those are existing design
commitments even where the course allows other solutions.

### Applied changes: Keep all data rules

| Applied edit | Why | Consequence |
| --- | --- | --- |
| Put single-column PRIMARY KEY beside its column | Matches familiar classroom examples | Same uniqueness and required-value behavior |
| Omit NOT NULL on those primary-key columns | A primary key already requires non-null values | No relaxation of nullability |
| Remove explicit constraint names such as uq_user_login and fk_user_role_user | Shortens declarations while retaining UNIQUE, CHECK, and FOREIGN KEY | MySQL assigns names; error messages/metadata names change, so diagnostics should not depend on the old names |
| Reduce repeated comments; keep explanations in Milestones | Makes the table structure easier to scan | No runtime effect |
| Write the short ActiveMarker expression on one line | Less visual clutter | Same generated value and active-membership rule |

Keep ENGINE = InnoDB and explicit ON DELETE/UPDATE RESTRICT so transaction support
and reference protection remain visible. Keep all existing checks, types,
collations, defaults, and columns. This pass makes the file shorter, but does not
remove the need to understand assignment history and ActiveMarker.

### Current SQL and explanation

Read the executable [schema.sql](../database/schema.sql) for the current definitions.
The reviewed proposal is now implemented there; its full SQL is not duplicated in
this document. Milestone 2 still explains the column types and data rules.

Primary-key declarations now appear on the column line; PRIMARY KEY still implies
NOT NULL. UNIQUE, CHECK, and FOREIGN KEY retain their original conditions and
columns, but MySQL now assigns their names on a fresh build. The existing
development tables keep their old names because this change is not a migration.
No changes to authorization, encryption, audit behavior, or requirement coverage
were introduced. This remains the same partial FR-01/02 and BR-01/02 increment.

### Larger changes that are possible, but not part of this first pass

| Candidate | Course-level assessment | Project consequences / recommendation |
| --- | --- | --- |
| BIGINT UNSIGNED identifiers to INT UNSIGNED | Either can demonstrate keys and relationships; our small dataset does not need BIGINT capacity | Change every related FK consistently, including future tables and model metadata; adjust the negative tests using an out-of-range BIGINT literal. Reasonable future design simplification, but not just formatting. |
| DATETIME(6) and UTC_TIMESTAMP(6) to DATETIME and UTC_TIMESTAMP() | Microseconds are not listed as a course requirement | Loses fractional-second precision; update the dictionary/model and review event ordering. Keep UTC behavior; CURRENT_TIMESTAMP alone would introduce session-time-zone dependence. |
| Remove explicit login collation | The course does not prescribe case-sensitive usernames | Changes Alex/alex behavior under the current database default; existing case-distinct users could conflict. Requires an explicit login-policy decision and changed tests. Do not remove role/status collations casually: they enforce code capitalization too. |
| Remove RowVersion | The course summary does not specifically require this column | The TDD uses it for stale-update detection. Review every use and choose another concurrency strategy before dropping it; deletion alone abandons that planned protection. |
| Replace UserRole with a plain (UserID, RoleCode) primary key | A simple junction table can satisfy an M:N modeling exercise | Would not retain repeated role-assignment episodes as currently designed. Retaining history elsewhere would require another design, possibly more code. Do not recommend for this pass. |
| Remove encrypted-email/hash/alias fields or blank-value checks | Shorter SQL does not establish equivalent security or validation | Weakens current project commitments or validation. Keep these fields/checks. Encryption and authorization still need their later implementation. |

The most useful optional follow-up is reviewing INT identifiers and second-level
UTC timestamps. Both could remain compatible with course goals, but would require
coordinated model/design changes. They were not included in this formatting change; the user has asked to keep
the schema rules and TDD unchanged.

### Verification actually performed

On local MySQL 26.7.0, built the original and formatted schemas in two uniquely
named disposable databases with the same utf8mb4_0900_ai_ci database default.
Loaded the four-role seed into each. Compared live MySQL metadata while ignoring
constraint/index names, which are intentionally different:

- All 19 column definitions match, including types, nullability, defaults,
  collations, generated expression, and auto-increment properties.
- All three tables retain the same InnoDB engine and table collation.
- All nine index definitions match by table, uniqueness, and ordered columns.
- All eight CHECK expressions and their enforcement settings match.
- All four foreign keys retain the same column references and RESTRICT actions.

Executed the valid examples from tests.sql against both schemas; their displayed
results match each other and the expected values. Defaults, case-sensitive logins,
UTC grant times, multiple memberships, retained revoked episodes, and rollback
all behaved as expected. Separately executed each of the 27 invalid examples
against the formatted schema with fresh setup; each returned its expected error
code. Both test databases ended with 0 users, 4 roles, and 0 memberships.

Removed both disposable databases after verification. Only read the development
database counts; they remained 0 users, 4 roles, and 0 memberships. No development
tables were rebuilt or migrated. A temporary verification helper outside the
repository performed the comparison; the simple project test workflow is unchanged.
Checked that the build/test files, README, TDD, and ERD contents remained unchanged,
and checked the documentation links and whitespace. No commit or push was made.

## Milestone 6: Case-insensitive usernames, strict role/status codes

Approved and implemented on October 20, 2026. LoginName no longer declares a
binary collation in [schema.sql](../database/schema.sql); it inherits the current
database default, utf8mb4_0900_ai_ci. The existing unique constraint now prevents
usernames differing only by capitalization. A query for DEMO_MEMBER finds the
stored demo_member account. Storage preserves the spelling that was inserted.

This default is also accent-insensitive, so names such as Jose and José compare
equal. This follows the selected database default; only dropping the binary override
would not guarantee the same behavior on a database created with another default.
Our database-creation script explicitly supplies the expected default.

AccountStatus, Role.RoleCode, and UserRole.RoleCode retain utf8mb4_0900_bin.
Incorrect code capitalization is still rejected. The application should supply
canonical values from actions/dropdowns; the database checks provide a final
validation layer. These column changes alone do not implement application sign-in.

### Files and rule impact

- Updated schema.sql for fresh builds, preserving the unique login constraint,
  column size, and required value. All other schema declarations are unchanged.
- Added [alter_username_collation.sql](../database/alter_username_collation.sql)
  for the existing database. It modifies only LoginName's collation without
  dropping tables, deleting users, or changing credentials. It is a separate
  one-time update, not part of the fresh-build runner.
- Updated [tests.sql](../database/tests.sql): P03 now demonstrates a
  case-insensitive lookup; the additional user has the distinct name demo_other.
  New N28 rejects a duplicate login with different capitalization (error 1062).
  All earlier invalid cases remain, including strict status and role capitalization.
- Updated README instructions and these notes. The TDD and ERD guide are unchanged
  as requested. Record the username comparison-policy change in their dictionary
  or model notes during the next approved design-document synchronization.

This is an approved change to the identity comparison policy supporting FR-01 and
BR-01, not a relaxation of username uniqueness. Role assignment, audit, encryption,
and authorization behavior are unchanged.

### Verification actually performed

Checked existing usernames grouped under the new collation before applying the
ALTER; no conflicts existed. Built and seeded the changed schema in a uniquely
named disposable MySQL 26.7.0 database. All valid examples produced the expected
results, including the uppercase lookup, default values, UTC time, retained role
episodes, and rollback. All 28 invalid examples returned their documented errors.
N10 and N13 still reject wrong status/role capitalization, while N28 rejects the
case-variant duplicate username.

Applied the ALTER to micro_lending_dev and confirmed its username/status/role
collations match the fresh build. Ran the valid SQL walkthrough on the development
database as well. Permanent counts remained User = 0, Role = 4, UserRole = 0;
no test records remained. Removed the disposable database after testing.

Checked documentation links and whitespace and verified that the TDD and ERD
contents did not change. No commit or push was made.

## Remaining implementation

The other 12 application tables, full seed data, and final ordered/tagged build
remain pending. Lending workflows, concurrent transactions, business-workflow
rollback, application authorization/encryption integration, and a running API/UI
have not been demonstrated. The professor's architecture feedback remains pending.

## Possible design-document updates for later review

These are notes to consider later, not changes applied to the design documents:

- Record the actual local MySQL version and decide the final supported baseline.
- Update implementation-status statements and acceptance gates with the completed
  three-table increment and its test evidence.
- Record later enforcement decisions and results when they are implemented and
  reviewed. Structural table constraints alone do not complete the security and
  business requirements.

Keep the SQL walkthrough here unless we later decide it belongs in the TDD.
