# Reusable prompt: a compact, complete micro-lending ERD

Revise this repository's micro-lending ERD into a small, coherent deliverable that
two students can explain in an interview. Read the supplied professor requirements
and the current FRD/TDD before editing. The professor's requirements take priority;
the example repository is only a secondary reference.

Use the approved scope: one fixed demonstration policy D1 ($100–$2,000 principal,
3 or 6 monthly installments, 14-day funding window, fictional interest-free USD)
and retained **summary** exposure evidence. Calculate exposure from every other
live request/outstanding loan, but retain its total, delinquency result, check time,
and condition results rather than a historical row per contributing obligation.
Retain the submitted income/external-obligation snapshot and policy label.
Different policy versions within one dataset and component-level exposure history
are outside this release. Do not weaken concurrent checks or credit eligibility.

1. Target 15 meaningful application tables: User, Role, UserRole, BorrowerProfile,
   LoanRequest, RequestEvaluation, OperationReceipt, FundingCommitment, Loan,
   Installment, Repayment, RepaymentAllocation, OversightNote, AuditEvent, AuditChange.
   Consolidate frozen inputs into LoanRequest and evaluation/assessment/review
   facts into RequestEvaluation. Keep separate historical attempts and preserve
   the distinction between a machine assessment and a human final decision.
   Do not force attribute/FK quotas or hide structured business facts in JSON/CSV.
2. Preserve multiple outstanding loans, repeat contributions to an eligible
   request, exact-result retry protection, full-funding activation, partial/early
   repayment and oldest-first allocation, account/role restrictions, immutable
   history, and participation-scoped lender delinquency access. Preserve protected
   inputs, authorization, atomicity, and meaningful audit evidence.
3. Produce one editable `Micro_Lending_ERD.drawio` with three pages: conceptual;
   accounts/requests/funding; loans/repayments/oversight. Export one matching SVG
   per page. Use the professor's Chen notation on the conceptual page and complete
   typed relational detail on the other pages. Show 1:1, 1:N, M:N, both-direction
   min/max participation, identifying weak entity, and relevant attribute types.
   The course says minimum 8–10 meaningful entities; no count of pages/columns/FKs
   is prescribed. Demonstrate 3NF and explain derived values.
4. Document every application attribute, type, PK, FK, UNIQUE rule, and nullability.
   Distinguish lookup/associative entities, derived reporting views, and operational
   build-log tables. Keep build details outside the main application model.
5. Update FRD, TDD, ERD explanation, README, and existing references together.
   Preserve requirement IDs. State the two approved scope reductions explicitly.
   Remove superseded diagram files and obsolete generation machinery; Git history
   preserves the previous package. Keep the workspace small and navigable.
6. Put the requirement checklist, relationship matrix, assumptions, sample records,
   enforcement boundaries, and a short interview walkthrough in `docs/ERD.md`.
   No separate audit/review document. Save this prompt as `docs/ERD_Work_Prompt.md`.
7. Validate the complete model and concrete sample cases, including concurrent
   exposure reasoning, repeated contributions, retries/conflicts, activation,
   repayment allocation, delinquency, and lender visibility. State which checks
   are structural, projected, or executed against a real database. If there is no
   SQL implementation, say implementation consistency remains unverified.
8. Inspect every rendered SVG at readable resolution, check text/connector clarity,
   and verify exports against the actual draw.io source. Do not claim a native
   diagrams.net UI round-trip or database execution unless performed.
9. Commit sources, exports, revised specifications, explanation, and this prompt
   together. Preserve unrelated repository files; never force-push. Verify the
   resulting commit and provide links. Ask only about additional contradictions
   that require a business decision outside the approved scope above.

Optimize for understandable behavior and defensible design, not the smallest
possible table count. Each retained table must have a concise purpose and a
requirement basis. Do not add new financial products or infrastructure.


Review-gap guardrails for subsequent revisions: keep one canonical `section` per entity;
check it resolves to the TDD heading. Maintain the finite audit catalogue and field
redaction rules. Retain bounded status explanations in existing AuditChange, allow both
owner and Administrator cancellation, and test event-specific actor/transaction bindings
(including missing actors, wrong services and fresh-build-only Bootstrap). Preserve the same-connection encryption/eligibility protocol and the
single owner of completion/audit. Include seven users with a dual-role self-funding denial,
complete seed values and explicit SQL-execution status. Keep the three ERD pages compact;
application flow/wireframes are separately identified design views. Do not claim that
internal Command/Query modules meet the instructor's microservices wording until that
interpretation is confirmed. Never invent contributor names, course section, test results
or dependency compatibility; list outstanding decisions in the existing TDD.
