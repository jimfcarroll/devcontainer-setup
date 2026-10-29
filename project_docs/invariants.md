# Invariants

Global rules. They hold in every layer, every epic, business and technical
alike. Not requirements to be traded off — code that breaks one is wrong, not
unfinished.

To break one, amend this file first.

---

## 1. No floats.

Fixed point only, in arithmetic and in storage. `Decimal` in Python,
`decimal128` in parquet, `DECIMAL` in DuckDB.

Casting to `float` to "just store it" or "just compare it" is the bug, not the
shortcut around it.

## 2. No backward compatible execution paths.

Code handles one shape. Never branch to support the shape it used to handle.

When a format, schema or contract changes, change it and migrate the data.
Until migration tooling exists, invalidate and re-import.

## 3. No untyped columns.

Every column carries a real type: `decimal128` for money, `timestamp[us]` for
instants, `date32` for dates.

`object` dtype is duck typing — it accepts anything and fails late, far from
the cause.

## 4. Absolute time only.

Instants are stored as an epoch: naive `timestamp[us]`, meaning UTC. Never a
local time plus a zone, which needs the timezone database to resolve and shifts
when that database changes.

Convert at the display boundary. Use a date only for a fact that has no instant.

---

## Adding a rule

A rule belongs here only if it holds everywhere in this project, with no
exceptions. A rule with exceptions is a guideline; put it somewhere else.

Number it and state it as a command in the heading. Underneath, say what it
means concretely in this project's own terms, and why the shortcut around it is
the bug rather than a convenience.
