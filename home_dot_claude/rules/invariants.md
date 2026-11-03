# Global invariants

Rules that hold in every project built on this template, in every layer and
every epic. They are not requirements to be traded off: code that breaks one
is wrong, not unfinished. A project's own rules live in its `docs/invariants.md`.

To break one, amend this file first.

---

## G1. No backward compatible execution paths.

Code handles one shape. Never branch to support the shape it used to handle.

When a format, schema or contract changes, change it and migrate the data.
Until migration tooling exists, invalidate and re-import.

## G2. No untyped columns.

Every column carries a real type, declared where the column is written:
`timestamp[us]` for instants, `date32` for dates, and a stated type for every
other kind of value the project stores.

`object` dtype is duck typing. It accepts anything and fails late, far from the
cause.

## G3. Absolute time only.

Instants are stored as an epoch: naive `timestamp[us]`, meaning UTC. Never a
local time plus a zone, which needs the timezone database to resolve and shifts
when that database changes.

Convert at the display boundary. Use a date only for a fact that has no instant.

---

## Adding a rule

A rule belongs here only if it holds in every project, with no exceptions. A
rule that holds in one project belongs in that project's `docs/invariants.md`.
A rule with exceptions is a guideline and belongs somewhere else.

Give it the next G number and state it as a command in the heading. Underneath,
say what it means concretely and why the shortcut around it is the bug rather
than a convenience.
