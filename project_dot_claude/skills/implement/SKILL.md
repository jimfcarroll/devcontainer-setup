---
name: implement
description: Steps for carrying out an approved plan for a commit section, from the failing tests to the git commit that ends the cycle. Invoke when the plan for one of a task's commit sections is approved.
---

# THE PRIME DIRECTIVE

**NOTHING GETS IMPLEMENTED UNLESS THERE'S A TEST WRITTEN FOR IT FIRST**

If needed in order to comply, reorder the plan.

# NON-NEGOTIABLES

Check the change against the invariants, global and project, before writing
code, and again
before committing. A change that breaks an invariant does not ship — amend the
invariant first, or find another design. Do not restate the rules here.

# Working Agreement — One Commit Section

A commit section is one plan and implement cycle, and the `flesh-out-task`
skill says what a commit section is and how the word "commit" is used. The task
file and that skill set what the commit section holds. This skill carries out
the approved plan for that commit section, and it ends with the commit
section's git commit. Follow these steps in order. Do not skip steps.

1. **Read the task file and the approved plan.** Understand the commit section's sub-tasks before writing any code.

2. **Ask questions** if anything is unclear. Do not assume.

3. **Write tests first.** Tests are the first real embodiment of the requirements.

4. **Implement the commit section's sub-tasks**, making the tests pass.

5. **Ensure test coverage reaches 85%** for new/changed code. Add missing tests if needed.

6. **Run all tests** and verify they pass. Then run the plan's check against the running app.

7. **Update the task file.** Tick the commit section's boxes and add their landing notes, as the outline of a task file in `flesh-out-task` describes. The task's last commit section also ticks the acceptance criteria.

8. **Commit locally, once.** DO NOT push, and never amend.
   - The subject is the commit section's sentence from the task, after `epic-NNN task-NNN: ` in an epics managed project and after `task-NNN: ` in a task managed project. The body says what was done and what was measured.
   - The git commit takes the task file and every other change waiting under `epics/` or `tasks/`. Add a moved epic directory or task file at both its old and its new path, so that git shows the move as a rename.
   - This git commit ends the cycle. The next commit section starts with its own plan.
