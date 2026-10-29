---
name: implement
description: Steps for executing the plan to implement sub-tasks. Invoke when starting work on one or more sub-tasks.
---

# THE PRIME DIRECTIVE

**NOTHING GETS IMPLEMENTED UNLESS THERE'S A TEST WRITTEN FOR IT FIRST**

If needed in order to comply, reorder the plan.

# NON-NEGOTIABLES

Check the change against `docs/invariants.md` before writing code, and again
before committing. A change that breaks an invariant does not ship — amend the
invariant first, or find another design. Do not restate the rules here.

# Working Agreement — Sub-task Implementation

AFTER PLANNING, follow these steps in order when implementing sub-tasks. Do not skip steps.

1. **Read the sub-task file.** Understand the requirements before writing any code.

2. **Ask questions** if anything is unclear. Do not assume.

3. **Write tests first.** Tests are the first real embodiment of the requirements.

4. **Implement the sub-task**, making the tests pass.

5. **Ensure test coverage reaches 85%** for new/changed code. Add missing tests if needed.

6. **Run all tests** and verify they pass.

7. **Update the task file** — check off completed sub-task checkboxes.

8. **Commit locally.** DO NOT push.
   - Commit message reflects the task details and work done.
   - Multiple commits per sub-task are fine; do not combine multiple sub-tasks in one commit.
   - Commit must include the updated task file showing completed checkboxes.
