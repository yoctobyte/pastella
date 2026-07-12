# Pastella docs & tickets

Minimal, file-based. No tracker, no tooling — just markdown under version control.

## Tickets

Live in [`tickets/`](tickets/), one file per ticket: `NNNN-slug.md`.

Frontmatter-ish header each ticket carries:

- **Status:** `open` · `in-progress` · `blocked` · `done` · `rejected`
- **Depends:** other tickets or external gaps (e.g. a frank2 RTL feature)

Flow: write the ticket → implement → flip Status to `done` with the commit(s) →
if a phase is blocked, mark `blocked` and say on what.

## Index

- [0001 — Realms & secure transport](tickets/0001-realms-and-secure-transport.md)
