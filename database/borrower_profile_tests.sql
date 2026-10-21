-- BorrowerProfile structural examples for FR-05 / BR-01 / BR-05 / SEC-12.
-- Use the same manual-test approach as tests.sql: read the expected results.
-- Running the whole file skips the commented invalid examples and ends in rollback.
-- Dummy bytes are not usable encrypted financial values. Never COMMIT this file.

-- SECTION 1: Create one fictional parent account and its profile.
-- The table requires a User, but Borrower-role/ownership checks are later service work.
-- This reserved demo name must not already exist. Stop on any setup error.
SET SESSION time_zone = '+05:00';
START TRANSACTION;

INSERT INTO `User` (LoginName, DisplayName, PublicAlias, PrivateEmailCipher, PasswordHash)
VALUES ('profile_demo', 'Profile Demo', 'profile_demo', X'01', 'constraint-test-only');
SET @profile_user = LAST_INSERT_ID();

INSERT INTO BorrowerProfile (UserID, MonthlyIncomeCipher, ExternalObligationsCipher)
VALUES (@profile_user, X'01', X'02');

-- SECTION 2: Invalid examples. Run ONE with fresh Section 1 setup in Workbench.
-- Select the SQL after -- and execute it without the comment prefix.
-- Check the error code, then run ROLLBACK; in the same connection, even after errors.
-- Repeat Section 1 for the next example. Do not run Section 3 during a negative test.
-- The large ID is a deliberately nonexistent user; REPEAT creates 129 test bytes.

-- B01: duplicate profile for the same user. Expected MySQL error 1062.
-- INSERT INTO BorrowerProfile (UserID, MonthlyIncomeCipher, ExternalObligationsCipher) VALUES (@profile_user, X'03', X'04');

-- B02: profile for a nonexistent user. Expected MySQL error 1452.
-- INSERT INTO BorrowerProfile (UserID, MonthlyIncomeCipher, ExternalObligationsCipher) VALUES (18446744073709551615, X'01', X'02');

-- B03: missing income field. Expected MySQL error 1048.
-- UPDATE BorrowerProfile SET MonthlyIncomeCipher = NULL WHERE UserID = @profile_user;

-- B04: missing obligations field. Expected MySQL error 1048.
-- UPDATE BorrowerProfile SET ExternalObligationsCipher = NULL WHERE UserID = @profile_user;

-- B05: empty income bytes. Expected MySQL error 3819.
-- UPDATE BorrowerProfile SET MonthlyIncomeCipher = X'' WHERE UserID = @profile_user;

-- B06: empty obligations bytes. Expected MySQL error 3819.
-- UPDATE BorrowerProfile SET ExternalObligationsCipher = X'' WHERE UserID = @profile_user;

-- B07: income field longer than 128 bytes. Expected MySQL error 1406 in strict mode.
-- UPDATE BorrowerProfile SET MonthlyIncomeCipher = REPEAT('x', 129) WHERE UserID = @profile_user;

-- B08: obligations field longer than 128 bytes. Expected MySQL error 1406 in strict mode.
-- UPDATE BorrowerProfile SET ExternalObligationsCipher = REPEAT('x', 129) WHERE UserID = @profile_user;

-- B09: deleting an account still referenced by a profile. Expected MySQL error 1451.
-- DELETE FROM `User` WHERE UserID = @profile_user;

-- B10: changing an account ID still referenced by a profile. Expected MySQL error 1451.
-- UPDATE `User` SET UserID = 18446744073709551615 WHERE UserID = @profile_user;

-- SECTION 3: Valid examples.
-- P01: Expected: one matching account/profile, one byte in each field, RowVersion 0.
-- The shared key connects the two records without a second profile identifier.
SELECT u.LoginName, OCTET_LENGTH(p.MonthlyIncomeCipher) AS income_bytes,
       OCTET_LENGTH(p.ExternalObligationsCipher) AS obligation_bytes, p.RowVersion
FROM `User` AS u
JOIN BorrowerProfile AS p ON p.UserID = u.UserID
WHERE p.UserID = @profile_user;

-- P02: Expected 1: default uses UTC even though this session is set to +05:00.
SELECT ABS(TIMESTAMPDIFF(SECOND, UpdatedAt, UTC_TIMESTAMP(6))) <= 2 AS uses_utc
FROM BorrowerProfile WHERE UserID = @profile_user;

-- P03: Demonstrate an explicit update; these fields do not increment themselves.
-- WHERE RowVersion = 0 matches the version we read; a stale version would not match.
UPDATE BorrowerProfile
SET MonthlyIncomeCipher = X'03', UpdatedAt = UTC_TIMESTAMP(6), RowVersion = RowVersion + 1
WHERE UserID = @profile_user AND RowVersion = 0;
SELECT ROW_COUNT() AS updated_rows;
-- Expected: updated_rows = 1, then RowVersion = 1 and income_matches_update = 1.
SELECT RowVersion, MonthlyIncomeCipher = X'03' AS income_matches_update
FROM BorrowerProfile WHERE UserID = @profile_user;

-- SECTION 4: Undo both profile and account changes. Expected counts: 0 and 0.
ROLLBACK;
SET SESSION time_zone = '+00:00';
SELECT COUNT(*) AS demo_profiles_remaining FROM BorrowerProfile WHERE UserID = @profile_user;
SELECT COUNT(*) AS demo_users_remaining FROM `User` WHERE UserID = @profile_user;
