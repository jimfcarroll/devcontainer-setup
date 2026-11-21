---
name: handoff
description: Write the note that carries a session's working knowledge across a context reset. Invoke when the user says they are about to clear the context and asks for a handoff.
---

# Handoff

This skill is to help when clearing the context so that vital information for
the next step, gleaned from this session, won't be lost whether the context is
cleared or compacted.

## What to do

**Save pertinent information in out.HANDOFF.md at the root of the workspace.**
You will be storing pertinent details for the work we're in the middle of
that was determined in this session, so it will not be lost after a clearing
of the context, in a file called out.HANDOFF.md.

**The note always tells its reader to delete the handoff file (out.HANDOFF.md) once read.**

**If there's a question about specific points that should be saved**
The default for anything questionable would be to save it. However, if you
really don't know, you can ask.

**If there is an active task or epic document.** Put what this session
learned about the work itself in an appendix to it: the task document if
there is one, otherwise the epic. The handoff file then points to that
appendix instead of repeating it.

**What.**

- where we are: the active epic and task, the last git commit and its hash,
  what is committed and what is not, and the exact next step in the words
  the user would use to ask for it;
- how the user works: the planning and implementing cycle, what approval
  looks like, what they expect of prose, questions and git commit messages;
- the commands known to work, each with today's numbers beside it, so the
  next session can tell a regression from a baseline;
- the approaches tried and rejected this session, each with the reason,
  so the next session does not retry them;
- the conventions established during the work that the code does not
  state on its own;
- a pointer to the appendix, if one was written, telling the next session
  to start from it rather than re-measure;
- anything the user said they would do themselves, such as restarting a
  server, that the next session should not assume is done.

## Writing it

1. Re-read the active task file, if there is one, and the last few git
   commit messages before writing, so the note states what was done, not what
   was planned.
2. If there is an appendix to write, write it first. Do not commit it.
   Then write the note, reading the appendix back so the two do not repeat
   each other.
3. Tell the user, in a short recap, where both pieces are, what the next
   step is, and that the note deletes itself.
