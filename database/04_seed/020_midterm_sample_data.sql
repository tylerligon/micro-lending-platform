-- FICTIONAL historical fixture for the midterm, copied from sample-records.json.
-- Funded loans/payments/evaluations below are SEEDED, not executed workflows.
-- X'01' and 'fixture-not-a-login' are opaque constraint placeholders, NOT encryption
-- or usable credentials. No sign-in/application encryption is implemented by this seed.
-- Load only once into an empty dedicated midterm DB. Reruns must refuse existing data.
SET SESSION time_zone = '+00:00';
CREATE TEMPORARY TABLE midterm_seed_guard (Safe TINYINT NOT NULL CHECK (Safe = 1));
INSERT INTO midterm_seed_guard SELECT
    DATABASE() IN ('micro_lending_midterm_demo', 'micro_lending_midterm_test')
    AND (SELECT COUNT(*) FROM `Role`) = 4
    AND NOT EXISTS (SELECT 1 FROM `User`)
    AND NOT EXISTS (SELECT 1 FROM `UserRole`)
    AND NOT EXISTS (SELECT 1 FROM `BorrowerProfile`)
    AND NOT EXISTS (SELECT 1 FROM `LoanRequest`)
    AND NOT EXISTS (SELECT 1 FROM `RequestEvaluation`)
    AND NOT EXISTS (SELECT 1 FROM `OperationReceipt`)
    AND NOT EXISTS (SELECT 1 FROM `FundingCommitment`)
    AND NOT EXISTS (SELECT 1 FROM `Loan`)
    AND NOT EXISTS (SELECT 1 FROM `Installment`)
    AND NOT EXISTS (SELECT 1 FROM `Repayment`)
    AND NOT EXISTS (SELECT 1 FROM `RepaymentAllocation`)
    AND NOT EXISTS (SELECT 1 FROM `OversightNote`)
    AND NOT EXISTS (SELECT 1 FROM `AuditEvent`)
    AND NOT EXISTS (SELECT 1 FROM `AuditChange`);
DROP TEMPORARY TABLE midterm_seed_guard;
START TRANSACTION;

-- User: historical sample rows.
INSERT INTO `User` (`UserID`, `LoginName`, `DisplayName`, `PublicAlias`, `PrivateEmailCipher`, `PasswordHash`, `AccountStatus`, `CreatedAt`, `RowVersion`) VALUES
    (1, 'demo1', 'Fictional User 1', 'alias1', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 0),
    (2, 'demo2', 'Fictional User 2', 'alias2', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 0),
    (3, 'demo3', 'Fictional User 3', 'alias3', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 0),
    (4, 'demo4', 'Fictional User 4', 'alias4', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 0),
    (5, 'demo5', 'Fictional User 5', 'alias5', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 0),
    (6, 'demo6', 'Fictional User 6', 'alias6', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 0),
    (7, 'demo7', 'Fictional User 7', 'alias7', X'01', 'fixture-not-a-login', 'Active', '2026-07-01 00:00:00', 4);

-- UserRole: historical sample rows.
INSERT INTO `UserRole` (`UserRoleID`, `UserID`, `RoleCode`, `GrantedAt`, `GrantedByUserID`, `RevokedAt`, `RevokedByUserID`) VALUES
    (1, 1, 'Borrower', '2026-07-01 00:00:00', 5, NULL, NULL),
    (2, 2, 'Lender', '2026-07-01 00:00:00', 5, NULL, NULL),
    (3, 3, 'Lender', '2026-07-01 00:00:00', 5, NULL, NULL),
    (4, 4, 'Borrower', '2026-07-01 00:00:00', 5, NULL, NULL),
    (5, 5, 'Administrator', '2026-07-01 00:00:00', NULL, NULL, NULL),
    (6, 6, 'Auditor', '2026-07-01 00:00:00', 5, NULL, NULL),
    (7, 7, 'Borrower', '2026-07-01 00:00:00', 5, NULL, NULL),
    (8, 7, 'Lender', '2026-07-01 00:00:00', 5, NULL, NULL);

-- BorrowerProfile: historical sample rows.
INSERT INTO `BorrowerProfile` (`UserID`, `MonthlyIncomeCipher`, `ExternalObligationsCipher`, `UpdatedAt`, `RowVersion`) VALUES
    (1, X'01', X'01', '2026-07-02 00:00:00', 0),
    (4, X'01', X'01', '2026-07-02 00:00:00', 0),
    (7, X'01', X'01', '2026-07-02 00:00:00', 0);

-- LoanRequest: historical sample rows.
INSERT INTO `LoanRequest` (`RequestID`, `BorrowerID`, `Purpose`, `Principal`, `InstallmentCount`, `PolicyCode`, `RequestState`, `CreatedAt`, `SubmittedAt`, `FundingDeadlineAt`, `TerminalReason`, `RowVersion`, `SubmittedIncomeCipher`, `SubmittedObligationsCipher`) VALUES
    (101, 1, 'Fictional equipment request 101', 900.00, 3, 'D1', 'Funded', '2026-07-27 00:00:00', '2026-07-27 00:00:00', '2026-08-10 00:00:00', NULL, 4, X'01', X'01'),
    (102, 1, 'Fictional equipment request 102', 600.00, 3, 'D1', 'Funded', '2026-08-13 00:00:00', '2026-08-13 00:00:00', '2026-08-27 00:00:00', NULL, 4, X'01', X'01'),
    (103, 4, 'Fictional equipment request 103', 300.00, 3, 'D1', 'OpenFunding', '2026-10-18 00:00:00', '2026-10-18 00:00:00', '2026-11-01 00:00:00', NULL, 3, X'01', X'01'),
    (104, 7, 'Fictional equipment request 104', 300.00, 3, 'D1', 'OpenFunding', '2026-10-18 00:00:00', '2026-10-18 00:00:00', '2026-11-01 00:00:00', NULL, 3, X'01', X'01'),
    (105, 4, 'Fictional cancelled draft 105', 300.00, 3, NULL, 'Cancelled', '2026-07-08 10:00:00', NULL, NULL, 'Fictional draft no longer needed.', 1, NULL, NULL),
    (106, 7, 'Fictional cancelled draft 106', 300.00, 3, NULL, 'Cancelled', '2026-07-08 10:00:00', NULL, NULL, 'Fictional duplicate draft cancelled after review.', 1, NULL, NULL);

-- RequestEvaluation: historical sample rows.
INSERT INTO `RequestEvaluation` (`EvaluationID`, `RequestID`, `EvaluationKind`, `AttemptNumber`, `EvaluatedAt`, `PlatformBurdenCipher`, `NoDelinquencyPass`, `AffordabilityPass`, `CompletedAt`, `AdministratorID`, `Decision`, `Reason`, `DecidedAt`, `ContextID`) VALUES
    (1010, 101, 'Submission', 0, '2026-07-27 00:00:00', X'01', 1, 1, '2026-07-27 00:00:00', NULL, NULL, NULL, NULL, X'844215f95ed75660a231d042dfa2a90f'),
    (1011, 101, 'Review', 1, '2026-07-27 00:00:00', X'01', 1, 1, '2026-07-27 00:00:00', 5, 'Approve', 'D1 conditions pass.', '2026-07-27 00:00:00', X'c962045fcc4658fea0cfbfcd993353f9'),
    (1020, 102, 'Submission', 0, '2026-08-13 00:00:00', X'01', 1, 1, '2026-08-13 00:00:00', NULL, NULL, NULL, NULL, X'478f30bf43ca5a25b16f6796c8fa07a6'),
    (1021, 102, 'Review', 1, '2026-08-13 00:00:00', X'01', 1, 1, '2026-08-13 00:00:00', 5, 'Approve', 'D1 conditions pass.', '2026-08-13 00:00:00', X'48093fe95c3c54288f3381e2f6856aa0'),
    (1030, 103, 'Submission', 0, '2026-10-18 00:00:00', X'01', 1, 1, '2026-10-18 00:00:00', NULL, NULL, NULL, NULL, X'3bf59e0234025524a687727b4d0b90f1'),
    (1031, 103, 'Review', 1, '2026-10-18 00:00:00', X'01', 1, 1, '2026-10-18 00:00:00', 5, 'Approve', 'D1 conditions pass.', '2026-10-18 00:00:00', X'2f864f5198d055efac253c09e1b6f4ef'),
    (3000, 101, 'Funding', 1, '2026-08-01 00:00:00', X'01', 1, 1, '2026-08-01 00:00:00', NULL, NULL, NULL, NULL, X'be0412c24e64561e824859d1b2cc5dc0'),
    (3001, 101, 'Funding', 2, '2026-08-01 00:00:00', X'01', 1, 1, '2026-08-01 00:00:00', NULL, NULL, NULL, NULL, X'087339a29af6549499cbb0db659fed47'),
    (3002, 101, 'Funding', 3, '2026-08-01 00:00:00', X'01', 1, 1, '2026-08-01 00:00:00', NULL, NULL, NULL, NULL, X'bf2689230f755287a4f118baba103caa'),
    (3003, 102, 'Funding', 1, '2026-08-15 00:00:00', X'01', 1, 1, '2026-08-15 00:00:00', NULL, NULL, NULL, NULL, X'b11d7d2108675ae9910b08647bd147a3'),
    (3004, 103, 'Funding', 1, '2026-10-19 00:00:00', X'01', 1, 1, '2026-10-19 00:00:00', NULL, NULL, NULL, NULL, X'f7d6b39039835046baa38a574be79e7e'),
    (1040, 104, 'Submission', 0, '2026-10-18 00:00:00', X'01', 1, 1, '2026-10-18 00:00:00', NULL, NULL, NULL, NULL, X'56c41e76b087505cb0f5b439d84778f7'),
    (1041, 104, 'Review', 1, '2026-10-18 00:00:00', X'01', 1, 1, '2026-10-18 00:00:00', 5, 'Approve', 'D1 conditions pass.', '2026-10-18 00:00:00', X'e6af472bf89f562e9a129f0b4de1d8d6');

-- OperationReceipt: historical sample rows.
INSERT INTO `OperationReceipt` (`OperationID`, `CallerUserID`, `OperationReference`, `ActionCode`, `ReceiptSnapshot`) VALUES
    (1001, 2, 'fund-201', 'CommitFunding', CONCAT('201', CHAR(10), '{"operationID":"1001","commitmentID":"201","requestID":"101","amount":"300.00","commitmentState":"Pending","pendingTotal":"300.00","remainingAmount":"600.00","loanID":null}')),
    (1002, 2, 'fund-202', 'CommitFunding', CONCAT('201', CHAR(10), '{"operationID":"1002","commitmentID":"202","requestID":"101","amount":"200.00","commitmentState":"Pending","pendingTotal":"500.00","remainingAmount":"400.00","loanID":null}')),
    (1003, 3, 'fund-203', 'CommitFunding', CONCAT('201', CHAR(10), '{"operationID":"1003","commitmentID":"203","requestID":"101","amount":"400.00","commitmentState":"Applied","pendingTotal":"0.00","remainingAmount":"0.00","loanID":"501"}')),
    (1004, 3, 'fund-204', 'CommitFunding', CONCAT('201', CHAR(10), '{"operationID":"1004","commitmentID":"204","requestID":"102","amount":"600.00","commitmentState":"Applied","pendingTotal":"0.00","remainingAmount":"0.00","loanID":"502"}')),
    (1005, 2, 'fund-205', 'CommitFunding', CONCAT('201', CHAR(10), '{"operationID":"1005","commitmentID":"205","requestID":"103","amount":"100.00","commitmentState":"Pending","pendingTotal":"100.00","remainingAmount":"200.00","loanID":null}')),
    (2001, 1, 'pay-501-1', 'PostRepayment', CONCAT('201', CHAR(10), '{"operationID":"2001","loanID":"501","repaymentNumber":1,"amount":"100.00","allocations":[{"installmentNumber":1,"amount":"100.00"}],"outstandingAfter":"800.00","loanState":"Active"}')),
    (2002, 1, 'pay-501-2', 'PostRepayment', CONCAT('201', CHAR(10), '{"operationID":"2002","loanID":"501","repaymentNumber":2,"amount":"250.00","allocations":[{"installmentNumber":1,"amount":"200.00"},{"installmentNumber":2,"amount":"50.00"}],"outstandingAfter":"550.00","loanState":"Active"}')),
    (2003, 1, 'pay-502-1', 'PostRepayment', CONCAT('201', CHAR(10), '{"operationID":"2003","loanID":"502","repaymentNumber":1,"amount":"200.00","allocations":[{"installmentNumber":1,"amount":"200.00"}],"outstandingAfter":"400.00","loanState":"Active"}')),
    (2004, 1, 'pay-502-2', 'PostRepayment', CONCAT('201', CHAR(10), '{"operationID":"2004","loanID":"502","repaymentNumber":2,"amount":"200.00","allocations":[{"installmentNumber":2,"amount":"200.00"}],"outstandingAfter":"200.00","loanState":"Active"}'));

-- FundingCommitment: historical sample rows.
INSERT INTO `FundingCommitment` (`CommitmentID`, `RequestID`, `OperationID`, `EvaluationID`, `Amount`, `CommitmentState`, `CreatedAt`, `AppliedAt`, `ReleasedAt`) VALUES
    (201, 101, 1001, 3000, 300.00, 'Applied', '2026-08-01 00:00:00', '2026-08-01 00:00:00', NULL),
    (202, 101, 1002, 3001, 200.00, 'Applied', '2026-08-01 00:00:00', '2026-08-01 00:00:00', NULL),
    (203, 101, 1003, 3002, 400.00, 'Applied', '2026-08-01 00:00:00', '2026-08-01 00:00:00', NULL),
    (204, 102, 1004, 3003, 600.00, 'Applied', '2026-08-15 00:00:00', '2026-08-15 00:00:00', NULL),
    (205, 103, 1005, 3004, 100.00, 'Pending', '2026-10-19 00:00:00', NULL, NULL);

-- Loan: historical sample rows.
INSERT INTO `Loan` (`LoanID`, `RequestID`, `ActivatedAt`, `LoanState`, `CompletedAt`, `ObservedCondition`, `LastEvaluatedAt`) VALUES
    (501, 101, '2026-08-01 00:00:00', 'Active', NULL, 'Delinquent', '2026-10-19 12:00:00'),
    (502, 102, '2026-08-15 00:00:00', 'Active', NULL, 'Current', '2026-10-19 12:00:00');

-- Installment: historical sample rows.
INSERT INTO `Installment` (`LoanID`, `InstallmentNumber`, `DueDate`, `ScheduledPrincipal`) VALUES
    (501, 1, '2026-09-01', 300.00),
    (501, 2, '2026-10-01', 300.00),
    (501, 3, '2026-11-01', 300.00),
    (502, 1, '2026-09-15', 200.00),
    (502, 2, '2026-10-15', 200.00),
    (502, 3, '2026-11-15', 200.00);

-- Repayment: historical sample rows.
INSERT INTO `Repayment` (`LoanID`, `RepaymentNumber`, `OperationID`, `Amount`, `PostedAt`) VALUES
    (501, 1, 2001, 100.00, '2026-09-01 00:00:00'),
    (501, 2, 2002, 250.00, '2026-10-10 00:00:00'),
    (502, 1, 2003, 200.00, '2026-09-15 00:00:00'),
    (502, 2, 2004, 200.00, '2026-10-15 00:00:00');

-- RepaymentAllocation: historical sample rows.
INSERT INTO `RepaymentAllocation` (`LoanID`, `RepaymentNumber`, `InstallmentNumber`, `AllocatedPrincipal`) VALUES
    (501, 1, 1, 100.00),
    (501, 2, 1, 200.00),
    (501, 2, 2, 50.00),
    (502, 1, 1, 200.00),
    (502, 2, 2, 200.00);

-- OversightNote: historical sample rows.
INSERT INTO `OversightNote` (`NoteID`, `RequestID`, `LoanID`, `AdministratorID`, `CreatedAt`, `NoteText`, `CorrectsNoteID`) VALUES
    (901, NULL, 501, 5, '2026-10-19 12:00:00', 'Follow up on overdue principal.', NULL),
    (902, NULL, 501, 5, '2026-10-19 12:10:00', 'Correction: use the current report amount of 250.00.', 901);

-- AuditEvent: historical sample rows.
INSERT INTO `AuditEvent` (`AuditEventID`, `OccurredAt`, `EventType`, `Outcome`, `ActorUserID`, `ActingRoleCode`, `ServiceActor`, `InitiatingUserID`, `TechnicalAccount`, `SubjectType`, `SubjectKey`, `ContextID`, `OperationID`, `AttemptedOperationReference`, `ReasonCode`) VALUES
    (801, '2026-07-01 00:00:00', 'UserCreated', 'Success', NULL, NULL, 'Bootstrap', NULL, 'fixture_builder@localhost', 'User', '5', X'85ef3299bdbd5ff483c6131dde440b48', NULL, NULL, NULL),
    (802, '2026-07-01 00:00:00', 'RoleGranted', 'Success', NULL, NULL, 'Bootstrap', NULL, 'fixture_builder@localhost', 'UserRole', '5', X'337344922e2d531789d20c02484639be', NULL, NULL, NULL),
    (803, '2026-07-01 00:00:00', 'UserCreated', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '1', X'f4d37f4a96b05c8e9f75a4480921e34a', NULL, NULL, NULL),
    (804, '2026-07-01 00:00:00', 'UserCreated', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '2', X'bfb13bada9e8512b804f34ce9dd0de17', NULL, NULL, NULL),
    (805, '2026-07-01 00:00:00', 'UserCreated', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '3', X'ed5e7f6e70d6588e924264e962c6a4a7', NULL, NULL, NULL),
    (806, '2026-07-01 00:00:00', 'UserCreated', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '4', X'1de78ebbeea853ef84241ab63f160c2d', NULL, NULL, NULL),
    (807, '2026-07-01 00:00:00', 'UserCreated', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '6', X'c50d0a4f45885898ad5886f881f50553', NULL, NULL, NULL),
    (808, '2026-07-01 00:00:00', 'UserCreated', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '7', X'807d38095a9d5205a767785add07d257', NULL, NULL, NULL),
    (809, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '1', X'5efd91f34c5f5a12815367149396add8', NULL, NULL, NULL),
    (810, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '2', X'd4e7886c563c507d9a251225dfdb0163', NULL, NULL, NULL),
    (811, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '3', X'87a412cd91065019a07b760d5340e51c', NULL, NULL, NULL),
    (812, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '4', X'219f069c76c6572bae7eb3b0df4ace9b', NULL, NULL, NULL),
    (813, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '6', X'6057ca87ccae59c4a6732de13326bc2e', NULL, NULL, NULL),
    (814, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '7', X'001d4e0e39555543ba6c208d79c1fc79', NULL, NULL, NULL),
    (815, '2026-07-01 00:00:00', 'RoleGranted', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'UserRole', '8', X'9754745fcdaa5d88a0bdfe0f78672e35', NULL, NULL, NULL),
    (816, '2026-07-02 00:00:00', 'ProfileSaved', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'BorrowerProfile', '1', X'2aff827fcef851b29393c20d706c5d03', NULL, NULL, NULL),
    (817, '2026-07-02 00:00:00', 'ProfileSaved', 'Success', 4, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'BorrowerProfile', '4', X'2271a671d43052afaddd4d4182a4565b', NULL, NULL, NULL),
    (818, '2026-07-02 00:00:00', 'ProfileSaved', 'Success', 7, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'BorrowerProfile', '7', X'86fa6c80d8ff56679ba3ea9361cfc49e', NULL, NULL, NULL),
    (854, '2026-07-03 12:00:00', 'AccountStatusChanged', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '7', X'f36af7c0ca985baf901f523a4ff47cb9', NULL, NULL, 'ADMIN_DECISION'),
    (855, '2026-07-04 12:00:00', 'AccountStatusChanged', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '7', X'2dd0e58f84fc519aa6716ec543d84afd', NULL, NULL, 'ADMIN_DECISION'),
    (856, '2026-07-05 12:00:00', 'AccountStatusChanged', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '7', X'46a4c3f6632556e2940be302f5dabf58', NULL, NULL, 'ADMIN_DECISION'),
    (857, '2026-07-06 12:00:00', 'AccountStatusChanged', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'User', '7', X'91eb90f47c0955a687223f9370882e5a', NULL, NULL, 'ADMIN_DECISION'),
    (858, '2026-07-08 10:00:00', 'RequestSaved', 'Success', 4, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '105', X'0089552c29495a6d9f8ccb6dd7436073', NULL, NULL, NULL),
    (860, '2026-07-08 10:00:00', 'RequestSaved', 'Success', 7, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '106', X'2437194fb2c9596491b357fb238d770b', NULL, NULL, NULL),
    (859, '2026-07-08 11:00:00', 'RequestCancelled', 'Success', 4, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '105', X'b96f5424d25d5ebb8a923b4b512c0f80', NULL, NULL, 'BORROWER_CANCELLED'),
    (861, '2026-07-08 11:00:00', 'RequestCancelled', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '106', X'4bf7bc7a5b315dadaf6629754a922e5b', NULL, NULL, 'ADMIN_DECISION'),
    (819, '2026-07-27 00:00:00', 'RequestSaved', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '101', X'bca0c19ecafc54ebb9d540c5c342117c', NULL, NULL, NULL),
    (820, '2026-07-27 00:00:00', 'RequestSubmitted', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '101', X'844215f95ed75660a231d042dfa2a90f', NULL, NULL, NULL),
    (821, '2026-07-27 00:00:00', 'AssessmentCompleted', 'Success', NULL, NULL, 'Assessment', NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1010', X'a1fc067cfa175dbaba9f08455ae1bafc', NULL, NULL, NULL),
    (822, '2026-07-27 00:00:00', 'ReviewApproved', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1011', X'c962045fcc4658fea0cfbfcd993353f9', NULL, NULL, 'ADMIN_DECISION'),
    (823, '2026-08-01 00:00:00', 'CommitmentAccepted', 'Success', 2, 'Lender', NULL, NULL, 'fixture_builder@localhost', 'FundingCommitment', '201', X'be0412c24e64561e824859d1b2cc5dc0', 1001, NULL, NULL),
    (824, '2026-08-01 00:00:00', 'CommitmentAccepted', 'Success', 2, 'Lender', NULL, NULL, 'fixture_builder@localhost', 'FundingCommitment', '202', X'087339a29af6549499cbb0db659fed47', 1002, NULL, NULL),
    (825, '2026-08-01 00:00:00', 'CommitmentAccepted', 'Success', 3, 'Lender', NULL, NULL, 'fixture_builder@localhost', 'FundingCommitment', '203', X'bf2689230f755287a4f118baba103caa', 1003, NULL, NULL),
    (826, '2026-08-01 00:00:00', 'CommitmentApplied', 'Success', NULL, NULL, 'Activation', 3, 'fixture_builder@localhost', 'FundingCommitment', '201', X'bf2689230f755287a4f118baba103caa', 1003, NULL, NULL),
    (827, '2026-08-01 00:00:00', 'CommitmentApplied', 'Success', NULL, NULL, 'Activation', 3, 'fixture_builder@localhost', 'FundingCommitment', '202', X'bf2689230f755287a4f118baba103caa', 1003, NULL, NULL),
    (828, '2026-08-01 00:00:00', 'CommitmentApplied', 'Success', NULL, NULL, 'Activation', 3, 'fixture_builder@localhost', 'FundingCommitment', '203', X'bf2689230f755287a4f118baba103caa', 1003, NULL, NULL),
    (829, '2026-08-01 00:00:00', 'LoanActivated', 'Success', NULL, NULL, 'Activation', 3, 'fixture_builder@localhost', 'Loan', '501', X'bf2689230f755287a4f118baba103caa', 1003, NULL, NULL),
    (830, '2026-08-13 00:00:00', 'RequestSaved', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '102', X'c1432c98029759e9bf114c3fc07174c4', NULL, NULL, NULL),
    (831, '2026-08-13 00:00:00', 'RequestSubmitted', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '102', X'478f30bf43ca5a25b16f6796c8fa07a6', NULL, NULL, NULL),
    (832, '2026-08-13 00:00:00', 'AssessmentCompleted', 'Success', NULL, NULL, 'Assessment', NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1020', X'93bfd907360c5715b2a4f578f3a49ac7', NULL, NULL, NULL),
    (833, '2026-08-13 00:00:00', 'ReviewApproved', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1021', X'48093fe95c3c54288f3381e2f6856aa0', NULL, NULL, 'ADMIN_DECISION'),
    (834, '2026-08-15 00:00:00', 'CommitmentAccepted', 'Success', 3, 'Lender', NULL, NULL, 'fixture_builder@localhost', 'FundingCommitment', '204', X'b11d7d2108675ae9910b08647bd147a3', 1004, NULL, NULL),
    (835, '2026-08-15 00:00:00', 'CommitmentApplied', 'Success', NULL, NULL, 'Activation', 3, 'fixture_builder@localhost', 'FundingCommitment', '204', X'b11d7d2108675ae9910b08647bd147a3', 1004, NULL, NULL),
    (836, '2026-08-15 00:00:00', 'LoanActivated', 'Success', NULL, NULL, 'Activation', 3, 'fixture_builder@localhost', 'Loan', '502', X'b11d7d2108675ae9910b08647bd147a3', 1004, NULL, NULL),
    (837, '2026-09-01 00:00:00', 'RepaymentPosted', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'Repayment', '501/1', X'3e4e316e0dc05ee18b17d60660af6f3b', 2001, NULL, NULL),
    (838, '2026-09-02 00:00:00', 'DelinquencyChanged', 'Success', NULL, NULL, 'Delinquency', NULL, 'fixture_builder@localhost', 'Loan', '501', X'8240b4113fab58d89a5b75a0a8d9418e', NULL, NULL, NULL),
    (839, '2026-09-15 00:00:00', 'RepaymentPosted', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'Repayment', '502/1', X'2e8bf8079e8b556497dda91c093e9ac7', 2003, NULL, NULL),
    (840, '2026-10-10 00:00:00', 'RepaymentPosted', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'Repayment', '501/2', X'e8cbfe1f3e365d37b21aaabb90be0cbd', 2002, NULL, NULL),
    (841, '2026-10-15 00:00:00', 'RepaymentPosted', 'Success', 1, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'Repayment', '502/2', X'2f9e62f018b95a369035b239f6e63b21', 2004, NULL, NULL),
    (842, '2026-10-18 00:00:00', 'RequestSaved', 'Success', 4, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '103', X'd7a409a937ed553387125a1ba2b4ac21', NULL, NULL, NULL),
    (843, '2026-10-18 00:00:00', 'RequestSaved', 'Success', 7, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '104', X'6e0e49cdd40a538cad01de0c66c24cd2', NULL, NULL, NULL),
    (844, '2026-10-18 00:00:00', 'RequestSubmitted', 'Success', 4, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '103', X'3bf59e0234025524a687727b4d0b90f1', NULL, NULL, NULL),
    (845, '2026-10-18 00:00:00', 'RequestSubmitted', 'Success', 7, 'Borrower', NULL, NULL, 'fixture_builder@localhost', 'LoanRequest', '104', X'56c41e76b087505cb0f5b439d84778f7', NULL, NULL, NULL),
    (846, '2026-10-18 00:00:00', 'AssessmentCompleted', 'Success', NULL, NULL, 'Assessment', NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1030', X'8c914a0e5e69534db806a6cd12fd02ea', NULL, NULL, NULL),
    (847, '2026-10-18 00:00:00', 'AssessmentCompleted', 'Success', NULL, NULL, 'Assessment', NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1040', X'f02f17c766355f91b920f133bdb071b7', NULL, NULL, NULL),
    (848, '2026-10-18 00:00:00', 'ReviewApproved', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1031', X'2f864f5198d055efac253c09e1b6f4ef', NULL, NULL, 'ADMIN_DECISION'),
    (849, '2026-10-18 00:00:00', 'ReviewApproved', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'RequestEvaluation', '1041', X'e6af472bf89f562e9a129f0b4de1d8d6', NULL, NULL, 'ADMIN_DECISION'),
    (850, '2026-10-19 00:00:00', 'CommitmentAccepted', 'Success', 2, 'Lender', NULL, NULL, 'fixture_builder@localhost', 'FundingCommitment', '205', X'f7d6b39039835046baa38a574be79e7e', 1005, NULL, NULL),
    (851, '2026-10-19 12:00:00', 'NoteAppended', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'OversightNote', '901', X'a7cc057a0bdf510fb2ab4bfc093a47b8', NULL, NULL, NULL),
    (852, '2026-10-19 12:05:00', 'AttemptRejected', 'Denied', 7, 'Lender', NULL, NULL, 'fixture_builder@localhost', 'Attempt', 'CommitFunding/104', X'a8ff606c272b580b9ba38272dd9ad3fd', NULL, 'dual-self-test', 'SELF_FUNDING'),
    (853, '2026-10-19 12:10:00', 'NoteAppended', 'Success', 5, 'Administrator', NULL, NULL, 'fixture_builder@localhost', 'OversightNote', '902', X'a838540e8ff95308bccce6659dc31bd5', NULL, NULL, NULL);

-- AuditChange: historical sample rows.
INSERT INTO `AuditChange` (`AuditEventID`, `FieldName`, `OldValue`, `NewValue`) VALUES
    (801, 'AccountStatus', NULL, 'Active'),
    (801, 'PasswordHash', NULL, NULL),
    (801, 'PrivateEmailCipher', NULL, NULL),
    (802, 'RoleCode', NULL, 'Administrator'),
    (802, 'UserID', NULL, '5'),
    (803, 'AccountStatus', NULL, 'Active'),
    (803, 'PasswordHash', NULL, NULL),
    (803, 'PrivateEmailCipher', NULL, NULL),
    (804, 'AccountStatus', NULL, 'Active'),
    (804, 'PasswordHash', NULL, NULL),
    (804, 'PrivateEmailCipher', NULL, NULL),
    (805, 'AccountStatus', NULL, 'Active'),
    (805, 'PasswordHash', NULL, NULL),
    (805, 'PrivateEmailCipher', NULL, NULL),
    (806, 'AccountStatus', NULL, 'Active'),
    (806, 'PasswordHash', NULL, NULL),
    (806, 'PrivateEmailCipher', NULL, NULL),
    (807, 'AccountStatus', NULL, 'Active'),
    (807, 'PasswordHash', NULL, NULL),
    (807, 'PrivateEmailCipher', NULL, NULL),
    (808, 'AccountStatus', NULL, 'Active'),
    (808, 'PasswordHash', NULL, NULL),
    (808, 'PrivateEmailCipher', NULL, NULL),
    (809, 'RoleCode', NULL, 'Borrower'),
    (809, 'UserID', NULL, '1'),
    (810, 'RoleCode', NULL, 'Lender'),
    (810, 'UserID', NULL, '2'),
    (811, 'RoleCode', NULL, 'Lender'),
    (811, 'UserID', NULL, '3'),
    (812, 'RoleCode', NULL, 'Borrower'),
    (812, 'UserID', NULL, '4'),
    (813, 'RoleCode', NULL, 'Auditor'),
    (813, 'UserID', NULL, '6'),
    (814, 'RoleCode', NULL, 'Borrower'),
    (814, 'UserID', NULL, '7'),
    (815, 'RoleCode', NULL, 'Lender'),
    (815, 'UserID', NULL, '7'),
    (816, 'ExternalObligationsCipher', NULL, NULL),
    (816, 'MonthlyIncomeCipher', NULL, NULL),
    (817, 'ExternalObligationsCipher', NULL, NULL),
    (817, 'MonthlyIncomeCipher', NULL, NULL),
    (818, 'ExternalObligationsCipher', NULL, NULL),
    (818, 'MonthlyIncomeCipher', NULL, NULL),
    (819, 'InstallmentCount', NULL, '3'),
    (819, 'Principal', NULL, '900.00'),
    (819, 'Purpose', NULL, 'Fictional equipment request 101'),
    (819, 'RequestState', NULL, 'Draft'),
    (820, 'EvaluationID', NULL, '1010'),
    (820, 'PolicyCode', NULL, 'D1'),
    (820, 'RequestState', 'Draft', 'Submitted'),
    (820, 'SubmittedIncomeCipher', NULL, NULL),
    (820, 'SubmittedObligationsCipher', NULL, NULL),
    (821, 'AffordabilityPass', NULL, '1'),
    (821, 'NoDelinquencyPass', NULL, '1'),
    (821, 'RequestID', NULL, '101'),
    (821, 'RequestState', 'Submitted', 'PendingReview'),
    (821, 'Result', NULL, 'Pass'),
    (822, 'Decision', NULL, 'Approve'),
    (822, 'FundingDeadlineAt', NULL, '2026-08-10T00:00:00Z'),
    (822, 'RequestID', NULL, '101'),
    (822, 'RequestState', 'PendingReview', 'OpenFunding'),
    (823, 'Amount', NULL, '300.00'),
    (823, 'CommitmentState', NULL, 'Pending'),
    (823, 'EvaluationID', NULL, '3000'),
    (823, 'PendingTotal', NULL, '300.00'),
    (823, 'RequestID', NULL, '101'),
    (824, 'Amount', NULL, '200.00'),
    (824, 'CommitmentState', NULL, 'Pending'),
    (824, 'EvaluationID', NULL, '3001'),
    (824, 'PendingTotal', NULL, '500.00'),
    (824, 'RequestID', NULL, '101'),
    (825, 'Amount', NULL, '400.00'),
    (825, 'CommitmentState', NULL, 'Pending'),
    (825, 'EvaluationID', NULL, '3002'),
    (825, 'PendingTotal', NULL, '900.00'),
    (825, 'RequestID', NULL, '101'),
    (826, 'AppliedAt', NULL, '2026-08-01T00:00:00Z'),
    (826, 'CommitmentState', 'Pending', 'Applied'),
    (826, 'LoanID', NULL, '501'),
    (827, 'AppliedAt', NULL, '2026-08-01T00:00:00Z'),
    (827, 'CommitmentState', 'Pending', 'Applied'),
    (827, 'LoanID', NULL, '501'),
    (828, 'AppliedAt', NULL, '2026-08-01T00:00:00Z'),
    (828, 'CommitmentState', 'Pending', 'Applied'),
    (828, 'LoanID', NULL, '501'),
    (829, 'ActivatedAt', NULL, '2026-08-01T00:00:00Z'),
    (829, 'InstallmentCount', NULL, '3'),
    (829, 'LoanState', NULL, 'Active'),
    (829, 'Principal', NULL, '900.00'),
    (829, 'RequestID', NULL, '101'),
    (829, 'RequestState', 'OpenFunding', 'Funded'),
    (830, 'InstallmentCount', NULL, '3'),
    (830, 'Principal', NULL, '600.00'),
    (830, 'Purpose', NULL, 'Fictional equipment request 102'),
    (830, 'RequestState', NULL, 'Draft'),
    (831, 'EvaluationID', NULL, '1020'),
    (831, 'PolicyCode', NULL, 'D1'),
    (831, 'RequestState', 'Draft', 'Submitted'),
    (831, 'SubmittedIncomeCipher', NULL, NULL),
    (831, 'SubmittedObligationsCipher', NULL, NULL),
    (832, 'AffordabilityPass', NULL, '1'),
    (832, 'NoDelinquencyPass', NULL, '1'),
    (832, 'RequestID', NULL, '102'),
    (832, 'RequestState', 'Submitted', 'PendingReview'),
    (832, 'Result', NULL, 'Pass'),
    (833, 'Decision', NULL, 'Approve'),
    (833, 'FundingDeadlineAt', NULL, '2026-08-27T00:00:00Z'),
    (833, 'RequestID', NULL, '102'),
    (833, 'RequestState', 'PendingReview', 'OpenFunding'),
    (834, 'Amount', NULL, '600.00'),
    (834, 'CommitmentState', NULL, 'Pending'),
    (834, 'EvaluationID', NULL, '3003'),
    (834, 'PendingTotal', NULL, '600.00'),
    (834, 'RequestID', NULL, '102'),
    (835, 'AppliedAt', NULL, '2026-08-15T00:00:00Z'),
    (835, 'CommitmentState', 'Pending', 'Applied'),
    (835, 'LoanID', NULL, '502'),
    (836, 'ActivatedAt', NULL, '2026-08-15T00:00:00Z'),
    (836, 'InstallmentCount', NULL, '3'),
    (836, 'LoanState', NULL, 'Active'),
    (836, 'Principal', NULL, '600.00'),
    (836, 'RequestID', NULL, '102'),
    (836, 'RequestState', 'OpenFunding', 'Funded'),
    (837, 'AllocationCount', NULL, '1'),
    (837, 'Amount', NULL, '100.00'),
    (837, 'OutstandingAfter', NULL, '800.00'),
    (837, 'OutstandingBefore', NULL, '900.00'),
    (838, 'LastEvaluatedAt', '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z'),
    (838, 'ObservedCondition', 'Current', 'Delinquent'),
    (838, 'OldestOverdueDueDate', NULL, '2026-09-01'),
    (838, 'OverduePrincipal', '0.00', '200.00'),
    (839, 'AllocationCount', NULL, '1'),
    (839, 'Amount', NULL, '200.00'),
    (839, 'OutstandingAfter', NULL, '400.00'),
    (839, 'OutstandingBefore', NULL, '600.00'),
    (840, 'AllocationCount', NULL, '2'),
    (840, 'Amount', NULL, '250.00'),
    (840, 'OutstandingAfter', NULL, '550.00'),
    (840, 'OutstandingBefore', NULL, '800.00'),
    (841, 'AllocationCount', NULL, '1'),
    (841, 'Amount', NULL, '200.00'),
    (841, 'OutstandingAfter', NULL, '200.00'),
    (841, 'OutstandingBefore', NULL, '400.00'),
    (842, 'InstallmentCount', NULL, '3'),
    (842, 'Principal', NULL, '300.00'),
    (842, 'Purpose', NULL, 'Fictional equipment request 103'),
    (842, 'RequestState', NULL, 'Draft'),
    (843, 'InstallmentCount', NULL, '3'),
    (843, 'Principal', NULL, '300.00'),
    (843, 'Purpose', NULL, 'Fictional equipment request 104'),
    (843, 'RequestState', NULL, 'Draft'),
    (844, 'EvaluationID', NULL, '1030'),
    (844, 'PolicyCode', NULL, 'D1'),
    (844, 'RequestState', 'Draft', 'Submitted'),
    (844, 'SubmittedIncomeCipher', NULL, NULL),
    (844, 'SubmittedObligationsCipher', NULL, NULL),
    (845, 'EvaluationID', NULL, '1040'),
    (845, 'PolicyCode', NULL, 'D1'),
    (845, 'RequestState', 'Draft', 'Submitted'),
    (845, 'SubmittedIncomeCipher', NULL, NULL),
    (845, 'SubmittedObligationsCipher', NULL, NULL),
    (846, 'AffordabilityPass', NULL, '1'),
    (846, 'NoDelinquencyPass', NULL, '1'),
    (846, 'RequestID', NULL, '103'),
    (846, 'RequestState', 'Submitted', 'PendingReview'),
    (846, 'Result', NULL, 'Pass'),
    (847, 'AffordabilityPass', NULL, '1'),
    (847, 'NoDelinquencyPass', NULL, '1'),
    (847, 'RequestID', NULL, '104'),
    (847, 'RequestState', 'Submitted', 'PendingReview'),
    (847, 'Result', NULL, 'Pass'),
    (848, 'Decision', NULL, 'Approve'),
    (848, 'FundingDeadlineAt', NULL, '2026-11-01T00:00:00Z'),
    (848, 'RequestID', NULL, '103'),
    (848, 'RequestState', 'PendingReview', 'OpenFunding'),
    (849, 'Decision', NULL, 'Approve'),
    (849, 'FundingDeadlineAt', NULL, '2026-11-01T00:00:00Z'),
    (849, 'RequestID', NULL, '104'),
    (849, 'RequestState', 'PendingReview', 'OpenFunding'),
    (850, 'Amount', NULL, '100.00'),
    (850, 'CommitmentState', NULL, 'Pending'),
    (850, 'EvaluationID', NULL, '3004'),
    (850, 'PendingTotal', NULL, '100.00'),
    (850, 'RequestID', NULL, '103'),
    (851, 'CorrectsNoteID', NULL, NULL),
    (851, 'LoanID', NULL, '501'),
    (853, 'CorrectsNoteID', NULL, '901'),
    (853, 'LoanID', NULL, '501'),
    (854, 'AccountStatus', 'Active', 'Restricted'),
    (854, 'StatusReason', NULL, 'Fictional administrative review pending.'),
    (855, 'AccountStatus', 'Restricted', 'Active'),
    (855, 'StatusReason', NULL, 'Fictional review completed; restriction cleared.'),
    (856, 'AccountStatus', 'Active', 'Inactive'),
    (856, 'StatusReason', NULL, 'Fictional account closure requested; no live participation.'),
    (857, 'AccountStatus', 'Inactive', 'Active'),
    (857, 'StatusReason', NULL, 'Fictional account reopened after administrative review.'),
    (858, 'InstallmentCount', NULL, '3'),
    (858, 'Principal', NULL, '300.00'),
    (858, 'Purpose', NULL, 'Fictional cancelled draft 105'),
    (858, 'RequestState', NULL, 'Draft'),
    (859, 'RequestState', 'Draft', 'Cancelled'),
    (859, 'TerminalReason', NULL, 'Fictional draft no longer needed.'),
    (860, 'InstallmentCount', NULL, '3'),
    (860, 'Principal', NULL, '300.00'),
    (860, 'Purpose', NULL, 'Fictional cancelled draft 106'),
    (860, 'RequestState', NULL, 'Draft'),
    (861, 'RequestState', 'Draft', 'Cancelled'),
    (861, 'TerminalReason', NULL, 'Fictional duplicate draft cancelled after review.');
COMMIT;
-- Expected fixture table counts (Role already contains 4): {"AuditChange": 208, "AuditEvent": 61, "BorrowerProfile": 3, "FundingCommitment": 5, "Installment": 6, "Loan": 2, "LoanRequest": 6, "OperationReceipt": 9, "OversightNote": 2, "Repayment": 4, "RepaymentAllocation": 5, "RequestEvaluation": 13, "User": 7, "UserRole": 8}
