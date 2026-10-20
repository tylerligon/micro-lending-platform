# Micro-Lending Platform

## Current project documents

Use the documents under `docs/` for review and implementation. This repository
maintains one full copy of each current document. The root-level FRD and TDD
are navigation notices; their earlier draft contents remain in Git history.

| Review order | Current document | Purpose |
| --- | --- | --- |
| 1 | [Functional Requirements Document](docs/Functional_Requirements_Document.md) | Business scope, actors, rules, permissions, reports, and acceptance criteria |
| 2 | [Technical Design Document](docs/Technical_Design_Document.md) | Architecture, complete data dictionary, transactions, security, and implementation plan |
| 3 | [ERD guide](docs/ERD.md) | Diagram navigation, requirement checklist, relationships, and worked examples |

Update these documents in place. Use Git history for earlier revisions instead
of maintaining separately named copies. Current review links follow the working
branch so they include subsequent corrections.

## Diagrams

The course requires editable sources, SVG exports, and Markdown explanations.
Each SVG below represents a page in its corresponding source, not a separate
version of the design.

| Editable source | Page exports | Explanation |
| --- | --- | --- |
| [Micro_Lending_ERD.drawio](docs/diagrams/Micro_Lending_ERD.drawio) | [Conceptual](docs/diagrams/01-conceptual.svg), [accounts/funding](docs/diagrams/02-accounts-funding.svg), [repayments/oversight](docs/diagrams/03-repayments-oversight.svg) | [ERD guide](docs/ERD.md) |
| [Application_Design.drawio](docs/diagrams/Application_Design.drawio) | [Application flow](docs/diagrams/04-application-flow.svg), [wireframes](docs/diagrams/05-wireframes.svg) | [TDD §§2.1–2.3](docs/Technical_Design_Document.md#21-architecture-decision-and-editable-views) |

## Supporting material and implementation status

The model contains **15 application entities, 114 attributes, and 27 foreign keys**.
The initial design package was imported from the team repository's
[39c00d7 revision](https://github.com/anuvikdas/CS-437-Database-Systems-Implementation/commit/39c00d7558166178393ce3d549aabb4e3f17b724).
The documents linked above are the maintained review set in this repository.

[Course handouts](docs/course) are instructor references. JSON files under
`docs/diagrams/` describe model metadata, the audit catalogue, and fictional sample
records. Python tools maintain and validate these design artifacts; they do not
constitute a working MySQL schema or application.

Run the design checks with Python 3 and the standard library:

```bash
python3 docs/diagrams/tools/validate_erd.py
```

These checks cover artifact consistency, fixture calculations, and audit contracts.
MySQL execution, a running API/UI, real concurrency, and rollback remain unverified.
The [TDD acceptance gates](docs/Technical_Design_Document.md#101-fixture-and-implementation-acceptance-gates)
identify the remaining implementation work and fixture materialization requirements.

The professor's architecture decision is still pending: whether one deployable
FastAPI service with command/update and query/extraction modules satisfies the
microservices requirement, or separate deployables are needed.
