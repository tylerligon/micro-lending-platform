-- Midterm administrative/reporting examples, NOT final RQ-01--08 authorization.
-- Explicit projections omit contact data and encrypted financial inputs.
-- DEFINER permits a technical reader to read these views without base-table grants.
CREATE SQL SECURITY DEFINER VIEW v_borrower_requests AS
SELECT r.BorrowerID, u.PublicAlias, r.RequestID, r.Purpose, r.Principal,
    r.InstallmentCount, r.RequestState, r.RowVersion, r.CreatedAt, r.SubmittedAt
FROM LoanRequest r JOIN `User` u ON u.UserID = r.BorrowerID;

-- Aggregate commitments BEFORE joining: one row per request, regardless of repeats.
-- RemainingToFund is arithmetic, not eligibility; terminal requests cannot receive funds.
CREATE SQL SECURITY DEFINER VIEW v_request_funding_progress AS
SELECT r.RequestID, r.BorrowerID, r.RequestState, r.Principal,
    COALESCE(c.PendingPrincipal, 0) AS PendingPrincipal,
    COALESCE(c.AppliedPrincipal, 0) AS AppliedPrincipal,
    COALESCE(c.ReleasedPrincipal, 0) AS ReleasedPrincipal,
    r.Principal - COALESCE(c.PendingPrincipal, 0) - COALESCE(c.AppliedPrincipal, 0) AS RemainingToFund
FROM LoanRequest r LEFT JOIN (
    SELECT RequestID,
        SUM(CASE WHEN CommitmentState = 'Pending' THEN Amount ELSE 0 END) AS PendingPrincipal,
        SUM(CASE WHEN CommitmentState = 'Applied' THEN Amount ELSE 0 END) AS AppliedPrincipal,
        SUM(CASE WHEN CommitmentState = 'Released' THEN Amount ELSE 0 END) AS ReleasedPrincipal
    FROM FundingCommitment GROUP BY RequestID
) c ON c.RequestID = r.RequestID;

-- Balances from allocations, with one row per loan. No participation join to multiply totals.
CREATE SQL SECURITY DEFINER VIEW v_loan_balances AS
SELECT l.LoanID, l.RequestID, r.BorrowerID, l.LoanState,
    COALESCE(i.ScheduledPrincipal, 0) AS ScheduledPrincipal,
    COALESCE(i.ScheduledPrincipal - i.OutstandingPrincipal, 0) AS AllocatedPrincipal,
    COALESCE(i.OutstandingPrincipal, 0) AS OutstandingPrincipal
FROM Loan l JOIN LoanRequest r ON r.RequestID = l.RequestID
LEFT JOIN (
    SELECT LoanID, SUM(ScheduledPrincipal) AS ScheduledPrincipal,
        SUM(RemainingPrincipal) AS OutstandingPrincipal
    FROM Installment JOIN v_installment_remaining USING (LoanID, InstallmentNumber, DueDate)
    GROUP BY LoanID
) i ON i.LoanID = l.LoanID;
