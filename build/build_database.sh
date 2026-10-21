#!/usr/bin/env bash
# Run from the repository root after setup_local.sh creates an empty development DB.
# See database/manifest.txt for the SQL order. Stop on errors; never replace tables.
set -e

# Tables first, then views, functions, procedures, and triggers.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/schema.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/010_views.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/020_functions.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/030_procedures.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/040_triggers.sql

# Reference data and object validation complete the current build.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/04_seed/010_reference_data.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/05_validation/010_object_validation.sql
