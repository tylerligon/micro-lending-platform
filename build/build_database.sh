#!/usr/bin/env bash
# Run from the repository root after creating an empty micro_lending_dev database.
# Stop on an error; never drop or replace existing tables.
set -e

# First create all 15 tables in dependency order.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/schema.sql

# Install the Draft-creation procedure after its tables exist.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/010_create_loan_request.sql

# Then insert the four role definitions into the new Role table.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/04_seed/010_roles.sql

# Display the expected table/column/key counts and storage engines.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/05_validation/010_schema.sql
