#!/usr/bin/env bash
# Run from the repository root. Create the database once, before building tables.
# Stop if a command fails, so later steps do not run after an error.
set -e

# The saved cs437 login contains our local connection settings; no password here.
# < sends the SQL file to MySQL for execution.
/usr/local/mysql/bin/mysql --login-path=cs437 < database/00_create_database.sql

# The database name selects where the temporary environment checks run.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/05_validation/000_environment.sql
