-- Show which server and database this connection is using.
SELECT VERSION() AS server_version, DATABASE() AS database_name;

-- Temporary tables exist only in this connection, not as application tables.
CREATE TEMPORARY TABLE EnvironmentAmount (
    Amount DECIMAL(10,2) NOT NULL
) ENGINE = InnoDB;

-- ROLLBACK undoes an uncommitted insert. Expected count: 0.
START TRANSACTION;
INSERT INTO EnvironmentAmount (Amount) VALUES (12.34);
ROLLBACK;
SELECT COUNT(*) AS rows_after_rollback FROM EnvironmentAmount;

-- COMMIT keeps the insert. Expected: one row containing exactly 12.34.
START TRANSACTION;
INSERT INTO EnvironmentAmount (Amount) VALUES (12.34);
COMMIT;
SELECT Amount FROM EnvironmentAmount;

-- Remove only the temporary demonstration table.
DROP TEMPORARY TABLE EnvironmentAmount;
