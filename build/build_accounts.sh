#!/usr/bin/env bash
# Run from the repository root after creating an empty micro_lending_dev database.
# Stop on an error; never drop or replace existing tables.
set -e

# First create User, Role, and UserRole in dependency order.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/schema.sql

# Then insert the four role definitions into the new Role table.
/usr/local/mysql/bin/mysql --login-path=cs437 micro_lending_dev < database/04_seed/010_roles.sql
