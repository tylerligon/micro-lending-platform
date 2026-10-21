#!/usr/bin/env bash
# ONE-TIME upgrade from commit 947ad55. Run from the repository root.
# Preserve tables/data; replace only the old Draft procedure to fix money precision.
# CREATE VIEW first stops an ordinary repeated run before the DROP PROCEDURE.
# DDL is not atomic: stop and inspect partial errors before retrying.
set -e

/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/010_views.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/020_functions.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev --execute="DROP PROCEDURE sp_create_loan_request;"
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/030_procedures.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/040_triggers.sql
