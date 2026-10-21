-- Fixed reference data. No passwords, accounts, or role assignments are seeded.
START TRANSACTION;

INSERT INTO `Role` (RoleCode, Description) VALUES
    ('Borrower', 'Request loans, inspect owned records, and make simulated repayments.'),
    ('Lender', 'Contribute to requests and monitor loans funded by the lender.'),
    ('Administrator', 'Review requests, manage accounts and roles, and append follow-up notes.'),
    ('Auditor', 'Read permitted reports and redacted history without changing business records.');

COMMIT;
