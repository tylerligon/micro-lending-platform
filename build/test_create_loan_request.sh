#!/usr/bin/env bash
# Run from the repository root. This creates and then drops ONLY a dedicated test DB.
# CREATE fails if the test database already exists; no existing database is overwritten.
# If a later step fails, set -e stops and leaves that test DB for inspection.
set -e

/usr/local/mysql/bin/mysql --login-path=cs437 --execute="CREATE DATABASE micro_lending_procedure_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_procedure_test < database/schema.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_procedure_test < database/04_seed/010_roles.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_procedure_test < database/02_programmability/010_create_loan_request.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_procedure_test < database/procedure_tests.sql
/usr/local/mysql/bin/mysql --login-path=cs437 --execute="DROP DATABASE micro_lending_procedure_test;"
