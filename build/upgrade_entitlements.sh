#!/usr/bin/env bash
# One-time upgrade from 1deed92. Backup/stop callers first. No fixture/reset.
set -e
mysql="${MYSQL_BIN:-/usr/local/mysql/bin/mysql}"
login="${MYSQL_LOGIN_PATH:-cs437}"
db="${MYSQL_DATABASE:-micro_lending_dev}"
for file in database/migrations/020_entitlements.sql database/02_programmability/025_entitlements.sql database/04_seed/015_permissions.sql database/migrations/021_replace_early_routines.sql database/02_programmability/030_procedures.sql database/02_programmability/031_draft_cancellation.sql; do
 "$mysql" --login-path="$login" "$db" < "$file"
done
