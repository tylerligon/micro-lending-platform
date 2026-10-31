#!/usr/bin/env bash
# One-time upgrade from 1deed92. Backup/stop callers first. No fixture/reset.
# Historical stage is pinned; run later upgrade stages separately.
set -euo pipefail
mysql="${MYSQL_BIN:-/usr/local/mysql/bin/mysql}"
login="${MYSQL_LOGIN_PATH:-cs437}"
db="${MYSQL_DATABASE:-micro_lending_dev}"
for file in database/migrations/020_entitlements.sql database/02_programmability/025_entitlements.sql database/04_seed/015_permissions.sql database/migrations/021_replace_early_routines.sql database/02_programmability/030_procedures.sql database/02_programmability/031_draft_cancellation.sql; do
 git show 189ed0f95dbf34f34d392f87e8ee2d9c33192bf4:"$file" | "$mysql" --login-path="$login" "$db"
done
