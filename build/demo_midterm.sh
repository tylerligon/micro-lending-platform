#!/usr/bin/env bash
# One presentation entry point. Creates ONLY a new isolated demo database.
# Refuse an existing name; leave the DB on success/failure for inspection.
set -e
mysql="${MYSQL_BIN:-/usr/local/mysql/bin/mysql}"
login="${MYSQL_LOGIN_PATH:-cs437}"
"$mysql" --login-path="$login" --execute="CREATE DATABASE micro_lending_midterm_demo CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/schema.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/010_views.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/011_midterm_reports.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/020_functions.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/030_procedures.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/031_draft_cancellation.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/040_triggers.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/02_programmability/041_request_delete_guard.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/04_seed/010_reference_data.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < database/04_seed/020_midterm_sample_data.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < tests/sql/midterm_demo.sql
"$mysql" --login-path="$login" micro_lending_midterm_demo < tests/sql/midterm_permissions.sql
