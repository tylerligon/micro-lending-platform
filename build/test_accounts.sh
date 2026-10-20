#!/usr/bin/env bash
# Run from the repository root after the account tables and roles are built.
set -e

# Run the valid examples and compare the displayed results with their comments.
# Invalid examples inside tests.sql are commented out; run those one at a time.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/tests.sql
