-- BR-22: cancellation is an UPDATE. Even an unreferenced Draft is retained.
-- This guard does not implement general immutable history for all other tables.
DELIMITER //
CREATE TRIGGER trg_request_no_delete BEFORE DELETE ON LoanRequest
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Requests are retained; cancel a Draft instead of deleting it';
END //
DELIMITER ;
