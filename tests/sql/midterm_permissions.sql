-- Basic database privilege demonstration, run as the setup administrator.
-- Only the isolated demo DB. Creates a LOCKED, passwordless/unusable login identity.
-- Locked users can own a DEFINER procedure, allowing a real privilege check without
-- distributing a demo password or changing connections. The probe is test-only.
CREATE TEMPORARY TABLE midterm_permission_guard (Safe TINYINT NOT NULL CHECK (Safe = 1));
INSERT INTO midterm_permission_guard SELECT DATABASE() = 'micro_lending_midterm_demo';
DROP TEMPORARY TABLE midterm_permission_guard;
-- No IF NOT EXISTS: refuse to reuse another person's user/role on this server.
CREATE USER 'cs437_midterm_demo_reader'@'localhost' ACCOUNT LOCK;
CREATE ROLE 'cs437_midterm_demo_reports'@'localhost';
GRANT SELECT ON micro_lending_midterm_demo.v_request_funding_progress TO 'cs437_midterm_demo_reports'@'localhost';
GRANT 'cs437_midterm_demo_reports'@'localhost' TO 'cs437_midterm_demo_reader'@'localhost';
SET DEFAULT ROLE 'cs437_midterm_demo_reports'@'localhost' TO 'cs437_midterm_demo_reader'@'localhost';
DELIMITER //
CREATE DEFINER = 'cs437_midterm_demo_reader'@'localhost' PROCEDURE midterm_privilege_probe(IN p_ExpectRead BOOLEAN)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_Count INT;
    DECLARE v_ReadError INT DEFAULT 0;
    DECLARE v_WriteError INT DEFAULT 0;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_ReadError = MYSQL_ERRNO; END;
        SELECT COUNT(*) INTO v_Count FROM v_request_funding_progress;
    END;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_WriteError = MYSQL_ERRNO; END;
        UPDATE LoanRequest SET Purpose = 'Forbidden reader write' WHERE RequestID = 101;
    END;
    IF (p_ExpectRead AND (v_ReadError <> 0 OR v_Count < 1))
       OR (NOT p_ExpectRead AND v_ReadError <> 1142) OR v_WriteError <> 1142 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Database privilege demonstration failed';
    END IF;
    SELECT CURRENT_USER() AS EffectiveAccount, CURRENT_ROLE() AS ActiveRole,
        v_ReadError AS ReadError, v_WriteError AS UpdateError, p_ExpectRead AS ExpectedReadAllowed;
END //
DELIMITER ;
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.midterm_privilege_probe TO 'cs437_midterm_demo_reader'@'localhost';
SHOW GRANTS FOR 'cs437_midterm_demo_reader'@'localhost';
SHOW GRANTS FOR 'cs437_midterm_demo_reports'@'localhost';
CALL midterm_privilege_probe(TRUE); -- SELECT allowed, UPDATE rejected with 1142.
REVOKE SELECT ON micro_lending_midterm_demo.v_request_funding_progress FROM 'cs437_midterm_demo_reports'@'localhost';
CALL midterm_privilege_probe(FALSE); -- SELECT now also rejected with 1142.
DROP PROCEDURE midterm_privilege_probe;
DROP USER 'cs437_midterm_demo_reader'@'localhost';
DROP ROLE 'cs437_midterm_demo_reports'@'localhost';
SELECT 'PASS: GRANT permits view SELECT; UPDATE denied; REVOKE removes SELECT' AS PrivilegeChecks;
-- This is technical DB privilege enforcement, NOT authenticated business ownership.
-- The views are administrative classroom reports, not borrower/lender-scoped endpoints.
