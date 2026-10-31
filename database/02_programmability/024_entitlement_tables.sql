CREATE TABLE Permission (
 PermissionCode VARCHAR(40) COLLATE utf8mb4_0900_bin PRIMARY KEY,
 BorrowerScope VARCHAR(16), LenderScope VARCHAR(16), AdministratorScope VARCHAR(16), AuditorScope VARCHAR(16),
 AllowRestricted BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;
CREATE TABLE RolePermission (
 RoleCode VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
 PermissionCode VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL,
 ScopeCode VARCHAR(16) COLLATE utf8mb4_0900_bin NOT NULL,
 PRIMARY KEY(RoleCode,PermissionCode),
 FOREIGN KEY(RoleCode) REFERENCES `Role`(RoleCode),
 FOREIGN KEY(PermissionCode) REFERENCES Permission(PermissionCode),
 CHECK(ScopeCode IN ('SELF','OWN','PARTICIPATING','ALL'))
) ENGINE=InnoDB;
