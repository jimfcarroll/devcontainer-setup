# devcontainer-setup

A template and an installer for a sandboxed Claude Code devcontainer. Running
`init.sh` against a project stamps in a `.devcontainer/`, a bind-mounted home for
Claude Code's state, a baseline `~/.claude/` configuration, a project-level
`implement` skill and a `docs/invariants.md`. A project that uses it keeps a
clone at `related/devcontainer-setup`, gitignored, for reference.

## What the container provides

- Claude Code runs as the native binary under the `node` user on a `node:20`
  image with Python 3.14, `uv`, zsh, `gh` and `git-delta`.
- An egress firewall (`init-firewall.sh`) drops everything except GitHub, npm,
  PyPI, Anthropic, the VS Code marketplace and outbound SSH. The
  `firewall-deferred` Feature launches it from PID 1, and it waits for
  post-create and for VS Code's extension installs to settle before locking
  down, because both need hosts the allowlist cannot carry. The container has
  open egress until then.
- The jCodeMunch MCP server is installed into the image by the
  `jcodemunch-watch` Feature and registered, configured and indexed by
  `post-create.sh`. The same Feature starts a file watcher from PID 1 so the
  index follows git and shell edits, not only Claude's Edit and Write tools.
- State survives rebuilds. `~/.claude` and the shell history are bind mounts of
  `devcontainer-state/` in the project, which `init.sh` adds to the project's
  `.gitignore`.
- `post-create.sh` builds a `.venv` from `requirements.txt` or `pyproject.toml`
  when either exists.

## Layout

| Directory | Lands at |
|---|---|
| `dot_devcontainer/` | `<project>/.devcontainer/` |
| `home_dot_claude/` | `<project>/devcontainer-state/claude/.claude/`, mounted as `/home/node/.claude` |
| `project_dot_claude/` | `<project>/.claude/` |
| `project_docs/` | `<project>/docs/` |

`home_dot_claude/` carries the global `CLAUDE.md`, `settings.json`, the
`memory-gate.py` hook that turns auto-memory writes into a permission prompt,
`statusline-context.py` and `rules/safety.md`.

## Usage

```
init.sh [--reset] [--reset-memory] TARGET_PROJECT_DIR
```

Run it from the host before the first container build, and again from inside
the container after pulling a newer template. Which files it touches depends on
who owns them.

- The template owns everything in `.devcontainer/` except `devcontainer.json`,
  plus the statusline, hooks and rules under `~/.claude/`, and overwrites them
  on every run. Change those files here and re-run `init.sh`; a change made
  only in the project is lost on the next run.
- `devcontainer.json`, `~/.claude/CLAUDE.md` and the project's `implement`
  skill are seeded when missing and replaced only by `--reset`.
- Both `settings.json` files are merged on `--reset`, so template keys win and
  user preferences survive. Without `--reset` the home copy is overwritten and
  the project copy is seeded only when missing.
- `docs/invariants.md` is never overwritten, not even by `--reset`. Once seeded
  it belongs to the project.
- `--reset-memory` wipes Claude's auto-memory under `~/.claude/projects/*/memory`.
  It does not imply `--reset`.

When `jcodemunch-mcp` is on `PATH`, which is only the case inside a container,
`init.sh` also re-runs its installer so its policy block, hooks and MCP
registration are laid back over the fresh baseline. On a host that step is
skipped, and `post-create.sh` does it at container creation.

The scripts carry their reasoning in comments. Read them before changing the
startup order, the firewall mode or where the watcher is launched; each has
been wrong before in a way that was measured and written down there.
