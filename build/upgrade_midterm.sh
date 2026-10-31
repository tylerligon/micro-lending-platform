#!/usr/bin/env bash
# ONE-TIME additive upgrade from a9303d5. Does not seed, rebuild or delete dev data.
# DDL is not atomic. Stop and inspect partial errors; do not rerun blindly.
# Historical stage is pinned; run later upgrade stages separately.
set -euo pipefail
git show 1deed928192f0f203e4f780e1b1a87daa957951a:database/02_programmability/031_draft_cancellation.sql | /usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev
git show 1deed928192f0f203e4f780e1b1a87daa957951a:database/02_programmability/041_request_delete_guard.sql | /usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev
git show 1deed928192f0f203e4f780e1b1a87daa957951a:database/02_programmability/011_midterm_reports.sql | /usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev
