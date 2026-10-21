-- Protect request identity and freeze terms/snapshots after Draft (BR-06).
-- Later lifecycle rules and the repayment completion trigger remain pending.
DELIMITER //

CREATE TRIGGER trg_request_frozen_terms BEFORE UPDATE ON LoanRequest
FOR EACH ROW
BEGIN
    IF NOT (NEW.BorrowerID <=> OLD.BorrowerID) OR NOT (NEW.RequestID <=> OLD.RequestID)
       OR NOT (NEW.CreatedAt <=> OLD.CreatedAt) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Request identity is immutable';
    END IF;
    IF OLD.RequestState <> 'Draft' AND (
        NEW.RequestState = 'Draft' OR NOT (BINARY NEW.Purpose <=> BINARY OLD.Purpose)
        OR NOT (NEW.Principal <=> OLD.Principal) OR NOT (NEW.InstallmentCount <=> OLD.InstallmentCount)
        OR NOT (NEW.PolicyCode <=> OLD.PolicyCode) OR NOT (NEW.SubmittedAt <=> OLD.SubmittedAt)
        OR NOT (NEW.SubmittedIncomeCipher <=> OLD.SubmittedIncomeCipher)
        OR NOT (NEW.SubmittedObligationsCipher <=> OLD.SubmittedObligationsCipher)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Submitted or terminal request terms and snapshots are immutable';
    END IF;
END //

DELIMITER ;
