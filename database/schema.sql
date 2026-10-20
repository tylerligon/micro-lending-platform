-- Create User and Role before UserRole. Load role seed data separately.
-- See docs/Milestones.md for the SQL walkthrough and remaining enforcement work.

CREATE TABLE `User` (
    UserID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    -- Inherit the database default: usernames compare case-insensitively.
    LoginName VARCHAR(80) NOT NULL,
    DisplayName VARCHAR(120) NOT NULL,
    PublicAlias VARCHAR(40) NOT NULL,

    PrivateEmailCipher VARBINARY(512) NOT NULL,
    PasswordHash VARCHAR(255) NOT NULL,
    AccountStatus VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'Active',
    CreatedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0,

    UNIQUE (LoginName),
    UNIQUE (PublicAlias),

    CHECK (CHAR_LENGTH(TRIM(LoginName)) > 0),
    CHECK (CHAR_LENGTH(TRIM(DisplayName)) > 0),
    CHECK (CHAR_LENGTH(TRIM(PublicAlias)) > 0),
    CHECK (AccountStatus IN ('Active', 'Restricted', 'Inactive'))
) ENGINE = InnoDB;

CREATE TABLE `Role` (
    RoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin PRIMARY KEY,
    Description VARCHAR(255) NOT NULL,

    CHECK (
        RoleCode IN ('Borrower', 'Lender', 'Administrator', 'Auditor')
    ),
    CHECK (CHAR_LENGTH(TRIM(Description)) > 0)
) ENGINE = InnoDB;

CREATE TABLE UserRole (
    UserRoleID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    UserID BIGINT UNSIGNED NOT NULL,
    RoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
    GrantedAt DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
    GrantedByUserID BIGINT UNSIGNED NULL,
    RevokedAt DATETIME(6) NULL,
    RevokedByUserID BIGINT UNSIGNED NULL,

    ActiveMarker TINYINT GENERATED ALWAYS AS (IF(RevokedAt IS NULL, 1, NULL)) VIRTUAL,

    UNIQUE (UserID, RoleCode, ActiveMarker),

    FOREIGN KEY (UserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (RoleCode)
        REFERENCES `Role` (RoleCode) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (GrantedByUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,
    FOREIGN KEY (RevokedByUserID)
        REFERENCES `User` (UserID) ON DELETE RESTRICT ON UPDATE RESTRICT,

    CHECK (
        (RevokedAt IS NULL AND RevokedByUserID IS NULL)
        OR (RevokedAt IS NOT NULL AND RevokedByUserID IS NOT NULL)
    ),
    CHECK (
        RevokedAt IS NULL OR RevokedAt >= GrantedAt
    )
) ENGINE = InnoDB;
