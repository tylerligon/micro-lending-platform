# Micro-Lending Platform — ERD deliverable

**Start with the [professor review artifacts](#professor-review--october-20-2026).**

## Professor review — October 20, 2026

**Review snapshot:** [`fc6e09d`](https://github.com/tylerligon/micro-lending-platform/commit/fc6e09dbc7b4a85232bd8f99a5540d94de988e43). The links below are pinned to this deliverable commit so later edits will not change the review set. These are review labels, not a Git release tag.

| Review order | Artifact | Review focus |
| --- | --- | --- |
| 1 — Requirements | [Functional_Requirements_Document.md](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/Functional_Requirements_Document.md) | Scope, actors, business rules and acceptance criteria. |
| 2 — Technical design | [Technical_Design_Document.md](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/Technical_Design_Document.md) | Schema/enforcement, transactions, security and implementation boundaries; §8.1 contains the latest audit fixes. |
| 3 — Conceptual ERD | [01-conceptual.svg](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/01-conceptual.svg) | Business relationships, cardinality, participation and weak-entity notation. |
| 4 — Accounts and funding ERD | [02-accounts-funding.svg](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/02-accounts-funding.svg) | Typed account/request/evaluation/contribution tables and their keys. |
| 5 — Repayments and oversight ERD | [03-repayments-oversight.svg](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/03-repayments-oversight.svg) | Loan schedules, repayment allocations, oversight and audit relationships. |
| 6 — ERD explanation and checklist | [ERD.md](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/ERD.md) | Professor-requirement mapping, relationship matrix, worked examples and design trade-offs. |

**Use the FRD/TDD under `docs/` for this review.** The root-level documents were preserved from earlier work; the root TDD does not describe this ERD baseline.

Supporting material, as needed:
- [Editable three-page ERD](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/Micro_Lending_ERD.drawio).
- [Application flow](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/04-application-flow.svg) and [UI wireframes](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/05-wireframes.svg) — proposed design views.
- [Validation entrypoint](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/tools/validate_erd.py), [audit catalogue](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/audit-catalogue.json) and [audit regression cases](https://github.com/tylerligon/micro-lending-platform/blob/fc6e09dbc7b4a85232bd8f99a5540d94de988e43/docs/diagrams/tools/test_audit_rules.py).

**Recent corrections to review:** protected account-status explanations in existing AuditChange; owner/Administrator cancellation; explicit Bootstrap exceptions; event-specific actor and transaction bindings. The package retains 15 entities, 114 attributes and 27 FKs.

**Evidence boundary:** the transfer recorded 4,976 passing design assertions, including 57 audit regression cases. This labeling change does not rerun or extend that evidence. Executable MySQL behavior, API/UI, real concurrency and rollback remain unverified.

**Decision requested from the professor:** does one deployable FastAPI service with separate command/update and query/extraction modules satisfy the course's microservices requirement, or are separate deployables required?

- [Editable ERD: one draw.io file, three pages](docs/diagrams/Micro_Lending_ERD.drawio)
- SVG exports: [conceptual](docs/diagrams/01-conceptual.svg), [accounts/funding](docs/diagrams/02-accounts-funding.svg), [repayments/oversight](docs/diagrams/03-repayments-oversight.svg)
- Matching sources: [FRD](docs/Functional_Requirements_Document.md), [TDD](docs/Technical_Design_Document.md), and [course handouts](docs/course)
- Supporting application views: [editable source](docs/diagrams/Application_Design.drawio), [flow](docs/diagrams/04-application-flow.svg), [wireframes](docs/diagrams/05-wireframes.svg)
- [Reusable ERD work prompt](docs/ERD_Work_Prompt.md)

The model has **15 application entities, 114 attributes and 27 foreign keys**.
The package includes its model dictionary, complete seven-user fixture specification,
audit catalogue, exporters, validator, audit regression tests and SQL fixture materializer.
Build-log tables and derived reporting views are distinguished from application entities.

## Source and existing documents

Copied from the reviewed ERD revision
[`39c00d7`](https://github.com/anuvikdas/CS-437-Database-Systems-Implementation/commit/39c00d7558166178393ce3d549aabb4e3f17b724).
All files under `docs/` match that source revision. Use the FRD/TDD **inside `docs/`**
when studying or validating this ERD. The pre-existing root-level FRD and TDD are preserved;
the root TDD is an earlier design and is not the baseline for this diagram package.
This transfer does not reconcile those separate document versions or their team metadata.

## Validate

From the repository root, with Python 3 and the standard library:

```bash
python3 docs/diagrams/tools/validate_erd.py
```

The transfer passed **4,976 design assertions**, including **57 targeted audit regressions**,
and checked exact editable-source/SVG agreement for all five views. These are design and
fixture checks; MySQL execution, a running API/UI, real concurrency and rollback remain
unverified. The optional materializer dependencies and commands are in
[TDD §10.1](docs/Technical_Design_Document.md#101-fixture-and-implementation-acceptance-gates).
No generated credentials or SQL seed are included.
