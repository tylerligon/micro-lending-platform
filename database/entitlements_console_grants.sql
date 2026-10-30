-- Run as build administrator AFTER creating a dedicated local MySQL account using
-- a private credential prompt. Replace console_operator with that account name.
-- Do not grant helper execution or direct business/audit-table writes.
GRANT SELECT ON micro_lending_midterm_demo.Role TO 'console_operator'@'localhost';
GRANT SELECT ON micro_lending_midterm_demo.Permission TO 'console_operator'@'localhost';
GRANT SELECT ON micro_lending_midterm_demo.RolePermission TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_require_permission TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_configure_role TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_configure_permission TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_set_role TO 'console_operator'@'localhost';
-- The console is a trusted operator gateway. Its MySQL credentials must remain local.
-- Stored procedures execute as the installer; review that definer before deployment.

GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_auth_lookup TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_session_user TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_failure_exists TO 'console_operator'@'localhost';
GRANT EXECUTE ON PROCEDURE micro_lending_midterm_demo.sp_record_failure TO 'console_operator'@'localhost';
