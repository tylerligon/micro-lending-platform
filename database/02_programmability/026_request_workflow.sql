-- Table-driven policy for implemented request commands. No dynamic SQL execution.
-- Definitions are developer-owned; runtime configuration only enables/disables rows.
CREATE TABLE RequestWorkflowState (
 StateCode VARCHAR(20) COLLATE utf8mb4_0900_bin PRIMARY KEY,
 Description VARCHAR(255) NOT NULL,
 CHECK (CHAR_LENGTH(TRIM(Description)) > 0)
) ENGINE=InnoDB;

CREATE TABLE RequestWorkflowAction (
 ActionCode VARCHAR(32) COLLATE utf8mb4_0900_bin PRIMARY KEY,
 PermissionCode VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL,
 SuccessEventType VARCHAR(40) COLLATE utf8mb4_0900_bin NOT NULL,
 FOREIGN KEY (PermissionCode) REFERENCES Permission(PermissionCode)
) ENGINE=InnoDB;

CREATE TABLE RequestWorkflowTransition (
 ActionCode VARCHAR(32) COLLATE utf8mb4_0900_bin NOT NULL,
 FromState VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
 ToState VARCHAR(20) COLLATE utf8mb4_0900_bin NOT NULL,
 IsEnabled BOOLEAN NOT NULL DEFAULT TRUE,
 RowVersion BIGINT UNSIGNED NOT NULL DEFAULT 0,
 PRIMARY KEY (ActionCode, FromState),
 FOREIGN KEY (ActionCode) REFERENCES RequestWorkflowAction(ActionCode),
 FOREIGN KEY (FromState) REFERENCES RequestWorkflowState(StateCode),
 FOREIGN KEY (ToState) REFERENCES RequestWorkflowState(StateCode),
 CHECK (IsEnabled IN (0,1)),
 CHECK (ToState <> 'NotCreated')
) ENGINE=InnoDB;

DELIMITER //
-- Internal helper; caller owns the transaction. Policy mutex precedes all domain locks.
CREATE PROCEDURE sp_require_request_transition(
 IN p_Actor BIGINT UNSIGNED, IN p_Role VARCHAR(16), IN p_Action VARCHAR(32),
 IN p_Request BIGINT UNSIGNED, IN p_ExpectedVersion BIGINT UNSIGNED,
 OUT p_SelectedRole VARCHAR(16), OUT p_NextState VARCHAR(20), OUT p_Event VARCHAR(40))
SQL SECURITY DEFINER
BEGIN
 DECLARE v_Permission VARCHAR(40);
 DECLARE v_State VARCHAR(20) DEFAULT 'NotCreated';
 DECLARE v_Version BIGINT UNSIGNED;
 SET p_SelectedRole=NULL, p_NextState=NULL, p_Event=NULL;
 CALL sp_lock_policy();
 SELECT PermissionCode, SuccessEventType INTO v_Permission,p_Event
 FROM RequestWorkflowAction WHERE ActionCode=p_Action;
 IF v_Permission IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown workflow action';
 END IF;
 CALL sp_require_permission(p_Actor,p_Role,v_Permission,p_Request,p_SelectedRole);
 IF p_Request IS NOT NULL THEN
  SET v_State=NULL;
  SELECT RequestState,RowVersion INTO v_State,v_Version
  FROM LoanRequest WHERE RequestID=p_Request FOR UPDATE;
  IF v_State IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Request is unavailable'; END IF;
  IF p_ExpectedVersion IS NULL OR p_ExpectedVersion<>v_Version THEN
   SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Stale request version';
  END IF;
 END IF;
 SELECT ToState INTO p_NextState FROM RequestWorkflowTransition
 WHERE ActionCode=p_Action AND FromState=v_State AND IsEnabled=1;
 IF p_NextState IS NULL THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Workflow transition unavailable';
 END IF;
END //

-- Same trusted administrator gateway as permission configuration; not arbitrary DML.
CREATE PROCEDURE sp_set_request_transition(IN p_Actor BIGINT UNSIGNED,
 IN p_Action VARCHAR(32), IN p_FromState VARCHAR(20),
 IN p_Enabled BOOLEAN, IN p_ExpectedVersion BIGINT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
 DECLARE v_Role VARCHAR(16); DECLARE v_Old BOOLEAN;
 DECLARE v_Version BIGINT UNSIGNED; DECLARE v_Audit BIGINT UNSIGNED;
 DECLARE EXIT HANDLER FOR SQLEXCEPTION
 BEGIN
  DECLARE v_Number INT; DECLARE v_Message TEXT;
  GET STACKED DIAGNOSTICS CONDITION 1 v_Number=MYSQL_ERRNO,v_Message=MESSAGE_TEXT;
  ROLLBACK;
  BEGIN
   DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET @ml_audit_failed=1;
   CALL sp_record_failure(p_Actor,'SetRequestTransition',
    CASE WHEN v_Number=1213 THEN 'DB_DEADLOCK' WHEN v_Number=1205 THEN 'DB_LOCK_TIMEOUT'
     WHEN v_Message LIKE '%version%' THEN 'STALE_VERSION'
     WHEN v_Message LIKE '%Permission%' THEN 'ROLE_REQUIRED'
     WHEN LOWER(v_Message) LIKE '%audit%failure%' THEN 'INTEGRITY_FAILURE'
     WHEN v_Number=1644 THEN 'INVALID_INPUT' ELSE 'DB_ERROR' END,
    fn_action_context(),v_Number<>1644 OR LOWER(v_Message) LIKE '%audit%failure%');
  END;
  RESIGNAL;
 END;
 SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
 START TRANSACTION;
 CALL sp_require_permission(p_Actor,NULL,'permission.manage',NULL,v_Role);
 SELECT IsEnabled,RowVersion INTO v_Old,v_Version FROM RequestWorkflowTransition
 WHERE ActionCode=p_Action AND FromState=p_FromState FOR UPDATE;
 IF v_Version IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Unknown workflow transition'; END IF;
 IF p_ExpectedVersion IS NULL OR p_ExpectedVersion<>v_Version THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Stale workflow version';
 END IF;
 IF p_Enabled IS NULL OR p_Enabled NOT IN (0,1) THEN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Enabled must be boolean';
 END IF;
 UPDATE RequestWorkflowTransition SET IsEnabled=p_Enabled,RowVersion=RowVersion+1
 WHERE ActionCode=p_Action AND FromState=p_FromState;
 INSERT INTO AuditEvent(EventType,Outcome,ActorUserID,ActingRoleCode,TechnicalAccount,SubjectType,SubjectKey,ContextID)
 VALUES('WorkflowConfigured','Success',p_Actor,v_Role,SESSION_USER(),'WorkflowTransition',
  CONCAT(p_Action,'/',p_FromState),fn_action_context());
 SET v_Audit=LAST_INSERT_ID();
 INSERT INTO AuditChange VALUES(v_Audit,'Configuration',CAST(v_Old AS CHAR),CAST(p_Enabled AS CHAR));
 COMMIT;
END //
DELIMITER ;
