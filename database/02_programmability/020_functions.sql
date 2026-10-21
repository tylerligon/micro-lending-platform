-- Reusable calculations and validation. Validate money before casting to DECIMAL.
DELIMITER //

CREATE FUNCTION fn_money(p_Value TEXT) RETURNS DECIMAL(18,2)
DETERMINISTIC NO SQL SQL SECURITY INVOKER
BEGIN
    IF p_Value IS NULL OR NOT REGEXP_LIKE(p_Value, '^[0-9]{1,16}([.][0-9]{1,2})?$', 'c') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Money must be nonnegative, with at most two decimal places';
    END IF;
    RETURN CAST(p_Value AS DECIMAL(18,2));
END //

DELIMITER ;
