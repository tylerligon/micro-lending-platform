-- NotCreated is a rule source only; LoanRequest's domain excludes it.
INSERT INTO RequestWorkflowState VALUES
 ('NotCreated','No request exists yet'),('Draft','Editable request'),
 ('Submitted','Submitted for assessment'),('PendingReview','Awaiting review'),
 ('OpenFunding','Available for funding'),('Funded','Activated as a loan'),
 ('Rejected','Rejected request'),('Cancelled','Cancelled request'),('Expired','Funding expired');

-- Action identifiers name implemented handlers, never executable SQL or module paths.
INSERT INTO RequestWorkflowAction VALUES
 ('CreateDraft','request.create','RequestSaved'),
 ('EditDraft','request.edit','RequestSaved'),
 ('SubmitRequest','request.submit','RequestSubmitted'),
 ('CancelDraft','request.cancel','RequestCancelled');

INSERT INTO RequestWorkflowTransition(ActionCode,FromState,ToState) VALUES
 ('CreateDraft','NotCreated','Draft'),
 ('EditDraft','Draft','Draft'),
 ('SubmitRequest','Draft','Submitted'),
 ('CancelDraft','Draft','Cancelled');

-- Do not seed executable assessment/funding/repayment rules until their handlers exist.
