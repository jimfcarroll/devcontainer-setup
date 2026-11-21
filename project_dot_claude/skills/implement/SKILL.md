---
name: implement
description: Steps for carrying out an approved commit plan, from the failing tests to the commit that ends the cycle. Invoke when the plan for a commit of a task is approved.
---

# THE PRIME DIRECTIVE

**NOTHING GETS IMPLEMENTED UNLESS THERE'S A TEST WRITTEN FOR IT FIRST**

If needed in order to comply, reorder the plan.

# NON-NEGOTIABLES

Check the change against the invariants, global and project, before writing
code, and again
before committing. A change that breaks an invariant does not ship — amend the
invariant first, or find another design. Do not restate the rules here.

# Working Agreement — One Commit

A commit is one plan and implement cycle. The task file and the
`flesh-out-task` skill set what the commit holds. This skill carries out the
approved plan for that commit, and it ends with the commit. Follow these steps
in order. Do not skip steps.

1. **Read the task file and the approved plan.** Understand the commit's sub-tasks before writing any code.

2. **Ask questions** if anything is unclear. Do not assume.

3. **Write tests first.** Tests are the first real embodiment of the requirements.

4. **Implement the commit's sub-tasks**, making the tests pass.

5. **Ensure test coverage reaches 85%** for new/changed code. Add missing tests if needed.

6. **Run all tests** and verify they pass. Then run the plan's check against the running app.

7. **Update the task file.** Tick the commit's boxes and add their landing notes, as the outline of a task file in `flesh-out-task` describes. The task's last commit also ticks the acceptance criteria.

8. **Commit locally, once.** DO NOT push, and never amend.
   - The subject is `epic-NNN task-NNN: ` followed by the commit's sentence from the task, and the body says what was done and what was measured.
   - The commit takes the task file and every other change waiting under `epics/`. Add a moved directory whole, so that git shows the move as a rename.
   - This commit ends the cycle. The next commit starts with its own plan.
