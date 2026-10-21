#!/usr/bin/env bash
# Run from the repository root after all tables and roles are built.
set -e

# First display the schema overview; compare the results with the SQL comments.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/05_validation/010_schema.sql

# Run the valid examples and compare the displayed results with their comments.
# Invalid examples inside tests.sql are commented out; run those one at a time.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/tests.sql

# Check the one-to-one borrower profile, its required fields, and rollback.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/borrower_profile_tests.sql

# Check request, lending, repayment, note, and audit table relationships.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/schema_tests.sql
