-- Readable query definitions. This view calculates remaining installment principal.
DELIMITER //

CREATE SQL SECURITY INVOKER VIEW v_installment_remaining AS
SELECT i.LoanID, i.InstallmentNumber, i.DueDate,
    i.ScheduledPrincipal - COALESCE(a.Paid, 0) AS RemainingPrincipal
FROM Installment i LEFT JOIN (
    SELECT LoanID, InstallmentNumber, SUM(AllocatedPrincipal) AS Paid
    FROM RepaymentAllocation GROUP BY LoanID, InstallmentNumber
) a ON a.LoanID = i.LoanID AND a.InstallmentNumber = i.InstallmentNumber //

DELIMITER ;
