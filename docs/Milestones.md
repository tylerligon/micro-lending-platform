# Implementation milestones

> **Historical log:** Entries below retain their original dates and scope. The current 20-table implementation and verification are described in [README](../README.md) and [table-driven workflows](Table_Driven_Workflows.md); earlier 15/17-table counts are milestone snapshots.


Updated: October 21, 2026

This file records implementation progress, test evidence, and explanations for
our professor walkthrough. It supplements the existing design documents; it is
not a second copy of the TDD or a change to the requirements.

The TDD and ERD guide remain at their committed design baseline for now. Their
statements about implementation status describe that earlier snapshot. Use this
file for current progress. Proposed updates to those documents are collected
below for later review before incorporating them.

Historical entries retain the filenames used at the time. Links point to current
locations; Milestone 13 describes the consolidated layout.

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
[environment checks](../tests/sql/environment.sql), and
[setup runner](../build/setup_local.sh).

## Milestone 2: Account tables and SQL walkthrough

Implemented on October 20, 2026: User, Role, and UserRole in
[schema.sql](../database/schema.sql), plus
[four role definitions](../database/04_seed/010_reference_data.sql).
Run `bash build/build_database.sh` once after local database creation. Each table
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

**Earlier evidence, before Milestone 4:** the original `bash build/test_database.sh`
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

Current files: [account build runner](../build/build_database.sh),
[test runner](../build/test_database.sh), and [SQL examples](../tests/sql/accounts.sql).
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
- [tests.sql](../tests/sql/accounts.sql) contains its own fictional setup, 27 labeled
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
| `bash build/build_database.sh` | Creates the three tables, then inserts the four roles | Once, when the database exists but the tables do not |
| `bash build/test_database.sh` | Runs the valid SQL walkthrough and displays results | After the tables and roles exist; can repeat after rollback |

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
- Updated [tests.sql](../tests/sql/accounts.sql): P03 now demonstrates a
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

## Milestone 7: BorrowerProfile

Implemented and tested on October 20, 2026. Added BorrowerProfile after UserRole in
[schema.sql](../database/schema.sql), using the existing simple formatting. This
is the table structure for FR-05, with BR-01/BR-05 and SEC-02/SEC-12 context; it is
not completion of the protected profile workflow. The TDD, ERD guide, and model
metadata remain unchanged because the new table follows their existing design.

### Explain each part

| SQL | What it does | Why we chose it |
| --- | --- | --- |
| `CREATE TABLE BorrowerProfile` | Creates the current borrower financial-profile table | Keeps borrower-specific data separate from general account information |
| `UserID BIGINT UNSIGNED PRIMARY KEY` | Identifies the profile using the existing account ID | One profile per account; the PK implies NOT NULL, and no second profile ID or auto-increment is needed |
| `MonthlyIncomeCipher VARBINARY(128) NOT NULL` | Requires up to 128 bytes of encrypted-income data | Matches the design's protected monthly-income envelope; this type does not encrypt anything |
| `ExternalObligationsCipher VARBINARY(128) NOT NULL` | Requires protected monthly obligations outside this platform | Assessment will add platform obligations separately, avoiding double counting |
| `UpdatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6))` | Supplies a UTC timestamp on insertion if omitted | Starts the profile's update timestamp consistently; later updates must explicitly set it |
| `RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0` | Starts a nonnegative version counter at zero | Later controlled writes can compare the expected version and increment it to detect stale edits |
| `FOREIGN KEY (UserID) REFERENCES User (UserID)` | Requires the profile's account to exist | The same column is both PK and FK, expressing a dependent one-to-one relationship |
| `ON DELETE RESTRICT ON UPDATE RESTRICT` | Rejects deleting/changing a referenced account key while its profile exists | Prevents an orphan profile; this alone does not make the profile itself immutable |
| `CHECK (OCTET_LENGTH(...Cipher) > 0)` | Requires at least one byte in each protected field | NOT NULL blocks missing values; these checks also block empty byte strings |
| `ENGINE = InnoDB` | Uses the existing transactional engine | Supports the foreign key and rollback demonstrations |

Each profile belongs to exactly one account; each account can have zero or one
profile. Having a Borrower role does not automatically create a profile, and a
foreign key to User does not prove the account holds Borrower. Current users who
only lend need not have profiles.

For the professor: "BorrowerProfile shares its primary key with User. The foreign
key requires an existing account, and the primary key prevents multiple profiles
for that account. The encrypted fields hold current financial inputs; they are
separate from the submitted snapshot that LoanRequest will retain later."

### Simple SQL examples

Added [borrower_profile_tests.sql](../tests/sql/borrower_profile.sql) using the
same four-section walkthrough as the existing account examples. It creates a
fictional parent and profile inside one transaction, shows a join, verifies the UTC
default from a +05:00 session, and explicitly changes the timestamp and version.
The update includes `WHERE RowVersion = 0`, then displays the affected-row count.
This demonstrates the intended pattern; it is not a protected application update
endpoint. Dummy X'01'/X'02' values demonstrate constraints, not actual encryption.

Ten commented invalid statements demonstrate duplicate profiles, nonexistent
accounts, NULL income/obligations, empty income/obligations, oversized fields, and
deletion or key modification of a referenced account. Oversize checks expect
strict SQL mode, which was verified on the local server. Execute each invalid
example independently with fresh Section 1 setup, compare its documented error,
and ROLLBACK in the same connection.

The [test runner](../build/test_database.sh) now executes the existing account
examples followed by the profile examples using a second direct MySQL command.
The [build runner](../build/build_database.sh) still executes schema.sql followed
by the role seed; its comment now lists all four tables. README describes the
new file and the same manual result-checking process. No new testing framework
was added to the repository.

### Verification actually performed

Built all four tables from schema.sql and loaded the four roles in a uniquely
named disposable local MySQL database. Verified the five profile columns match
the dictionary's order, types, and non-nullability, its two CHECK constraints exist,
and its UserID FK references User.UserID with RESTRICT actions. The original three
table declarations are unchanged from the prior committed schema.

Ran both valid walkthroughs successfully. The profile example showed one joined
row, one byte in each field, RowVersion 0, UTC check = 1, exactly one updated row,
RowVersion 1, and the updated placeholder bytes. Final profile/user demo counts
were zero. Separately executed all 28 account invalid examples and all 10 new
profile invalid examples; each returned its expected error code.

Confirmed BorrowerProfile was absent in micro_lending_dev, then executed only its
CREATE TABLE block there. No existing tables were dropped or recreated. Ran the
combined test runner successfully against the development database. Permanent
counts afterward: User = 0, Role = 4, UserRole = 0, BorrowerProfile = 0. Removed the
disposable database. Checked Bash syntax, documentation links, and whitespace,
and verified the TDD/ERD/model and existing account tests remain unchanged.

### Boundaries and remaining work

The SQL checks only the presence/length of bytes, not whether they form a valid
authenticated encryption envelope or decrypt to legal amounts. The future trusted
service must validate income > 0 and external obligations >= 0 before encryption,
enforce Borrower role/ownership/account-status permissions, and maintain UpdatedAt
and RowVersion. There is no automatic update or audit trigger in this increment.
No real financial data or usable credentials were inserted; no persistent profile
seed was added. No commit or push was made for this milestone yet.

## Milestone 8: Complete table schema

Implemented on October 20, 2026 at the user's request to finish the schema.
[schema.sql](../database/schema.sql) now creates every table in the current design:
**15 tables, 114 columns, 27 foreign keys, and 63 CHECK constraints**. The original
four table bodies remain unchanged. This completes the table-definition stage,
not the application's workflow, security, reporting, trigger, or final-build stages.
The TDD, ERD/model, audit catalogue, and design fixtures were not edited.

### New tables and their purpose

| Table | What one row means | Main structural rules |
| --- | --- | --- |
| LoanRequest | A borrower's request and its submitted input snapshot | User FK, nonblank purpose, principal 100–2000, 3/6 installments, permitted states, complete submission fields, required terminal reason/deadline |
| RequestEvaluation | A retained Submission/Review/Funding check | Request/admin FKs, local attempt identity, condition flags, completion pairing, derived Result, at most one final review |
| OperationReceipt | One caller's identified financial operation | Unique caller/reference across both actions, valid action, optional-until-finalized nonempty response snapshot |
| FundingCommitment | One contribution event | Positive DECIMAL amount, unique receipt/evaluation references, consistent Pending/Applied/Released timestamps; repeated lender/request pairs remain possible |
| Loan | One activated loan from one request | Unique request origin, Active/Repaid with completion pairing, Current/Delinquent observation |
| Installment | One scheduled obligation within a loan | Composite PK (LoanID,InstallmentNumber), positive amount/number, unique due date within the loan; this is the required weak entity |
| Repayment | One posted payment within a loan | Composite PK (LoanID,RepaymentNumber), unique receipt, positive amount/number |
| RepaymentAllocation | Part of a payment assigned to a scheduled installment | Composite PK and two composite FKs sharing LoanID; positive allocated amount |
| OversightNote | One administrative follow-up or correction | Exactly one request/loan target, nonblank text, existing author/corrected-note references |
| AuditEvent | An event or observed failed/denied attempt | Finite catalogue values, valid event/outcome/subject/actor shapes, required reasons, existing recorded actors/receipts |
| AuditChange | One safe changed field attached to an event | Composite event/field key, global field allowlist, NULL values for protected fields, bounded nonblank StatusReason |

Money is DECIMAL(18,2), not floating point. Controlled codes use the same binary
collation style as our existing roles/statuses. All FK actions remain explicit
RESTRICT. Only PK/UNIQUE/FK-supporting indexes are present; the TDD's workload
indexes remain candidates for later measured reporting work.

### Explain the additional SQL patterns

| Pattern | Explanation |
| --- | --- |
| `BETWEEN 100.00 AND 2000.00` | Includes both boundary values |
| `PRIMARY KEY (LoanID, InstallmentNumber)` | The combination identifies one installment; number 1 can appear on different loans |
| `FOREIGN KEY (LoanID, RepaymentNumber)` | Checks both values against the same parent row, preserving the payment's loan identity |
| `CASE ... END` in generated Result | Returns NULL for an incomplete check, Pass when both flags pass, otherwise Fail; callers cannot assign Result themselves |
| FinalReviewMarker + UNIQUE | The same NULL-marker technique used by UserRole: many nonfinal attempts, at most one final decision |
| `IS NULL` / `IS NOT NULL` in conditional checks | Requires related fields together and prevents a NULL value from bypassing a required-field condition |
| `A AND B` / `A OR B` | Requires both conditions or permits alternative complete shapes, e.g. the three commitment states |
| `TEXT` | Stores the note body; a separate CHECK rejects empty/space-only notes |
| `BINARY(16)` | Holds a fixed-length context identifier; the future service must generate/validate UUID bytes |
| `MEDIUMBLOB` | Stores an opaque operation-response snapshot for exact retry replay; normalized financial facts remain in event tables |

Audit catalogue checks are longer because the existing design enumerates specific
permitted events, subjects, actors, and reasons. They are ordinary CHECK conditions,
not a second authorization system. The source sets are in audit-catalogue.json.
The global AuditChange field list is enforced here; matching the field to its
particular parent event needs the future append routine.

### Files and commands

- Extended schema.sql in dependency order, without changing the four earlier table
  bodies or splitting the table definitions into multiple SQL files.
- Added [schema_tests.sql](../tests/sql/schema.sql): readable fictional setup,
  71 commented invalid examples S01–S71, valid query examples, and final ROLLBACK.
- Added [010_schema.sql](../database/05_validation/010_object_validation.sql): displays expected
  table/column/FK/CHECK counts, engines, and username/code collations. These SELECTs
  are for inspection, not an automatic assertion framework.
- Renamed build_accounts.sh to [build_database.sh](../build/build_database.sh) and
  test_accounts.sh to [test_database.sh](../build/test_database.sh) to reflect their
  full-database scope. Earlier command/file references in this document now use the
  current names. The scripts remain straight-line MySQL commands.
- The build runs schema, role seed, and structural overview. The test runner runs
  the overview, account examples, profile examples, then the full-schema examples.
  All invalid statements stay commented for individual Workbench execution.
- Updated README instructions. The old fixture materializer and other Python design
  tools were not changed; no new Python testing framework was added to the project.

The new SQL walkthrough is structural test setup, not execution of the eventual
business procedures. Its deliberately supplied IDs/timestamps, dummy encrypted
fields, and direct inserts are available to the local setup/test identity; they
must not become trusted application input paths. Full-file execution rolls back
all rows; auto-increment gaps can remain.

### Verification actually performed

On local MySQL 26.7.0, built and seeded a fresh disposable database successfully.
Compared all 114 live columns with the design model by table, order, type, and
nullability. Compared all primary/unique keys and all 27 FK mappings/actions.
Confirmed 63 enforced CHECK declarations. Existing case-insensitive username
policy is preserved; role/status codes remain strict.

Ran the three valid walkthroughs and inspected expected outputs: accounts/history,
profile defaults/update, multiple requests per borrower, repeated contributions,
pending and completed evaluation results, one final and multiple nonfinal reviews,
repeated installment numbers on separate loans, allocated totals, redacted changed
fields, and zero retained demonstration rows. Executed all **109 invalid cases**
separately with fresh setup: 28 account, 10 profile, and 71 full-schema examples.
Each returned its documented MySQL error, rather than an unrelated connection error.
Temporary verification helpers outside the repository checked these results.

In a separate disposable database, loaded all **343 rows** described by the existing
fictional design fixture in its dependency order. Protected data/password directives
were replaced with explicitly marked constraint-test placeholders, not usable
cryptographic values. All per-table counts and expected generated Result/marker
values matched. This establishes structural fixture compatibility, not actual
cryptography, an application sign-in path, or a safe persistent seed release.

Only the 11 missing CREATE TABLE statements were applied to micro_lending_dev.
The original four tables and their rows were not dropped or rebuilt. The combined
SQL test runner succeeds there. Final persistent counts: Role = 4, every other
table = 0. Test databases were removed afterward. The structural overview, Bash
syntax, documentation links/whitespace, and existing design validator were checked.
The design validator is artifact evidence, separate from the MySQL execution above.

### What the completed schema does not enforce yet

| Schema already enforces | Remaining controlled-workflow responsibility |
| --- | --- |
| Snapshot fields present for submitted states | Freeze terms/snapshots after submission; atomically create the Submission evaluation |
| Valid flags, derived result, one final review | Calculate real eligibility, lock current exposure, bind actor/current role and matching evaluation/request |
| Unique operation reference and event references | Exactly one matching financial event and finalized response per receipt at commit; resolve exact retries |
| Positive contributions and one loan per request | Self-funding prevention, capacity/deadline checks under locks, funding total, loan/schedule activation atomically |
| Positive allocations and same-loan parent keys | Oldest-first allocation, per-installment caps, sum = payment, no overpayment, once-only loan completion |
| Valid note target and existing correction parent | Administrator authority, earlier same-target correction, append-only protection |
| Audit catalogue shapes and basic private-field redaction | Trusted session identity, historical roles, subject-key grammar/binding, event-specific fields/required changes, immutable audit storage and authorized projections |
| Byte fields, defaults and version counters | Real encryption/hashing, plaintext range validation, automatic controlled timestamp/version maintenance, ownership checks |

No new business procedures, triggers, views/reports, technical grants, safe full
seed, final tagged build, API/UI, or concurrency tests were implemented in this
schema-completion step. Follow the existing TDD for those next stages. No commit
or push was made for this milestone.

## Milestone 9: Simpler named audit checks

Approved and applied on October 20, 2026. Implemented the reviewed proposal in
[schema.sql](../database/schema.sql). Grouped repeated actor requirements, replaced
long event/outcome and event/subject alternatives with CASE mappings, combined the
three identical administrator-reason checks, and named the complex rules.
**The rules remain the same.** There are now 61 CHECK declarations rather than 63
because three administrator-reason declarations became one equivalent declaration.
The full reviewed SQL is implemented in schema.sql rather than duplicated here.

### Named checks and explanations

| Name | What it enforces |
| --- | --- |
| chk_audit_event_outcome | AttemptRejected requires Denied, TransactionFailed requires Failed, InterruptionObserved requires Interrupted; other permitted events require Success |
| chk_audit_event_subject | Selects the same required subject type for each permitted event |
| chk_audit_actor | Groups shared human fields and role rules, Bootstrap, service-name/initiator rules, and the three failure actor shapes |
| chk_audit_admin_reason | AccountStatusChanged, ReviewApproved, and ReviewRejected require ADMIN_DECISION |
| chk_audit_expiration_reason | RequestExpired requires WORKER_EXPIRED |
| chk_audit_failure_reason | Unsuccessful outcomes require a reason |
| chk_audit_private_values | Protected AuditChange fields require NULL OldValue and NewValue |
| chk_audit_status_reason | StatusReason has NULL old value and a present, nonblank, trimmed new value |

`CONSTRAINT name CHECK (...)` names the rule MySQL evaluates. Naming helps explain
and locate a failure; it does not authorize the caller. CASE selects an expected
value instead of repeating the same comparisons in several OR branches.

The human branch now writes its common ActorUserID/ActingRoleCode presence and
ServiceActor/InitiatingUserID absence once, then groups events by role. The service
branch maps event to service name and keeps the required initiating user on the
same three events as before. Failure services use an IN list. The redundant
Delinquency alternative is removed because the existing broader branch already
allowed both NULL and non-NULL initiating users.

The actor check remains detailed because the current design has different valid
cases. Explicit IS NOT NULL guards are preserved. A CHECK accepts UNKNOWN as well
as TRUE, so removing those guards could change acceptance. The existing event/code
allowlists remain: CASE ELSE branches do not permit arbitrary new events.
Bootstrap still requires a trusted fresh-build path at runtime; merely storing
its service name is not proof of authority.

### What did not change

No columns, types, defaults, collations, generated expressions, PKs, unique keys,
FKs, RESTRICT actions, allowed-value lists, or nonblank conditions were changed.
AuditChange redaction/StatusReason expressions were only named and reformatted.
No rule was moved into a future procedure. The TDD, ERD/model, audit catalogue,
and the existing SQL walkthrough files were not modified.

This is a refactor of the existing FR-28 / BR-22 / SEC-08/11/12 structural controls.
Authorization, trusted audit identity, historical role/subject binding, event-specific
changed-field rules, append-only protection, grants, and other pending workflows
remain pending. Preserving this schema behavior does not establish that the whole
project's security or course deliverables are complete.

### Verification actually performed

Built the original and refactored full schemas, each with the four roles, in two
uniquely named disposable MySQL databases. Compared every column/default/collation,
table engine, index and foreign key; they match. All 15 tables, 114 columns and 27
FKs remain. The check count changed only by the planned consolidation.

Evaluated the old and new predicates in MySQL and compared CHECK acceptance
(TRUE or UNKNOWN, versus rejected FALSE), including incorrect codes and NULL fields:

| Predicate group | Compared cases | Acceptance differences |
| --- | ---: | ---: |
| Event / actor presence / role / service / initiator presence | 7,700 | 0 |
| Event / outcome | 150 | 0 |
| Event / subject type | 300 | 0 |
| Event / outcome / reason | 5,100 | 0 |
| AuditChange field / old value / new value | 784 | 0 |
| Total | 14,034 | 0 |

The actor cases cover all 23 permitted event names, unrecognized/miscapitalized
names, all four roles plus NULL/incorrect values, all eight service names plus
NULL/incorrect values, and present/absent user identifiers. IDs were representative
values because these particular predicates only test their presence. The mapping
and reason comparisons retain the original domain guards; the schema's NOT NULL
and FK declarations are unchanged. These are bounded equivalence comparisons,
not application authentication or concurrent transaction tests.

Ran all three valid walkthroughs on both schemas and compared their displayed
outputs: identical. Executed all 109 invalid examples against both schemas; each
returned the same documented error code. Additional real inserts/updates targeting
each of the eight named checks returned error 3819 containing its new constraint
name. All those test rows were rolled back.

Loaded the 343-row fictional structural fixture on both schemas. Counts and
generated values match. As in Milestone 8, protected values/passwords were explicit
constraint-test placeholders, not real ciphertext or usable credentials. No new
cryptographic behavior is claimed. Both disposable databases were removed.

### Existing development database and files

Applied ALTER TABLE to the two development audit tables, replacing only the eight
old complex AuditEvent checks with six named equivalents and the two AuditChange
checks with their named equivalents. Each table's drops/additions were in one
ALTER statement. Constraint identities were matched against the old definitions
before replacement; no table was dropped/recreated and no data rows were changed.
All 61 current CHECKs are enforced. Persistent row counts remain Role = 4 and zero
in every other table.

Updated the expected count in [010_schema.sql](../database/05_validation/010_object_validation.sql)
and README. The standard [test runner](../build/test_database.sh), Bash syntax,
document links/whitespace, and design validator were checked. The temporary MySQL
comparison helpers are outside the repository; the project's simple test workflow
is unchanged. Earlier Milestone 8 counts/results describe the prior schema version.
No commit or push was made for this refactor.

## Milestone 10: Basic schema checks

Approved and implemented after the user asked to reduce the number and complexity
of checks. This supersedes the preserve-every-rule scope of Milestone 9. It is a
behavior change, not another equivalent rewrite. schema.sql is now 394 lines
rather than 506, with **52 CHECKs instead of 61**. There are still 15 tables,
114 columns, and 27 FKs. Column types, defaults, generated values, primary/unique
keys, foreign keys, and their RESTRICT actions are unchanged.

### What we kept

Keys and required columns, permitted status/kind/action codes, financial bounds,
positive funding/payment/allocation amounts, nonblank required descriptions,
role grant/revocation consistency, profile byte presence, commitment state/time
consistency, loan completion pairing, and note target checks remain.

The generated evaluation Result, one-final-review marker/unique key, and rejection
of Approve when Result is not Pass remain. The audit tables still restrict code
values, require nonblank technical account/subject, require reasons on unsuccessful
outcomes, preserve parent references, and redact protected old/new values.
AuditChange's field allowlist and protected StatusReason validation remain.

### Exactly what changed

| Table | Old CHECKs removed | Simpler checks / remaining responsibility |
| --- | --- | --- |
| LoanRequest | Complete submission snapshot/state combination; required deadlines for funding states; required terminal reasons | Added a simple NULL-or-D1 policy-code check. Optional terminal reasons still cannot be blank. The future submit/cancel/expire/review operations must provide the required timestamps, snapshots, deadlines and reasons. |
| RequestEvaluation | Kind-specific completion/affordability pairing; reviewer-present-exactly-for-Review rule; complete decision/reason/time combination | Added a simple completion-time-not-before-evaluation check. Flag domains, attempt rules, decision code values and Approve-requires-Pass remain. The future review/assessment operations must bind the reviewer and require complete, kind-appropriate decision/completion fields. |
| AuditEvent | chk_audit_event_outcome, chk_audit_event_subject, chk_audit_actor, chk_audit_admin_reason, chk_audit_expiration_reason | Basic allowed-value lists and unsuccessful-outcome reason presence remain. The future trusted audit operation must validate event/outcome/subject/actor/service combinations and event-specific reasons. |

Five audit checks and six request/evaluation combination checks were removed;
two small domain/date checks were added, for nine fewer declarations overall.
Some of the 52 remaining checks have short OR expressions for nullable fields or
simple state consistency. The goal is readable, useful integrity rules, not
reaching an arbitrary check count by deleting protections.

For example, the former long request snapshot expression is no longer a table
requirement. A Submitted row missing its submitted financial inputs can now be
inserted by a direct SQL writer. A future SubmitRequest operation must reject
that condition. Similarly, the audit table permits individually valid codes that
do not belong together, such as ProfileSaved with subject Loan. That matching is
now the future audit writer's responsibility.

The removed rules are not already enforced elsewhere. No procedure or application
was added during this step. The system is therefore not ready to accept protected
business actions directly through table writes. FR-07/09/28 and related security
rules are not complete merely because the schema builds. Preserve the course's
required auditing, authorization, transactions, and valid/invalid demonstrations
when implementing the controlled operations.

### Tests now describe the current behavior

The 28 account and 10 profile invalid examples remain unchanged. Of the 71
full-schema examples, 59 still reject. The other 12 were retained as W01–W12 in
[schema_tests.sql](../tests/sql/schema.sql), under an explicit deferred-rule
section. Original S IDs are noted, and retained S IDs are not renumbered, so
historical evidence can be traced. W examples are commented out during normal
full-file runs, just like the individually demonstrated rejection cases.

| New example | Former example | Table-level behavior now permitted |
| --- | --- | --- |
| W01 | S07 | Submitted request missing income snapshot |
| W02 | S08 | Empty submitted obligations bytes |
| W03 | S10 | Funded request missing deadline |
| W04 | S11 | Cancelled request missing reason |
| W05 | S18 | Funding evaluation without completion time |
| W06 | S20 | Review without recorded administrator |
| W07 | S21 | Administrator recorded on a non-review evaluation |
| W08 | S23 | Decision missing its reason |
| W09 | S60 | Audit subject not matching event |
| W10 | S61 | Audit outcome not matching event, with otherwise permitted codes/reason |
| W11 | S62 | Audit acting role not matching event |
| W12 | S63 | Successful human event without recorded actor |

These are examples of deferred validation, not a list of permitted application
actions. Other consequences of removing the same compound rules also need future
workflow validation: e.g. only completed Review evaluations may carry final human
decisions, and DecidedAt must agree with completion. The table still rejects an
Approve whose generated result is not Pass.

### Verification actually performed

Built old and simplified schemas in separate disposable local MySQL databases.
Both have identical columns/defaults/collations, indexes and FK definitions. The
simplified schema has 52 enforced CHECKs. All three valid SQL walkthroughs produced
the same output on both schemas. All **97 retained negative examples** returned
their expected error on both schemas; this includes positive-money limits, code
validation, key/reference integrity, approval-on-failed-result rejection and private
audit-value protection.

Executed all 12 W cases independently: each fails under the prior schema and
succeeds under the new one, affecting one row before rollback. This confirms the
intentional relaxation instead of claiming unchanged behavior. No test rows were
retained.

The existing 343-row fictional structural fixture loads on both schemas with
matching counts. Protected values/passwords remain test placeholders. Rehearsed
the ALTER TABLE changes against the disposable database containing that fixture;
all rows were preserved and the resulting check expressions matched a fresh build.
Only after those checks passed were the ALTER statements applied to LoanRequest,
RequestEvaluation and AuditEvent in micro_lending_dev. No table was dropped and
no columns or data rows were changed. Both test databases were removed.

Updated the schema overview to expect 52 checks and README to document 97 rejection
cases plus 12 deferred examples. Ran the normal SQL walkthrough runner, Bash syntax,
document-link/whitespace checks, and existing design-artifact validator. Persistent
development counts remain Role = 4 and every other table = 0.

The TDD, ERD/model, and audit catalogue remain unchanged as requested. They describe
the more detailed target design; this milestone records which validations are
currently deferred. No new course compliance or workflow-security completion is
claimed. No commit or push was made.

## Milestone 11: First stored procedure

### Business behavior and scope

Implemented `sp_create_loan_request` in
`database/02_programmability/010_create_loan_request.sql`. This is the creation
portion of FR-06 and a partial demonstration of AC-03. The amount/term limits come
from the approved D1 assumptions (AS-03). Multiple Drafts for the same borrower
remain permitted under BR-04. Successful writes carry the RequestSaved audit
specified by the existing catalogue. No schema rules or design documents changed. During this work an accidental
undo briefly reduced schema.sql to three tables; restored the exact approved
15-table version, including case-insensitive usernames, before final verification.

### SQL walkthrough for explaining the code

1. `DELIMITER //` lets the MySQL client read the procedure's internal semicolons
   without ending CREATE PROCEDURE early; `DELIMITER ;` restores normal input.
2. Four `IN` parameters supply the borrower, purpose, amount, and installment count.
   Local `DECLARE` variables hold the checked account/role/profile and new IDs.
3. `SQL SECURITY INVOKER` uses the caller's privileges instead of granting the
   procedure creator's privileges to whoever calls it.
4. An EXIT HANDLER catches SQL exceptions. `ROLLBACK` undoes this transaction and
   `RESIGNAL` returns the original error to the caller, rather than hiding it.
5. `START TRANSACTION` groups the request and audit writes into one action.
6. `IF` and `SIGNAL SQLSTATE '45000'` reject missing/invalid input with readable
   messages (MySQL error 1644). Principal is inclusive $100–$2,000 and term is 3/6.
7. Three SELECT INTO queries verify an Active account, current Borrower assignment,
   and profile. Variables start NULL, so a missing row leads to an explicit error.
   `FOR UPDATE` locks the relevant rows until commit/rollback, preventing those
   eligibility records from changing midway through this action. This is not a
   claim that all concurrent lending workflows have been implemented or tested.
8. INSERT creates one LoanRequest, trims surrounding spaces from Purpose, and uses
   the schema defaults Draft and RowVersion 0. Submission fields stay NULL.
9. `LAST_INSERT_ID()` captures the new request's ID in this connection. A separate
   call captures the AuditEvent ID after inserting that row.
10. AuditEvent records RequestSaved/Success, the borrower, Borrower role, database
    session account, request ID, and a generated binary UUID context. Four
    AuditChange rows record the new Purpose, Principal, InstallmentCount and
    RequestState, each with NULL old value because the request is new.
11. `COMMIT` saves all those writes together. The final SELECT returns the request
    ID, Draft state, and initial version. No financial inputs are copied or
    decrypted during Draft creation.

The procedure owns its transaction. MySQL does not provide nested transactions:
call it outside an existing transaction, and do not expect an outer ROLLBACK to
undo a successful CALL. This is why its tests use a separate disposable database.

### Files and demonstration

- `build/build_database.sh` installs the procedure after the fresh table schema.
- `build/test_create_loan_request.sh` uses simple MySQL commands to create a
  dedicated test database, load schema/roles/procedure, run the SQL walkthrough,
  and drop that database. CREATE refuses an existing test database; failures stop
  the script and leave it for inspection. It never drops micro_lending_dev.
- `tests/sql/create_loan_request.sql` contains fictional setup, three valid calls,
  expected SELECT output, 17 commented invalid calls, and a commented test-only
  trigger demonstration that forces an audit error. It is explicitly tied to
  micro_lending_procedure_test. Placeholder credentials/cipher bytes are not real
  application credentials or encryption evidence.
- README explains installation, example CALL, transaction ownership, test commands,
  and security/validation boundaries. TDD and ERD remain unchanged.

### Verification actually performed

On local MySQL 26.7.0, loaded the schema, role seed and procedure into a disposable
verification database. All 17 invalid calls returned error 1644 with the intended
message and unchanged table counts: NULL/nonexistent borrower, Restricted/Inactive
account, missing/revoked Borrower role, missing profile, NULL/blank/oversize purpose,
NULL/below/above/zero/negative principal, and NULL/unsupported installment count.

Three valid calls returned new IDs with Draft/version 0. Verified trimmed purpose,
$100 and $2,000 inclusive boundaries, both terms, NULL submission fields, three
matching RequestSaved events, and 12 field changes. SQL SECURITY is INVOKER.

Created a test-only BEFORE INSERT trigger on AuditChange that raises an error.
The CALL failed after the request and AuditEvent inserts; the same connection
still saw only the earlier 3 requests, 3 events and 12 changes. An additional
COMMIT retained no partial writes. This verifies the procedure's explicit rollback
handler rather than relying on connection closure. Removed trigger and test DB.

Ran the committed simple procedure runner successfully and compared its output;
it removed its dedicated test database. Ran the existing table walkthrough runner
successfully (15 tables, 114 columns, 27 FKs, 52 checks; no retained walkthrough
rows). Installed the tested procedure into micro_lending_dev without replacing any
existing routine. Verified every table's row count unchanged: Role = 4, all others
= 0. Checked Bash syntax and Git whitespace. No commit or push made.

### Remaining boundaries

A supplied BorrowerID is not proof of authenticated identity. A future trusted
caller must derive it from the session and enforce record ownership; runtime
grants still need implementation. Root remains a local setup/demo account.
Successful Draft creation is audited atomically, but rejected attempts are not
persisted by this procedure. Failure auditing and append-only protection remain
pending, as do editing, submission snapshots, assessment and later workflows.
DECIMAL(18,2) coerces/rounds fractional cents before procedure validation; explicit
fractional-cent rejection at the trusted input boundary remains pending. These
limits mean FR-06, AC-03 and the overall security/audit requirements are not fully
complete. No encryption, authentication, full concurrency or performance result
is claimed by these tests.

## Milestone 12: Account, profile, Draft editing, and submission

Implemented the SQL portion of the next three planned steps on October 20, 2026.
The approved table definitions, TDD, ERD and model are unchanged. This milestone
records implementation choices and remaining integration work instead of editing
the TDD. No new application backend, Python runtime, or UI was added.

### Requirements and implemented operations

| Requirements | SQL operation | Rules enforced |
| --- | --- | --- |
| FR-01; BR-01/05 | sp_create_user | Active Administrator, nonblank bounded identity fields, encrypted email/hash presence, unique case-insensitive login and alias |
| FR-02; BR-01/03 | sp_set_role | Active Administrator, canonical roles, Borrower/Lender coexistence, separate oversight roles, new row on regrant, retained revocations, live-participation protection |
| FR-03; BR-03/23 | sp_set_account_status | Active Administrator, expected user version, canonical status, nonblank reason, no deactivation with live participation |
| FR-05; BR-03/05 | sp_save_profile | Borrower entitlement, Active or Restricted, positive income, nonnegative external obligations, cents precision, encrypted envelope presence/size, expected profile version |
| FR-06; BR-03/05 | sp_update_loan_request | Active Borrower, owned Draft, current request version, bounded purpose, principal $100–$2,000, term 3/6 |
| FR-07; BR-04/06/07/23/24 | sp_prepare_submission + sp_submit_request | Borrower serialization, owned Draft/profile, version checks, current SQL-derived combined burden and delinquency, frozen D1 inputs/time, incomplete Submission evaluation, atomic audit |

These provide partial evidence toward AC-01/02/03/20/29. They do not complete those
acceptance criteria: sign-in, service authorization/encryption integration, later
assessment/funding/payment operations and end-to-end acceptance remain pending.
Role/account changes take effect on the next routine call; routines re-read current
entitlements. A supplied user ID is still not authenticated identity.

### Keep the code explainable

- `005_workflow_helpers.sql` holds repeated checks: fn_money, ordered account locks,
  entitlement checks, live-participation checks, narrowly scoped success auditing,
  and current exposure calculation. Helpers do not own or commit transactions.
- `010_create_loan_request.sql` keeps the original creation behavior, but monetary
  input is now TEXT and passed through fn_money before conversion to DECIMAL(18,2).
  This fixes the earlier fractional-cent rounding gap. Normal numeric CALL examples
  still work, but a future service must bind original canonical decimal strings,
  rather than pre-rounding them. fn_money accepts 1–16 integer digits and an optional
  one/two-digit fractional part; rejects negatives, signs, exponent notation,
  nonnumeric text, missing values and excess precision. Zero is permitted by the
  helper; each action applies its own positive/range rule.
- `020_accounts.sql` implements create user, grant/revoke role and change status.
  Administrator and affected User rows lock in ascending UserID order. Changes to
  role membership increment the affected User.RowVersion, so status forms with an
  old version cannot overwrite an intervening role/account change. Regrant inserts
  a fresh UserRole episode. Revocation is audited before the Administrator can lose
  their own role; RevokedAt is later than the audit's event time.
- `030_profile_and_draft.sql` implements profile creation/update and Draft editing.
  NULL expected profile version means create; an existing profile requires its
  current version. Creation starts at 0, updates increment it. Restricted borrowers
  can maintain profiles but cannot edit/create/submit requests. Plain financial
  parameters are transient validation inputs; only encrypted bytes are persisted.
- `v_installment_remaining` groups allocation amounts per loan/installment before
  joining them to schedules. Exposure adds the maximum remaining installment per
  Active loan and largest proposed installment per other live request. The largest
  proposed installment includes the last-installment cent remainder. Funded
  requests are excluded so conversion to a Loan is not counted twice. Delinquency
  uses actual unpaid due dates at the snapshot time, not a stale stored condition.
  This relies on future activation/repayment operations producing valid schedules
  and allocations; it does not implement those operations.
- `040_submission.sql` implements the two-call protocol and one narrow update guard.
  The guard protects request identity and freezes terms and input snapshots after
  Draft, including changes to purpose capitalization. It permits later mutable
  lifecycle/deadline/reason/version fields; their complete transition rules still
  belong to later controlled actions. This guard is not the planned repayment
  trigger that performs the course-required related-record update.

### Why submission has prepare and finish

A simple copy of profile ciphertext is incompatible with the approved encryption
contract: a profile field is authenticated to UserID, while a submitted field is
authenticated to RequestID. The database must not store the encryption key.

1. `sp_prepare_submission` starts a READ COMMITTED transaction and locks the Borrower
   User, active role, profile and request. The User is the serialization point for
   multiple submissions. It checks ownership, Draft state and version, then captures
   UTC business time and calculates combined platform burden/delinquency in SQL.
2. It generates a ContextID and remembers source versions/digests/time/results in
   connection-local `@ml_submit_...` variables. It returns current profile envelopes,
   versions, uppercase ContextHex, snapshot time, burden and delinquency. A named
   SAVEPOINT stays alive inside the transaction. No table or column was added.
3. The future trusted coordinator authenticates/decrypts the returned envelopes,
   validates their numeric values, and encrypts fresh input snapshots bound to the
   request and burden bound to RequestID/Submission/ContextHex. The same reserved
   connection and locks remain held. Never wait for user input or remote work here.
4. `sp_submit_request` requires the matching prepared actor/request/context. Releasing
   the named savepoint verifies an intervening COMMIT/ROLLBACK has not ended the
   transaction. It verifies source versions/digests, validates transient income and
   obligation values plus envelope sizes, and writes Submitted/D1, frozen input
   bytes and submission time, and an attempt-0 Submission evaluation. SQL supplies
   NoDelinquencyPass. AffordabilityPass, Result and CompletedAt remain NULL because
   this is submission, not assessment or approval.
5. The RequestSubmitted audit includes state/policy/time/evaluation reference and
   redacted field names. COMMIT saves all records together; context is cleared.
   SQL errors roll back all records and clear context. A coordinator-side failure
   must issue ROLLBACK and clear context or discard the connection. All future
   writers affecting exposure must obey the same borrower lock protocol.

Other public actions own one READ COMMITTED transaction per CALL. Their EXIT
HANDLER performs ROLLBACK and RESIGNAL; successful changes and audits commit
atomically. Call them outside an existing transaction. Internal helpers are not
public business entrypoints; do not expose them or connection variables to clients.

### Audit and security boundary

All implemented successful writes create matching human success events. Private
fields record field names with NULL old/new values. User creation does not put
password hashes or email bytes in AuditChange. Status changes require a trimmed
StatusReason and ADMIN_DECISION. Draft edits retain prior/new terms. No plaintext
financial values or protected ciphertext are placed in the audit feed.

SQL cannot prove that caller-supplied plaintext or encrypted envelopes are authentic
or correspond to each other without the trusted cryptographic coordinator. These
routines are not callable by untrusted users in a finished application. Authentication,
record-level API authorization, least-privilege technical grants, production envelope
handling/key management, separate failure/denial audits and append-only audit guards
remain pending. INVOKER routines use the caller's privileges, not root's authority
through a definer. Root is still used only for local setup/test demonstrations.
No claim of full FR-04/27/28, SEC compliance or AC-03 completion is made.

### Build, upgrade and tests

- Fresh build installs helpers, original creation, accounts, profile/Draft operations,
  and submission in order. Role seed loading and table validation remain separate.
- `build/upgrade_early_workflows.sh` is a one-time upgrade from commit 947ad55. It
  preserves tables/data, creates new helpers first, replaces only the old Draft
  procedure to fix money precision, and installs the new operations. DDL is not
  atomic: stop and inspect partial failures. An ordinary repeated run fails at
  existing helpers before dropping/replacing the Draft routine.
- `build/test_early_workflows.sh` creates ONLY micro_lending_workflow_test, loads the
  objects and role seed, runs `tests/sql/early_workflows.sql`, then drops the DB
  on success. Existing test DB causes failure; a later failure leaves it for review.
  Tests assert values and expected errors instead of only printing query output.
- `tests/sql/submission_concurrency.sql` supplies the manual two-connection
  sequence in a dedicated test DB. Its setup/sections must be selected individually.
- The original Draft test runner now loads its money helper. Schema overview counts
  base tables/columns separately from the new view, and reports routine/view/trigger
  counts after the full build: 15 tables/114 columns/27 FKs/52 CHECKs, 14 procedures,
  one function, one view and one trigger.
- Six old frozen-field negative examples (S01–S04/S09/S12) now report error 1644 from
  the trigger before the old CHECK/FK error. W01/W02 also now reject with 1644.
  Their comments describe both schema-only and full-workflow behavior. W03–W12 remain
  deferred at direct-table level. This strengthens behavior without adding CHECKs.

### Verification actually performed

The automatic SQL workflow suite passed **86 checks**, including **58 expected
rejections**. Covered identity/duplicate validation, role conflicts and histories,
missing authority, account states, live requests/pending commitments/applied lender
participation, profile/Draft versions, precision/ranges, ownership, frozen snapshots,
wrong or missing preparation, lost transaction, private audit redaction, due-today
versus overdue, and multiple-request/loan exposure. Forced audit errors verify
rollback for create user, role grant, status change, profile save, Draft editing and
submission. Same-connection queries verify unchanged business versions/values and
no retained success audit; failed submission leaves no evaluation or state change.
Fictional pending/applied loan fixtures are structural test setup, not proof of
implemented funding, assessment or repayment workflows.

Separately ran two real MySQL connections: the first preparation held the borrower
lock; the second waited. After the first committed, the second returned burden
$400 rather than $0 and both submissions completed once. Their later assessment
is intentionally not implemented here.

A temporary local verification coordinator exercised the approved AES-256-GCM ML1
format with a random in-memory key: authenticated profile decryption, fresh request-
bound input envelopes, and a context-bound encrypted $800 combined burden were
stored, retrieved and authenticated/decrypted successfully. Wrong-record binding
and tampered ciphertext failed authentication. No key was retained and protected
values were absent from audit changes. This proves the SQL integration contract
can be exercised; the temporary checker is not a production encryption service.
The committed workflow implementation/tests require SQL/Bash, not Python.

Rehearsed the one-time upgrade from the committed baseline in a disposable database;
the upgrade and workflow checks passed. A repeated upgrade stopped before replacing
the revised Draft procedure. Verified all eight affected legacy frozen-field examples
return 1644. Original Draft walkthrough and all three existing table walkthroughs
passed with the new objects installed. Base-table overview remained 15/114/27/52.
Disposable verification databases were removed.

Applied the verified upgrade to micro_lending_dev, then reran the existing table
walkthrough runner. Installed 14 procedures, one function, one view and one guard
trigger; all routines use INVOKER security. Table data remained Role = 4 and all
other tables = 0, with no retained walkthrough rows. Bash syntax, Git whitespace,
and local README/Milestones links passed checks. Confirmed schema.sql, TDD, ERD and
model match their committed versions. No commit or push was made.

## Milestone 13: Clean SQL build organization

Consolidated the implementation by SQL object type, following the build-list style
reviewed with the user. This is an organization change for the same FR-01/02/03/05/
06/07 behavior and course reproducible-build methodology; no business rules or
security/transaction behavior changed.

### Current build order

[manifest.txt](../database/manifest.txt) lists the implemented SQL in order:

1. database/00_create_database.sql
2. database/schema.sql
3. database/02_programmability/010_views.sql
4. database/02_programmability/020_functions.sql
5. database/02_programmability/030_procedures.sql
6. database/02_programmability/040_triggers.sql
7. database/04_seed/010_reference_data.sql
8. database/05_validation/010_object_validation.sql

Kept all 15 table definitions and constraints in schema.sql. The four programmability
files contain one view, one function, all 14 procedures (helpers first), and one
trigger respectively. Object names, parameters and complete CREATE definitions are
unchanged. The prior per-feature files were consolidated rather than retained as
duplicate executable copies. Historical descriptions in earlier milestones refer
to those earlier file arrangements.

Renamed the role seed to reference data: these are application business-role codes,
not MySQL security grants. Renamed the object overview to object validation. Future
technical roles/grants and full fictional sample seeds remain pending; no empty
placeholder scripts imply they are implemented.

Moved seven walkthrough/test files under tests/sql: environment, accounts,
borrower_profile, schema, create_loan_request, early_workflows and
submission_concurrency. The application SQL build remains separate from test-only
fixtures/helpers. Updated all build/test/upgrade paths and README/Milestones links.
The existing historical username ALTER script remains available separately.

setup_local.sh creates the empty database and runs environment checks.
build_database.sh executes the remaining manifest entries with simple direct MySQL
commands. The one-time upgrade still targets commit 947ad55; it creates the view
and function, replaces only the old Draft routine, installs the grouped procedures,
then installs the trigger. Its repeated-run guard now stops at the existing view.
The current development database already contains these same definitions; this
layout cleanup requires no reinstall or change to its objects/data. The final
release-tag runner/security/sample-data deliverables remain pending as before.

### Verification actually performed

- Compared all 17 CREATE definitions with the saved pre-cleanup source: byte-for-byte
  identical. No schema.sql, TDD, ERD or model edits.
- Verified manifest paths exist and match the SQL order in the setup/build commands.
- Executed all eight manifest entries in a disposable database: 15 tables, 114 base
  columns, 27 FKs, 52 CHECKs, 14 procedures, one function, one view and one trigger.
- Compared compiled routine bodies, parameter definitions, security attributes,
  view and trigger with the existing development database: identical after schema
  name normalization. Development access was read-only during this cleanup.
- Re-ran the workflow runner: all 86 checks passed. Re-ran the original Draft runner:
  three valid Drafts and matching audit rows. Both dedicated test databases removed.
- Rehearsed the updated baseline upgrade: 86 workflow checks passed; a repeated run
  stopped before replacing the Draft routine. All eight affected legacy frozen-field
  examples still rejected as documented. Removed the upgrade verification database.
- Ran the moved environment and three table walkthroughs against the disposable
  manifest build; no walkthrough User rows remained. Removed that database.
- Bash syntax, Git whitespace and local documentation links passed checks.

No commit or push was made. Existing uncommitted implementation work and local
Milestones notes are preserved.

<a id="milestone-7-midterm-request-management-demonstration"></a>

## Milestone 14: Midterm request-management demonstration

Implemented October 21, 2026 on top of pulled commit `a9303d5`. The README already
reported a complete 15-table schema and early account/profile/Draft/submission
operations; the numbered history in this file still ended at Milestone 6. Preserve
that earlier history and use this entry for the current snapshot and new evidence.
The original TDD and ERD artifacts are unchanged.

### Chosen boundary and concrete implementation

This is the team's chosen midterm scope, **not a confirmed instructor checklist**.
Keep the existing schema/accounts/profiles/Draft/submission work. Stop before adding
assessment, administrator review/approval, funding, activation, repayment allocation
or an application UI/backend. Directly seeded later-stage records are explicitly
historical classroom fixtures, not executed workflows. This boundary follows the
user's supplied midterm plan; no professor approval is inferred.

| File | Purpose / decision |
| --- | --- |
| [031_draft_cancellation.sql](../database/02_programmability/031_draft_cancellation.sql) | sp_cancel_draft checks a real current Borrower/Administrator role, account status, owner (Borrower), Draft state, expected version and 1–1000-character reason; locks Users in ID order then the request; commits state/version/reason and success audit together |
| [041_request_delete_guard.sql](../database/02_programmability/041_request_delete_guard.sql) | BEFORE DELETE rejects any LoanRequest deletion, including an unreferenced Draft; cancellation is UPDATE |
| [011_midterm_reports.sql](../database/02_programmability/011_midterm_reports.sql) | Administrative request, funding-progress and allocation-balance views, with child aggregation before joins |
| [020_midterm_sample_data.sql](../database/04_seed/020_midterm_sample_data.sql) | Four existing Role rows plus 339 fictional rows reproduce the existing 343-row JSON fixture in a fresh dedicated DB; refuses existing data or a different DB name |
| [demo_midterm.sh](../build/demo_midterm.sh) | Single presentation entry point: fresh dedicated DB, build, seed, SQL story/checks and technical privilege checks; preserves the DB for inspection |
| [midterm_demo.sql](../tests/sql/midterm_demo.sql) | Create/read/edit/cancel, rejected actions, injected audit-failure rollback, reports, history and EXPLAIN; 44 assertions fail the command on mismatches |
| [midterm_permissions.sql](../tests/sql/midterm_permissions.sql) | Locked test identity/default reporting role; DEFINER probe demonstrates real allowed SELECT, denied UPDATE and revoked SELECT, then removes its objects |
| [upgrade_midterm.sh](../build/upgrade_midterm.sh) | One-time additive SQL upgrade from a9303d5; no DROP, replacement, table rebuild or seed load on dev |

The object-type organization remains intact. The manifest and existing fresh-build /
early-test runners now include the three new object files. The original 14 procedures,
base schema and frozen-terms trigger are unchanged. Fresh builds now have 15 procedures,
one function, four views and two triggers. There are still 15 tables, 114 columns,
27 FKs and 52 CHECK constraints. The S71 commented invalid example now expects the
request-delete trigger's 1644 before the foreign-key check, rather than 1451.

### Explain the important choices

- Restricted owners can cancel; inactive owners cannot. An Active Administrator can
  cancel another user's Draft. A caller cannot merely claim an ungranted role. The
  supplied actor ID is still a trusted-caller parameter, not proof of authentication.
- Draft cancellation deliberately rejects other states and unexpected evaluation,
  contribution or loan children. FR-10's broader cancellation/release workflow is
  not complete. No pending contributions are released by this midterm routine.
- A successful cancel creates RequestCancelled with BORROWER_CANCELLED or
  ADMIN_DECISION, plus RequestState and TerminalReason old/new values. A failed audit
  append rolls back the request update, version and reason as well as the event.
  Rejections currently return errors without retaining separate denial-audit events.
- Public actions own their transactions. Use them outside an existing transaction;
  a later outer ROLLBACK cannot undo their committed results.
- The fictional seed is a directly inserted historical dataset with opaque private
  placeholders and unusable credential markers. It contains seeded loans, payments,
  assessments/reviews, funding and audit examples; it proves no later-stage workflow.
  The previous encrypted materializer is optional future tooling, not used by this
  simple SQL classroom seed. All fixture fields except generated values are loaded;
  generated values come from the schema.
- Report views are administrative technical projections, not RQ-01–08 production
  endpoints. SQL SECURITY DEFINER lets the restricted reporting role read the explicit
  view without base-table grants. Application ownership needs authenticated context
  and separate checks. WHERE/EXISTS in a report does not implement that boundary.
- Loan 501 remains 550 outstanding after 350 allocated; loan 502 remains 200 after 400.
  Request 101 totals 900 despite repeated participation. Lender 2's distinct loan
  balance is 550. On the declared date 2026-10-19, loan 501 has 250 overdue and 18 days
  past due; a due date equal to the report date is not overdue. These are historical
  fixture calculations, not a newly executed delinquency evaluation.
- The EXPLAIN example is a primary-key point lookup: const / PRIMARY / one estimated
  row was observed. Larger-data timing/index tuning and the marketplace lock-contention
  benchmark remain future work; no performance improvement is claimed.

### Verification actually performed

Executed against a **separate Linux MySQL Community Server 8.4.6 instance**, with
lower_case_table_names=0. This is distinct from the earlier Mac MySQL 26.7.0 evidence.
The Mac/development connection was not accessed, upgraded, seeded or cleared.

- Fresh build and all 343 fixture rows loaded with FK/CHECK/UNIQUE constraints enabled.
- All **44** midterm assertions passed: retained cancellation terms/reason/version,
  Borrower/Admin attribution, owner/role/status/state/version/reason rejections,
  prohibited deletion of both referenced and unreferenced requests, maximum reason,
  forced post-update audit failure with full rollback, joins/aggregation and balances.
- Technical permission probe: SELECT returned rows; UPDATE returned **1142**. After
  REVOKE, SELECT returned **1142**. No password was distributed; the locked test user,
  role and probe were removed on success. This is not the final runtime privilege set.
- Existing early_workflows.sql passed all **86** assertions, including submission
  behavior and previous forced audit-failure checks, with the new objects installed.
- Repeating the shell presentation runner stopped on existing DB error **1007** and
  preserved rows. Repeating the seed stopped on guard error **3819** before writes.
- Built the previous committed objects in another isolated DB, created an account,
  profile and Draft, then applied the three additive files. Compared all existing
  User/UserRole/BorrowerProfile/LoanRequest/AuditEvent/AuditChange values byte-for-byte:
  unchanged. A seed attempt against that non-demo DB was also rejected without change.
- Replayed the SQL presentation on the same dedicated demo dataset successfully.
  It adds new fictional request/audit rows; it does not overwrite the initial fixture.
- Live metadata confirmed the unchanged table/column/FK/CHECK inventory and the new
  routine/view/trigger counts. Checked Bash syntax, whitespace and local links.

Run [the README command and walkthrough](../README.md#midterm-request-management-and-database-demonstration)
for the presentation. If a command fails, inspect the dedicated DB and any remaining
helper/user/role before retrying. No automatic reset/delete is built into the runner.
This increment is not the final exact-tag evaluator build or full FRD acceptance proof.

## Milestone 15: Manual Workbench demo and speaking notes

Added tests/sql/midterm_walkthrough.sql and docs/Midterm_Demo_Guide.md for the
user's narrated midterm rehearsal. README links both files. The main story uses
existing FR-06 Draft creation/editing and the implemented Draft-only FR-10
cancellation branch, followed by rejection, BR-23 rollback, live audit history,
and a primary-key EXPLAIN. It does not perform submission, assessment, approval,
funding, activation or repayment actions. Submission routines remain available
separately; the trusted encryption coordinator remains unfinished.

Optional report sections are explicitly labelled as queries over seeded historical
finance. Permissions instructions reuse tests/sql/midterm_permissions.sql and
explain its limited DEFINER probe rather than claiming application authentication.
The walkthrough selects only the existing demo database, requires one connection,
and labels each intentional failure for individual execution in Workbench.
Successful calls commit and add two fictional requests; replay is not a reset.

Rehearsed the entire SQL file against the current manifest and fictional seed in
a disposable local MySQL database. The verification runner used --force only for
this intentional-error walkthrough, not for the build. Exactly four expected
1644 errors occurred (invalid amount, cancelled edit, deletion, injected audit
failure). Verified Cancelled/version 2 and a separate Draft/version 0 after
rollback, unchanged audit counts for the failed action, three original-request
events, expected balances/funding gaps, and removal of the test trigger.
Only the two new requests and four successful action audit events remained before
the disposable database was dropped. Existing demo/development databases were
not accessed. Checked local links and Git whitespace; schema, application routines
and TDD are unchanged. No commit or push was made.

## Remaining implementation

The midterm request-management demonstration is implemented as described above.
Full-release assessment, review/approval, funding/activation, repayment allocation,
delinquency updates, scoped production reports, complete audit/immutability controls,
application authentication/encryption, a running API/UI and the final tagged build
remain unfinished. Larger-data performance and funding/repayment concurrency are not
demonstrated. The professor's service-architecture interpretation remains open.

## Possible design-document updates for later review

These are notes to consider later, not changes applied to the design documents:

- Record the actual local MySQL version and decide the final supported baseline.
- Update implementation-status statements and acceptance gates with the current
  complete schema, early workflows and midterm demonstration evidence.
- Record later enforcement decisions and results when they are implemented and
  reviewed. Structural table constraints alone do not complete the security and
  business requirements.

Keep the SQL walkthrough here unless we later decide it belongs in the TDD.

## Configurable entitlements

October 30: reviewed implementation. Adds capability tables, custom-role
configuration, local operator console, scoped reads and data-preserving migration.
Tests and limitations are recorded in [Entitlements](Entitlements.md). Existing 44/86
assertion suites passed on isolated MySQL8.4.6; no development database was modified.
User approved this implementation for commit.

### Expanded administration implementation

Independent scrypt-backed administrator sign-in, hashed in-memory sessions, bounded
concurrent request handling, per-action connections, denial/failure records after rollback,
correlated request/SQL spans, protected monitoring and local alert/recovery are implemented.
The complete contract and reproducible tests are in [Entitlements](Entitlements.md).

Observed on isolated MySQL 8.4.6: revised midterm 45 and early-workflow 87 assertions,
entitlement SQL cases, migration preservation, actual credential provisioning, runtime
privilege denials, two administrator HTTP sessions, simultaneous edits, revocation,
last-admin race, logout, evidence deduplication, real connection failure/fallback and
recovery. Seven unit tests cover the associated security/telemetry boundaries. Sessions
are single-instance memory; global policy serialization remains deliberate. No development
database or external notification was used. User approved the completed change for commit.

### Observability handout acceptance

Mapped the supplied handout's nine deliverables to existing/new artifacts. Added real
histograms and capacity gauges, protected metrics and trace views, explicit parent/child
span identity, alert duration/context/links, and a disposable before/after experiment.
Observed controlled-delay p50 181.68→30.07 ms and p95 224.68→38.36 ms over ten samples
per phase; full timing controls/source hashes are in the JSON evidence. Nine unit tests,
45/87 SQL checks, concurrency/security/migration checks and the metrics/trace/diagnosis
integration passed. This is a local classroom manual-instrumentation implementation;
there is no real connection pool, external monitoring backend or claimed production
speedup. User approved these changes for commit.


## Table-driven request workflow implementation — October 30, 2026

[Current contract and demonstration](Table_Driven_Workflows.md). Added RequestWorkflowState,
RequestWorkflowAction and RequestWorkflowTransition, a common transition helper, and
an audited/versioned administrator Enable/Disable API and screen. Existing create/edit/
submit/cancel handlers resolve their permission, source/destination and event through
those rows. Fixed scoped permission selection for dual-role users and binary UUID
context coercion. The current extended model has 20 tables, 136 columns and 33 FKs.
Fresh-build and one-time migration paths are included; no development database was
migrated during implementation. Existing 45/87 SQL checks, new workflow/FK/rollback
checks, migration preservation and real authenticated HTTP integration pass locally
on MySQL 26.7.0. Remaining financial handlers, durable worker execution and general
failure-attribution corrections are not included in this increment.
