#!/usr/bin/env bash
set -euo pipefail

# Tell the deferred firewall (firewall-deferred Feature) that post-create is
# over, whatever the outcome. It waits for this marker before locking the
# network down, because the steps below reach hosts the allowlist does not
# carry (the embedding model comes from huggingface.co). EXIT trap, not a last
# line: a failed post-create must still let the firewall come up.
PC_MARKER=/home/node/.devcontainer/.post-create-finished
mkdir -p "$(dirname "$PC_MARKER")"
trap 'echo "exit=$? at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PC_MARKER"' EXIT

# --- Universal tooling (system Python) ---
pip3 install --upgrade pip
pip3 install uv
# jcodemunch-mcp itself is NOT installed here.  The jcodemunch-watch Feature
# (.devcontainer/jcodemunch-watch/install.sh) installs it, with watchfiles, at
# image build -- because that Feature's entrypoint starts the watcher from PID 1,
# which on a fresh rebuild runs BEFORE this script.  The jCodeMunch section at
# the bottom still registers the MCP client and indexes the workspace.

# --- Source .env in all shells (unconditional) ---
ENV_SOURCE='[ -f /workspace/.env ] && set -a && source /workspace/.env && set +a'
grep -qF "$ENV_SOURCE" /home/node/.bashrc 2>/dev/null || echo "$ENV_SOURCE" >> /home/node/.bashrc
grep -qF "$ENV_SOURCE" /home/node/.zshrc 2>/dev/null || echo "$ENV_SOURCE" >> /home/node/.zshrc

# --- Project Python detection (.venv) ---
cd /workspace

# Every step is guarded with `|| PY_OK=0` so a failure here is recorded but does
# not abort the script -- `set -euo pipefail` would otherwise let a broken venv
# take the unrelated jCodeMunch section below down with it.
#
# Do NOT "simplify" this into `( set -e; ... ) || PY_OK=0`. Bash disables errexit
# inside any compound command whose status is tested by || or if, so the subshell
# runs to completion and reports the last command's status -- failures vanish.
PY_OK=1
if [ -f requirements.txt ] || [ -f pyproject.toml ]; then
    echo "Python project detected, setting up .venv..."

    # --clear --force is required, not cosmetic. /workspace is bind-mounted, so a
    # .venv built by the PREVIOUS container survives a rebuild while the
    # interpreter it symlinks to does not.
    #   bare `uv venv`        -> exit 2, "A virtual environment already exists"
    #                            (or an interactive prompt when a TTY is attached)
    #   `--clear`             -> exit 2 when .venv exists but is NOT a valid venv,
    #                            i.e. the wreckage a previously-aborted run leaves
    #   `--clear --force`     -> removes whatever is there and rebuilds
    # The venv belongs to the container, not the workspace, so recreating it once
    # per container creation is the correct semantics; deps reinstall just below.
    uv venv --clear --force .venv || PY_OK=0

    if [ $PY_OK -eq 1 ] && [ -f requirements.txt ]; then
        echo "Installing requirements.txt..."
        uv pip install -r requirements.txt --python .venv/bin/python || PY_OK=0
    fi

    if [ $PY_OK -eq 1 ] && [ -f pyproject.toml ]; then
        echo "Installing project (editable) from pyproject.toml..."
        uv pip install -e . --python .venv/bin/python || PY_OK=0
    fi

    if [ $PY_OK -eq 0 ]; then
        cat >&2 <<'EOF'

================================================================
ERROR: Python environment setup failed.

  Recover without rebuilding the container:
    cd /workspace
    uv venv --clear --force .venv
    uv pip install -r requirements.txt --python .venv/bin/python
================================================================

EOF
    fi
else
    echo "No Python project detected, skipping .venv setup"
fi

# --- jCodeMunch: register the MCP client and index the workspace -------------
# Deliberately LAST: this section exits non-zero on failure, and the Python
# environment above must survive a jCodeMunch problem. Being last also puts the
# error banner at the bottom of the creation log, where it is actually seen.
# Runs at postCreateCommand: once per container creation (a rebuild re-runs it;
# stop/start and reattach do not), and BEFORE postStartCommand — therefore before
# init-firewall.sh. That ordering is load-bearing: the embedding model
# (all-MiniLM-L6-v2, ~90MB) is fetched from huggingface.co, which is not in the
# firewall allowlist. Post-firewall the download dies on OUTPUT DROP.
#
# Installing the binary is not enough on its own. Without the client
# registration the hooks in ~/.claude/settings.json fire against a server that
# was never started, and without an index every tool call returns nothing.
#
# The tool surface is set here too, to `full`, on every creation: it lives in
# ~/.code-index/config.jsonc on the container filesystem, and a fresh config is
# born saying `counter`. See the comment above the `config set` lines.
JCM=/home/node/.local/bin/jcodemunch-mcp
JCM_MARKER=/home/node/.jcodemunch-broken   # container FS, NOT the ~/.claude mount:
                                           # dies with the container it describes

jcm_fail() {
  cat >&2 <<EOF

================================================================
ERROR: jCodeMunch setup failed -- $1

  Recover without rebuilding the container:
    jcodemunch-mcp config set tool_surface full
    jcodemunch-mcp install claude-code --skills --skills-scope global
    jcodemunch-mcp claude-md --refresh --yes
    claude mcp add -s local jcodemunch /home/node/.local/bin/jcodemunch-mcp
    jcodemunch-mcp index /workspace
    jcodemunch-mcp health

  Marker: $JCM_MARKER (removed once health is clean)
================================================================

EOF
  touch "$JCM_MARKER"
  exit 1
}

# Surface first: the server, the steering hook and the policy block all read
# it, and a fresh container's config.jsonc is born saying "counter". `full`
# because Claude Code defers MCP tools anyway and loads jcodemunch's six core
# read tools up front (1.108.389), all annotated read-only, so plan mode runs
# them silently; under `counter` the only query path is order/route, which
# upstream marks non-read-only, and plan mode prompted on every call
# (2026-10-28: 32 dialogs in one session). surface_offer_seen stops the "a new
# install would default to counter" row from nagging in every container.
echo "jCodeMunch: tool surface -> full"
"$JCM" config set tool_surface full       || jcm_fail "config set tool_surface"
"$JCM" config set surface_offer_seen true || jcm_fail "config set surface_offer_seen"

# Let jCodeMunch own its own configuration: MCP registration, the always-on
# policy block in ~/.claude/CLAUDE.md, AGENTS.md, its hooks, and the agent skill.
# The template pins none of these on purpose -- `install` skips whatever it finds
# "already present", so a hand-maintained copy here would freeze at whatever the
# tool looked like the day it was written and never pick up refinements.
#
# Verified: idempotent across repeat runs, and it preserves unrelated hooks such
# as memory-gate.py.
echo "jCodeMunch: installing (registration, policy, hooks, skill)..."
# cwd is /workspace here (set above), which is where install_agents_md() writes.
JCM_HAD_AGENTS=0
[[ -f /workspace/AGENTS.md ]] && JCM_HAD_AGENTS=1

"$JCM" install claude-code --skills --skills-scope global || \
  echo "WARNING: jcodemunch-mcp install returned non-zero; asserts below decide." >&2

# Upstream bug: `install <agent>` writes AGENTS.md unconditionally, while the
# sibling Cursor/Windsurf policies gate on `<name> in selected_names`. AGENTS.md
# should gate on {"Codex","opencode"} & selected_names -- both ARE detected
# clients (cli/init.py:313-318), so the gate exists and is simply unused. Claude
# Code never reads AGENTS.md (confirmed: it is absent from /context's memory-file
# list), so on a claude-code-only install the file is pure litter.
#
# Conditional on purpose, twice over:
#   - only when install CREATED it, so an authored AGENTS.md that install merely
#     appended to is never destroyed;
#   - only when it exists, so this becomes a silent no-op once upstream fixes the
#     gate. Nothing to un-wire later.
if [[ $JCM_HAD_AGENTS -eq 0 && -f /workspace/AGENTS.md ]]; then
  rm -f /workspace/AGENTS.md
  echo "jCodeMunch: removed AGENTS.md (written unconditionally; Claude Code does not read it)"
fi

# The policy block in ~/.claude/CLAUDE.md follows the surface. `install`
# refreshes a block it finds; this makes that explicit and covers a block
# written under the old surface. Everything outside the block is left alone.
echo "jCodeMunch: refreshing the CLAUDE.md policy block..."
"$JCM" claude-md --refresh --yes || \
  echo "WARNING: policy block not refreshed; run: jcodemunch-mcp claude-md --refresh" >&2

# One registration, one scope, one command. The installer's `claude mcp add`
# carries no scope flag (so, local) and names `uvx jcodemunch-mcp`, a second
# environment that re-resolves the package on a fresh container while the
# hooks and the watcher use the binary the Feature pinned at image build.
# Re-point local at that binary and drop any user-scope twin: here ~/.claude IS
# the project's devcontainer-state, so user and local are one place, and a
# second entry is only a "Conflicting scopes" warning (2026-10-28). Local, not
# user, because local is where the installer checks "already exists" next time.
echo "jCodeMunch: registering the MCP server (local scope, pinned binary)..."
claude mcp remove jcodemunch -s user  >/dev/null 2>&1 || true
claude mcp remove jcodemunch -s local >/dev/null 2>&1 || true
claude mcp add -s local jcodemunch "$JCM" || jcm_fail "MCP registration"

echo "jCodeMunch: indexing /workspace (respects .gitignore)..."
"$JCM" index /workspace || jcm_fail "indexing -- model fetch from huggingface.co?"

# Assert the specific boxes we care about. Never grep for a bare '[ ]':
# install-status permanently reports unchecked entries for cursor_rules,
# windsurf_rules, agents_md, Copilot hooks and both claude_md_* policies, so a
# blanket check would fail every time.
jcm_status="$("$JCM" install-status 2>&1)" || jcm_fail "install-status did not run"
grep -q '\[x\] Claude Code'          <<<"$jcm_status" || jcm_fail "MCP client not registered"
grep -q '\[x\] Claude settings.json' <<<"$jcm_status" || jcm_fail "hooks not registered"
[[ -f /home/node/.claude/skills/jcodemunch/SKILL.md ]] || \
  echo "WARNING: agent skill missing -- MCP tools still work." >&2

# health is the real gate: exit codes say whether THIS run worked, health says
# whether the system IS working.
"$JCM" health >/dev/null 2>&1 || jcm_fail "health check -- repo not indexed"
"$JCM" surface 2>/dev/null | grep -q '^Surface: full' || jcm_fail "tool surface is not 'full'"

rm -f "$JCM_MARKER"
echo "jCodeMunch: ready."

# Surfaced last: the Python section above is non-fatal so jCodeMunch still runs,
# but a failure there must still make postCreate exit non-zero.
if [ "${PY_OK:-1}" -ne 1 ]; then
    echo "post-create finished, but the Python environment failed (see above)." >&2
    exit 1
fi
