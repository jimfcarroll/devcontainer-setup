---
name: flesh-out-task
description: How a task file is laid out, how its sub-tasks are grouped into commits, and how the plan for fleshing out a task and the plan for a commit are written. Invoke when the user asks to plan to flesh out a task, to re-flesh one, or to plan a commit of one.
argument-hint: "[task N of epic NNN]"
---

# Fleshing Out a Task

A task is fleshed out when its work starts. Fleshing it out decides what the
task does, records those decisions in its file, and groups its sub-tasks into
commits. This skill holds everything that is planned: the task file's outline,
what each commit holds, and the outline of each plan. The `implement` skill
holds how an approved commit plan is carried out and committed.

## Which task

The task to plan is the one this text describes: $ARGUMENTS

The text can describe the task in any words, such as "task 3 of epic 007" or
"the next task of the active epic". When it names no epic, the task is in the
epic in `epics/active/`. The next task of an epic is its first task, in the
order of the `task-NNN_` prefixes, that still has a box left unticked. When
the text is empty, take the task from the user's request. Ask which task is
meant only when the description fits no task or fits more than one. The plan's
Context names the task's file, so that the user can see which task was chosen.

## Before planning

All planning happens in plan mode, which `EnterPlanMode` enters. Before
anything else, read `epics/README.md`, the epic's `epic.md`, the task file, and the earlier tasks of the epic, together with their appendices and
the gaps their landing notes list. Read both invariants files as well, the
global one in `~/.claude/rules/invariants.md` and the project's in
`docs/invariants.md`, because a design that breaks one is wrong however well
it is built. A fact that an appendix already records is not measured again.

## Fleshing out a task

1. Measure what the appendices lack. Read the code. Try a package in a
   throwaway environment, so that the project is not touched. Check behaviour
   against a scratch database, never against a real data directory.
2. Write a plan for the documents. It opens with a Context and then gives the
   facts measured this session, naming the commit they were read at. It sets
   out each decision the user must make, with one recommendation and its
   reasons. It says what each document will hold, which means the task file
   and also the epic or any other task the work changes. It ends with the
   steps and the gaps to record.
3. Paste the whole plan into the reply, and then call `ExitPlanMode`. When the
   user rejects the plan with a correction, fix the plan, say what was wrong,
   and paste the whole plan again.
4. Once the plan is approved, write the documents. Make no commit. The
   documents wait in the working tree and go in with the task's first code
   commit.

## The outline of a task file

**The title** is `# Task N: <Title>`.

**The Objective** says what the task delivers and why. It says what the app
does today in the area the task changes, naming the modules and symbols
involved. It also says what lies outside the task, and which task or backlog
epic holds that work.

**The Decisions section** opens with a paragraph saying who decided what and
when. Credit each decision to the person who made it, exactly. A rule the user
set is the user's, but a design that only follows from it is not. Each decision
is numbered and opens with a bold sentence that states it, followed by its
reasons. One decision says how many commits make up the task and what each
commit does. An amended decision keeps its number. The opening paragraph dates
the amendment, names the decisions that changed and says why they changed.

**The Sub-tasks section** groups its boxes under one bold line for each
commit, written as `**Commit N: <a lowercase sentence>.**`. That sentence
becomes the commit's subject. A commit can open with a paragraph saying what it
builds on. Its first box is the tests written first and shown failing, and the
box says what the tests will show. The boxes after it are the production
changes. When a box is ticked, it gains a note that begins "Measured on
landing". The note says what was measured and lists the gaps left. When a later
commit replaces that work, the note stays as history.

**The Acceptance criteria** are boxes that state what is true once the task is
done. The last of them says that both suites pass, that every touched Python
file is ruff-clean, and that coverage on changed code is at least 85%. The
task's last commit ticks the criteria, and each one gains a note that begins
"Measured on landing of commit N".

**The Appendix of working notes** is made of dated sections, each with a
heading of the form `### Facts for <subject>, measured on <date>`. Each section
opens by naming the commit it was read at and how its facts were measured. The
facts are bulleted sentences, and each begins with a bold phrase.

**A task that has not been fleshed out** holds only its Objective and its
Acceptance criteria. The Objective names what will be decided when the task is
fleshed out, and the criteria hold at least one box. The rules for what a
checkbox means, and how a task's status follows from its boxes, are in
`epics/README.md` under "Status Is Derived, Never Declared".

## What a commit holds

**A commit is one plan and implement cycle.** Its plan is written and approved
first, and the `implement` skill then carries it out and ends the cycle with
the commit.

**A commit holds whole sub-tasks.** Several sub-tasks may share one commit, and
a sub-task is never split across two commits.

**Group a task's sub-tasks into the fewest commits.** Every cycle costs the
same fixed amount whatever it holds. That cost covers measuring the facts,
writing and approving the plan, the run that shows the tests failing, both
suites, the check against the running app, and the landing notes. So group the
sub-tasks into the fewest commits whose cycles each fit in one session, from
the plan to the commit, with no handoff in between. Split a commit only where
one session would not hold the whole of it, and split it at a point where each
part still stands on its own.

**A commit stands on its own.** After it, the code builds, every suite the
commit touches passes, and the app still starts and works, which the plan's
check against the running app shows. A commit that leaves a route broken until
a later commit does not stand on its own.

**A commit carries its task's updates.** It holds the task file with its ticked
boxes and landing notes. It also holds every other change waiting under
`epics/`, such as edits to the epic, to other tasks or to the backlog, and any
move of an epic between `active/`, `backlog/` and `done/`.

**A commit of documents alone is the exception.** It is made only when the user
asks for one. Otherwise a change to a document waits in the working tree for
the next code commit.

## Planning a commit

The plan for a commit has ten sections, in this order.

1. The Context says what the commit does, why, and what it builds on.
2. Measured this session gives the facts read for this plan and names the
   commit they were read at.
3. Decisions holds those settled while planning, so that the landing notes can
   record them.
4. Files lists each file the commit adds, changes or deletes.
5. Tests first gives each new test and the reason it will fail before the
   production change.
6. Steps gives the order of the work.
7. Expected counts gives the counts each suite should report once the commit
   lands.
8. The check against the running app, or against real data, says what will be
   run and what it should show.
9. Things to eyeball names what the user should look at once the commit lands.
10. Gaps to record names the gaps the commit leaves and does not fix.

The plan is pasted whole and approved in the same way as a plan for fleshing
out. Approval of a commit plan means implementing it, which starts by invoking
the `implement` skill.
