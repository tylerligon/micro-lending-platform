#!/usr/bin/env bash
# One-time from 189ed0f only. Backup and stop callers; DDL is not atomic.
# No fixture/reset. Reapply runtime grants after replacing routines.
set -euo pipefail
mysql="${MYSQL_BIN:-/usr/local/mysql/bin/mysql}"
login="${MYSQL_LOGIN_PATH:-cs437}"
db="${MYSQL_DATABASE:-micro_lending_dev}"
for file in database/migrations/030_request_workflow.sql database/02_programmability/025_entitlements.sql database/02_programmability/026_request_workflow.sql database/04_seed/016_request_workflow.sql database/02_programmability/030_procedures.sql database/02_programmability/031_draft_cancellation.sql; do
 "$mysql" --login-path="$login" "$db" < "$file"
done
