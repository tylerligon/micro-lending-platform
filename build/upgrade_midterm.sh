#!/usr/bin/env bash
# ONE-TIME additive upgrade from a9303d5. Does not seed, rebuild or delete dev data.
# DDL is not atomic. Stop and inspect partial errors; do not rerun blindly.
set -e
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/031_draft_cancellation.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/041_request_delete_guard.sql
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/02_programmability/011_midterm_reports.sql
