INSERT INTO Permission VALUES
('user.create',NULL,NULL,'ALL',NULL,0),('role.assign',NULL,NULL,'ALL',NULL,0),
('account.status',NULL,NULL,'ALL',NULL,0),('profile.edit','SELF',NULL,NULL,NULL,1),
('request.create','SELF',NULL,NULL,NULL,0),('request.edit','OWN',NULL,NULL,NULL,0),
('request.submit','OWN',NULL,NULL,NULL,0),('request.cancel','OWN',NULL,'ALL',NULL,1),
('request.read','OWN',NULL,'ALL','ALL',1),('loan.read','OWN','PARTICIPATING','ALL','ALL',1),
('permission.manage',NULL,NULL,'ALL',NULL,0);
INSERT INTO RolePermission
SELECT r.RoleCode,p.PermissionCode,CASE r.RoleClass WHEN 'Borrower' THEN p.BorrowerScope WHEN 'Lender' THEN p.LenderScope
 WHEN 'Administrator' THEN p.AdministratorScope ELSE p.AuditorScope END
FROM `Role` r CROSS JOIN Permission p WHERE CASE r.RoleClass WHEN 'Borrower' THEN p.BorrowerScope WHEN 'Lender' THEN p.LenderScope
 WHEN 'Administrator' THEN p.AdministratorScope ELSE p.AuditorScope END IS NOT NULL;
