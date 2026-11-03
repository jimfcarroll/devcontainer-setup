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

**The out.HANDOFF.md file should always contain delete instructions.** The file should contain instructions that it be deleted upon ingestion. This is not only to clean up but also to make sure the handoff was completed and an understanding was passed.

**If there's a question about specific points that should be saved**
The default for anything questionable would be to save it. However, if you
really don't know, you can ask.

**If we're in the middle of development.** You can use the documents for the epic
and/or current task we're working on to store relevant understandings from this
session in an appendix of either or both documents. Preferably specifics in the task document, or if there's no work context, the epic itself. **Include a reference to the added content from out.HANDOFF.md**

**What.**

- where we are: the active epic and task, the last commit and its hash,
  what is committed and what is not, and the exact next step in the words
  the user would use to ask for it;
- how the user works: the planning and implementing cycle, what approval
  looks like, what they expect of prose, questions and commit messages;
- the commands known to work, each with today's numbers beside it, so the
  next session can tell a regression from a baseline;
- the gotchas met this session: shell quirks, tools that lie, stale
  artefacts, test patterns that only work one way;
- the conventions established during the work that the code does not
  state on its own;
- a pointer to the task appendix, telling the next session to start from
  it rather than re-measure;
- anything the user said they would do themselves, such as restarting a
  server, that the next session should not assume is done.

## Writing it

1. Re-read the active task file and the last few commit messages before
   writing, so the note states what was done, not what was planned.
2. Write the appendix first and commit it. Then write the note, reading
   the appendix back so the two do not repeat each other.
3. Check with `git status --short` that the tree is clean. The note is
   gitignored by the `out.*` pattern, so it does not show; confirm that
   with `git check-ignore -v out.HANDOFF.md`.
4. Tell the user, in a short recap, where both pieces are, what the next
   step is, and that the note deletes itself.

## On the other side

The session that finds `out.HANDOFF.md` reads it in full, reads the
appendix it points to, acts on the next step, and deletes it before
doing anything else that could be committed. It does not copy the note's
contents into memory.
