# Midterm walkthrough: block explanations

These numbers match [midterm_walkthrough.sql](../tests/sql/midterm_walkthrough.sql).
Run one block at a time in the same Workbench connection. Blocks **5, 6, 7 and 12**
intentionally fail; show the error and continue to the next block.

## 1. Select the database and inspect the borrower

`USE` selects micro_lending_midterm_demo. Setting the session time zone to +00:00
makes the connection use UTC. `SELECT DATABASE()` confirms which database is selected.

The next queries retrieve user 1's account status, current roles, and borrower
profile. `ActiveMarker = 1` selects current role assignments instead of revoked
assignments. The profile query shows its UserID and version without exposing its
financial fields.

**Expected:** the demo database, an Active user, a Borrower role, and a profile row.
These are the starting conditions for creating a request.

## 2. Create and read a Draft

`CALL sp_create_loan_request(...)` runs the stored procedure with borrower ID 1,
a purpose, principal 300.00, and three installments. The procedure checks the account,
role, profile and terms, then inserts the request and its audit records atomically.

`MAX(RequestID)` finds this borrower's highest request ID and saves it in the
connection variable `@demo_request`. We use that ID in later blocks. This lookup
assumes one presenter is creating requests; it is not a concurrent application
ID-retrieval mechanism.

The final SELECT reads the new request through v_borrower_requests, a view joining
request information with the user's public alias.

**Expected:** principal 300.00, 3 installments, Draft, RowVersion 0 and NULL
SubmittedAt. The supplied user ID identifies the demo actor; it is not a login.

## 3. Edit the Draft

The procedure receives the borrower ID, remembered request ID, expected version 0,
new purpose, principal 600.00, and six installments. It checks eligibility,
ownership, Draft state, version and valid terms before updating and auditing.

Expected version 0 means "update the version I previously read." If another edit
has changed it, the procedure rejects that stale version rather than silently
overwriting newer work. The final SELECT displays the updated row.

**Expected:** revised purpose, principal 600.00, 6 installments, Draft and version 1.

## 4. Cancel the Draft

`sp_cancel_draft` receives the actor ID, Borrower role, request ID, expected version
1, and cancellation reason. It checks the actor's stored role and ownership, then
changes the request state and saves the reason and audit records together.

Cancellation is an UPDATE, not a DELETE. The request and its original terms remain
available as history. `TerminalReason` holds the reason for ending the request.

**Expected:** Cancelled, principal 600.00, 6 installments, the supplied reason and
version 2. This request was cancelled without submission and cannot then be submitted.

## 5. Reject a principal below the minimum

This attempts to create a different request for 99.99. Although that is a valid
decimal amount, it violates the project's minimum principal of 100.00.

**Expected:** MySQL error 1644 with the principal-range validation message. No new
request or success audit is inserted. This is an intentional validation failure.

## 6. Reject editing a cancelled request

This attempts to edit the request cancelled in block 4. The expected version 2 is
current, but the request is no longer Draft.

**Expected:** MySQL error 1644 stating that only Draft requests may be edited.
This demonstrates that supplying the right version and valid amounts does not
permit an operation in the wrong lifecycle state.

## 7. Reject hard deletion

`DELETE FROM LoanRequest` attempts to remove the selected request permanently.
The request-delete guard trigger runs before deletion and raises an error.

**Expected:** MySQL error 1644 and no deleted row. This is explicit history
protection, separate from a foreign key rejecting deletion of a referenced parent.

## 8. Verify the rejected actions changed nothing

This SELECT retrieves the original request after the three intentional failures.
It checks the result directly instead of relying only on the error messages.

**Expected:** the row still exists with Cancelled, principal 600.00 and version 2.
The invalid creation in block 5 did not replace or alter this request.

## 9. Prepare a separate rollback example

The first CALL creates a second Draft for 300.00 over three installments.
`@demo_rollback_request` stores that new ID without replacing `@demo_request`, which
continues to identify the first, cancelled request.

The two COUNT queries save the current numbers of AuditEvent and AuditChange rows.
They run after the new Draft's successful creation, so its creation audit is part
of the baseline. `@demo_fail_audit = 0` starts the test switch in the off position.
The final SELECT displays the second request before the attempted cancellation.

**Expected:** the second request is Draft, version 0, with a NULL cancellation reason.

## 10. Create the test-only failure trigger

This creates demo_force_cancel_audit_failure on AuditChange. `BEFORE INSERT` means
it runs before a new audit-detail row is inserted; `FOR EACH ROW` checks each row.

It raises an error only when the connection's @demo_fail_audit switch is 1 and the
new detail's FieldName is TerminalReason. That deliberately makes cancellation
fail after its request UPDATE and AuditEvent insert have already occurred.

`SIGNAL SQLSTATE '45000'` raises the custom error. The DELIMITER commands let the
Workbench client read the complete trigger body, including its internal semicolons,
as one CREATE statement, then restore the normal separator.

**Expected:** the trigger is created. It does not cancel anything or cause an error
yet. It is a demonstration tool, not an additional production business rule.

## 11. Enable the test switch

`SET @demo_fail_audit = 1` turns on the test trigger's failure condition for this
connection. SET changes a connection variable, not a request or audit row.

**Expected:** no result table is needed. The next cancellation will encounter the
injected error when it attempts to insert its TerminalReason audit detail.

## 12. Attempt cancellation and force rollback

This calls cancellation for the second request using its correct owner, Draft
state, expected version 0 and a nonblank reason. Normal input validation should pass.

The procedure updates the request and begins its audit writes. The trigger from
block 10 then raises the forced error. The procedure's EXIT HANDLER executes
ROLLBACK to undo the transaction and RESIGNAL to return the error to Workbench.

**Expected:** error 1644 with "Demo forced audit failure". Run this CALL alone, then
continue to block 13. Do not issue a manual ROLLBACK first: we are demonstrating
that the procedure's own handler performs it.

## 13. Verify rollback and remove the test trigger

The first SET turns the failure switch off. The following queries inspect the
second request, compare audit counts with the saved baseline, and return simple
Boolean checks. In these SELECT results, 1 means true and 0 means false.

**Expected:**

- The second request remains Draft, version 0, with NULL TerminalReason.
- RollbackPreservedDraft is 1.
- EventsBefore equals EventsAfter; ChangesBefore equals ChangesAfter.
- AuditEventCountUnchanged and AuditChangeCountUnchanged are both 1.

These results show that neither the cancellation nor its partial success-audit
records survived the failure. The second request's earlier creation remains committed.

The final DROP removes only demo_force_cancel_audit_failure. It does not remove
the actual request-protection triggers. Complete this cleanup before another
rehearsal, because creating a trigger with the same name again would fail.

## 14. Read the original request's audit history

This returns to the first request stored in @demo_request. The JOIN connects each
AuditEvent to its AuditChange detail rows through AuditEventID.

SubjectType and SubjectKey filter the history to that request. CAST converts its
numeric ID to text because SubjectKey stores identifiers as text. ORDER BY arranges
the results by event time, event ID, then field name.

The output shows the event, timestamp, actor, acting role and old/new field values.
The second SELECT counts the events themselves rather than the joined detail rows.

**Expected:** three events: RequestSaved for creation, RequestSaved for editing,
and RequestCancelled. The joined output has more than three rows because one
action can change several fields. This is history produced by the live walkthrough.

## 15. Explain the primary-key lookup

EXPLAIN asks MySQL for the access plan of the SELECT. Its WHERE clause uses RequestID,
the primary key, to identify at most one row. This does not change any records.

**Expected:** a unique lookup, possibly shown as PRIMARY/const in traditional output.
Your MySQL version may instead display "Rows fetched before execution," reflecting
the optimizer resolving the uniquely identified row during planning.

Explain the purpose of the key and access path. This small example is not a measured
performance benchmark or proof that additional indexes are needed.
