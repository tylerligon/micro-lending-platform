#!/usr/bin/env bash
# Run from the repository root. Refuse to overwrite an existing test database.
# On failure, leave this isolated database for inspection. Never load fixtures on dev.
set -e

/usr/local/mysql/bin/mysql --login-path=cs437 --execute="CREATE DATABASE micro_lending_workflow_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/schema.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/010_views.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/011_midterm_reports.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/020_functions.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/030_procedures.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/031_draft_cancellation.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/040_triggers.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/02_programmability/041_request_delete_guard.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < database/04_seed/010_reference_data.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_workflow_test < tests/sql/early_workflows.sql
/usr/local/mysql/bin/mysql --login-path=cs437 --execute="DROP DATABASE micro_lending_workflow_test;"
