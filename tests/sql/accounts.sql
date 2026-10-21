-- Account-table examples: partial FR-01/02 and BR-01/02 structural checks.
-- Run against micro_lending_dev after loading schema.sql and the four roles.
-- Running this entire file executes valid examples; invalid statements stay comments.
-- Compare SELECT results with the expected results written beside them.
-- These are demonstrations, not an automatic pass/fail test framework.

-- SECTION 1: Set up fictional test records inside a transaction.
-- Use these reserved demo names only for tests. Existing names cause an error;
-- do not delete existing users to make a test run. Stop and investigate instead.
-- X'01' is one byte of dummy data, not an encrypted email.
-- 'constraint-test-only' is dummy text, not a usable password hash.
-- Never COMMIT these examples. ROLLBACK at the end removes the test records.
SET SESSION time_zone = '+00:00';
START TRANSACTION;

-- @ variables last for this connection. LAST_INSERT_ID() returns the new row's ID.
SET @member_login = 'demo_member';
INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES (@member_login, 'Demo Member', 'demo_member', X'01', 'constraint-test-only');
SET @member = LAST_INSERT_ID();

INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES ('demo_admin', 'Demo Administrator', 'demo_admin', X'01', 'constraint-test-only');
SET @admin = LAST_INSERT_ID();

-- NULL grantor represents the initial administrator bootstrap for this example.
INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID)
VALUES (@admin, 'Administrator', '2026-10-20 12:00:00', NULL);

INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID)
VALUES (@member, 'Borrower', '2026-10-20 12:00:00', @admin);
SET @membership = LAST_INSERT_ID();

-- SECTION 2: Invalid examples. Each statement below SHOULD be rejected.
-- In Workbench, select and run SECTION 1 first, stopping if setup reports any error.
-- Select the SQL after -- for ONE example below and run it without the -- prefix.
-- Compare MySQL's error code with the comment, then run ROLLBACK; in the same tab.
-- Repeat from SECTION 1 for the next example; do not run SECTION 3 in between.
-- Keep these statements commented when running the entire file from Terminal.
-- The large ID in the FK examples is a deliberately nonexistent test parent ID.

-- N01: duplicate user primary key. Expected MySQL error 1062.
-- INSERT INTO `User` SELECT * FROM `User` WHERE UserID = @member;

-- N02: duplicate login. Expected MySQL error 1062.
-- UPDATE `User` SET LoginName = @member_login WHERE UserID = @admin;

-- N03: duplicate alias. Expected MySQL error 1062.
-- UPDATE `User` SET PublicAlias = @member_login WHERE UserID = @admin;

-- N04: missing login. Expected MySQL error 1048.
-- UPDATE `User` SET LoginName = NULL WHERE UserID = @member;

-- N05: missing encrypted email. Expected MySQL error 1048.
-- UPDATE `User` SET PrivateEmailCipher = NULL WHERE UserID = @member;

-- N06: blank login. Expected MySQL error 3819.
-- UPDATE User SET LoginName = '   ' WHERE UserID = @member;

-- N07: blank display name. Expected MySQL error 3819.
-- UPDATE User SET DisplayName = '   ' WHERE UserID = @member;

-- N08: blank public alias. Expected MySQL error 3819.
-- UPDATE User SET PublicAlias = '' WHERE UserID = @member;

-- N09: invalid account status. Expected MySQL error 3819.
-- UPDATE User SET AccountStatus = 'Deleted' WHERE UserID = @member;

-- N10: incorrect status capitalization. Expected MySQL error 3819.
-- UPDATE User SET AccountStatus = 'active' WHERE UserID = @member;

-- N11: duplicate role primary key. Expected MySQL error 1062.
-- INSERT INTO Role VALUES ('Borrower', 'Duplicate');

-- N12: unsupported business role. Expected MySQL error 3819.
-- INSERT INTO Role VALUES ('Superuser', 'Unsupported');

-- N13: incorrect role capitalization. Expected MySQL error 3819.
-- INSERT INTO Role VALUES ('borrower', 'Incorrect spelling');

-- N14: blank role description. Expected MySQL error 3819.
-- UPDATE Role SET Description = ' ' WHERE RoleCode = 'Borrower';

-- N15: missing membership user. Expected MySQL error 1048.
-- UPDATE UserRole SET UserID = NULL WHERE UserRoleID = @membership;

-- N16: nonexistent member. Expected MySQL error 1452.
-- UPDATE UserRole SET UserID = 18446744073709551615 WHERE UserRoleID = @membership;

-- N17: nonexistent role. Expected MySQL error 1452.
-- UPDATE UserRole SET RoleCode = 'Missing' WHERE UserRoleID = @membership;

-- N18: nonexistent grantor. Expected MySQL error 1452.
-- UPDATE UserRole SET GrantedByUserID = 18446744073709551615 WHERE UserRoleID = @membership;

-- N19: nonexistent revoker. Expected MySQL error 1452.
-- UPDATE UserRole SET RevokedAt = '2026-10-20 12:01:00', RevokedByUserID = 18446744073709551615 WHERE UserRoleID = @membership;

-- N20: duplicate active membership. Expected MySQL error 1062.
-- INSERT INTO UserRole (UserID, RoleCode, GrantedByUserID) VALUES (@member, 'Borrower', @admin);

-- N21: revocation time without revoker. Expected MySQL error 3819.
-- UPDATE UserRole SET RevokedAt = '2026-10-20 12:01:00' WHERE UserRoleID = @membership;

-- N22: revoker without revocation time. Expected MySQL error 3819.
-- UPDATE UserRole SET RevokedByUserID = @admin WHERE UserRoleID = @membership;

-- N23: revocation before grant. Expected MySQL error 3819.
-- UPDATE UserRole SET RevokedAt = '2026-10-20 11:59:00', RevokedByUserID = @admin WHERE UserRoleID = @membership;

-- N24: deletion of referenced member. Expected MySQL error 1451.
-- DELETE FROM `User` WHERE UserID = @member;

-- N25: deletion of referenced grantor. Expected MySQL error 1451.
-- DELETE FROM `User` WHERE UserID = @admin;

-- N26: deletion of referenced role. Expected MySQL error 1451.
-- DELETE FROM Role WHERE RoleCode = 'Borrower';

-- N27: manual generated-column value. Expected MySQL error 3105.
-- UPDATE UserRole SET ActiveMarker = 0 WHERE UserRoleID = @membership;

-- N28: duplicate login with different capitalization. Expected MySQL error 1062.
-- UPDATE `User` SET LoginName = 'DEMO_MEMBER' WHERE UserID = @admin;

-- SECTION 3: Valid examples. Running the whole file reaches this section normally.

-- P01: Expected roles: Administrator, Auditor, Borrower, Lender (four rows).
SELECT RoleCode FROM `Role` ORDER BY RoleCode;

-- P02: Expected account defaults: Active and 0.
SELECT AccountStatus, RowVersion FROM `User` WHERE UserID = @member;

-- P03: Looking up DEMO_MEMBER returns the existing demo_member account (one row).
-- Stored spelling is preserved; comparisons ignore capitalization.
SELECT LoginName FROM `User` WHERE LoginName = 'DEMO_MEMBER';

-- A genuinely different username can still create a separate account.
INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES ('demo_other', 'Other Demo', 'demo_other', X'01', 'constraint-test-only');
SET @other_member = LAST_INSERT_ID();

-- P04: One member can hold Borrower and Lender; another can also hold Borrower.
-- Change this connection's time zone to prove the grant default still uses UTC.
SET SESSION time_zone = '+05:00';
INSERT INTO UserRole (UserID, RoleCode, GrantedByUserID)
VALUES (@member, 'Lender', @admin);
-- Expected: 1 (true). The stored grant time should be within two seconds of UTC.
-- ABS handles the sign of the difference; <= returns 1 for true or 0 for false.
SELECT ABS(TIMESTAMPDIFF(SECOND, GrantedAt, UTC_TIMESTAMP(6))) <= 2 AS uses_utc
FROM UserRole WHERE UserID = @member AND RoleCode = 'Lender';
SET SESSION time_zone = '+00:00';
INSERT INTO UserRole (UserID, RoleCode, GrantedByUserID)
VALUES (@other_member, 'Borrower', @admin);

-- P05: Revoke a grant, then insert a new episode instead of reusing the old row.
UPDATE UserRole
SET RevokedAt = '2026-10-20 12:01:00', RevokedByUserID = @admin
WHERE UserRoleID = @membership;

INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID)
VALUES (@member, 'Borrower', '2026-10-20 12:02:00', @admin);
SET @second_membership = LAST_INSERT_ID();

UPDATE UserRole
SET RevokedAt = '2026-10-20 12:03:00', RevokedByUserID = @admin
WHERE UserRoleID = @second_membership;

INSERT INTO UserRole (UserID, RoleCode, GrantedAt, GrantedByUserID)
VALUES (@member, 'Borrower', '2026-10-20 12:04:00', @admin);

-- Expected: three Borrower episodes, with markers NULL, NULL, 1 in that order.
SELECT RoleCode, GrantedAt, RevokedAt, ActiveMarker
FROM UserRole WHERE UserID = @member AND RoleCode = 'Borrower'
ORDER BY GrantedAt;

-- Expected active roles for this member: Borrower and Lender (two rows).
-- JOIN connects each assignment to its user and role definition by matching keys.
-- u, ur, and r are short table aliases used only within this query.
SELECT u.LoginName, r.RoleCode
FROM `User` AS u
JOIN UserRole AS ur ON ur.UserID = u.UserID
JOIN `Role` AS r ON r.RoleCode = ur.RoleCode
WHERE u.UserID = @member AND ur.ActiveMarker = 1
ORDER BY r.RoleCode;

-- SECTION 4 / P06: Undo all test changes. Expected counts: 0 and 0.
-- The seeded roles remain; only changes since START TRANSACTION are undone.
-- If running selected statements in Workbench, always run this ROLLBACK afterward,
-- including after an expected error. A rejected statement does not end a transaction.
ROLLBACK;
SELECT COUNT(*) AS demo_users_remaining FROM `User`
WHERE UserID IN (@member, @admin, @other_member);
SELECT COUNT(*) AS demo_memberships_remaining FROM UserRole
WHERE UserID IN (@member, @admin, @other_member);
