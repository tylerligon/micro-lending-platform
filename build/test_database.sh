#!/usr/bin/env bash
# Run from the repository root after all tables and roles are built.
set -e

# First display the schema overview; compare the results with the SQL comments.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/05_validation/010_object_validation.sql

# Run the valid examples and compare the displayed results with their comments.
# Invalid examples inside accounts.sql are commented out; run those one at a time.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < tests/sql/accounts.sql

# Check the one-to-one borrower profile, its required fields, and rollback.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < tests/sql/borrower_profile.sql

# Check request, lending, repayment, note, and audit table relationships.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < tests/sql/schema.sql
