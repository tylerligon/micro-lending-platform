-- Structural overview for the current 15-table design. Compare with these expectations.
-- INFORMATION_SCHEMA is MySQL's built-in catalogue of tables, columns, and constraints.
-- DATABASE() limits each query to the database selected for this connection.

-- Expected: 15 tables, 114 columns, 27 foreign keys, and 52 CHECK constraints.
SELECT COUNT(*) AS table_count FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE';
SELECT COUNT(*) AS column_count FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN (
    SELECT TABLE_NAME FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE');
SELECT COUNT(*) AS foreign_key_count FROM information_schema.REFERENTIAL_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE();
SELECT COUNT(*) AS check_count FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_TYPE = 'CHECK';

-- Expected: 15 rows, all using InnoDB.
SELECT TABLE_NAME, ENGINE FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;

-- Expected: LoginName is utf8mb4_0900_ai_ci; status/role columns are utf8mb4_0900_bin.
SELECT TABLE_NAME, COLUMN_NAME, COLLATION_NAME FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'User' AND COLUMN_NAME IN ('LoginName', 'AccountStatus'))
       OR (TABLE_NAME IN ('Role', 'UserRole') AND COLUMN_NAME = 'RoleCode'))
ORDER BY TABLE_NAME, COLUMN_NAME;

-- After the full early-workflow build: 14 procedures, 1 function, 1 view, 1 trigger.
SELECT ROUTINE_TYPE, COUNT(*) AS routine_count FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() GROUP BY ROUTINE_TYPE ORDER BY ROUTINE_TYPE;
SELECT COUNT(*) AS view_count FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE();
SELECT COUNT(*) AS trigger_count FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE();
