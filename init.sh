#!/usr/bin/env bash
set -euo pipefail

# init.sh — Initialize or reset a project's devcontainer setup.
#
# Usage: init.sh [--reset] [--reset-memory] TARGET_PROJECT_DIR
#   --reset         overwrite baseline files even if they exist
#   --reset-memory  also wipe auto memory (destructive)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESET=0
RESET_MEMORY=0
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)        RESET=1; shift ;;
    --reset-memory) RESET_MEMORY=1; shift ;;
    -h|--help)      echo "Usage: init.sh [--reset] [--reset-memory] TARGET_DIR"; exit 0 ;;
    *)              TARGET="$1"; shift ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "ERROR: target project directory required"; exit 1; }
[[ -d "$TARGET" ]] || { echo "ERROR: $TARGET is not a directory"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

DEVCONTAINER="$TARGET/.devcontainer"
STATE="$TARGET/devcontainer-state"
HOME_CLAUDE="$STATE/claude/.claude"
PROJ_CLAUDE="$TARGET/.claude"

should_seed() { [[ $RESET -eq 1 ]] || [[ ! -f "$1" ]]; }

# merge_json TEMPLATE LIVE
# Template keys win; keys the template does not declare are preserved. That is
# what keeps user preferences (effortLevel, theme) across a --reset while the
# template still owns hooks, permissions, statusLine, and model.
merge_json() {
  python3 - "$1" "$2" <<'PY'
import json, sys
tpl, live = sys.argv[1], sys.argv[2]
template = json.load(open(tpl))
try:
    merged = json.load(open(live))
except Exception:
    merged = {}
merged.update(template)
with open(live, "w") as fh:
    json.dump(merged, fh, indent=2)
    fh.write("\n")
PY
}

# run_jcm_install
# Hands jCodeMunch full ownership of its own configuration: the always-on policy
# block in ~/.claude/CLAUDE.md, AGENTS.md, its hooks, and the agent skill. The
# template deliberately does NOT pin copies of any of these -- a hand-minimised
# subset would silently miss upstream refinements, and `install` skips anything
# it finds "already present", so a stale copy would never be corrected.
#
# Verified safe: idempotent (repeat runs leave CLAUDE.md byte-identical), and it
# preserves unrelated hooks such as memory-gate.py.
#
# What the template DOES pin is the tool surface: `tool_surface=full`, set below
# and in post-create.sh on every creation. Claude Code runs an MCP tool silently
# in plan mode only when the server marks it read-only; under the `counter`
# front door the only query path is order/route, which upstream marks
# non-read-only, so plan mode prompted on every call. On `full` the six core
# read tools load up front, all read-only, and plan mode is silent. A
# `permissions.allow` rule or a PreToolUse `allow` hook cannot reach that gate
# (Claude Code docs: a PreToolUse allow "has no effect" in plan mode), which is
# why the hook this template once pinned is gone (2026-10-28).
#
# Registration is normalised after `install`: one entry, local scope, the
# pinned binary. post-create.sh carries the reasoning; the two must agree.
#
# No-op when the binary is absent -- the normal case when init.sh runs on a host.
run_jcm_install() {
  command -v jcodemunch-mcp >/dev/null 2>&1 || {
    echo "  (jcodemunch-mcp not on PATH -- configured at container build instead)"
    return 0
  }
  echo "  Running jcodemunch-mcp install..."

  # install_agents_md() writes to Path.cwd(), so run from the target project or
  # AGENTS.md lands wherever init.sh happened to be invoked from.
  #
  # CLAUDE_CONFIG_DIR steers `claude mcp add` but NOT jcodemunch-mcp itself,
  # which resolves the global config from HOME (verified 2026-09-20: pointing
  # only CLAUDE_CONFIG_DIR at a scratch dir left it reporting, and reading,
  # /home/node/.claude). That is right in the normal case -- inside a project's
  # own container ~/.claude IS its devcontainer-state mount -- but running
  # init.sh from inside one container against a DIFFERENT project configures
  # this container's ~/.claude, not the target's.
  local had_agents=0
  [[ -f "$TARGET/AGENTS.md" ]] && had_agents=1

  # Surface before install, so install and the policy refresh see `full`.
  jcodemunch-mcp config set tool_surface full       || echo "  WARNING: config set tool_surface failed" >&2
  jcodemunch-mcp config set surface_offer_seen true || echo "  WARNING: config set surface_offer_seen failed" >&2

  ( cd "$TARGET" && CLAUDE_CONFIG_DIR="$HOME_CLAUDE" \
      jcodemunch-mcp install claude-code --skills --skills-scope global ) \
    || echo "  WARNING: jcodemunch-mcp install returned non-zero" >&2

  # Upstream bug: `install <agent>` writes AGENTS.md unconditionally, while the
  # sibling Cursor/Windsurf policies gate on `<name> in selected_names`. AGENTS.md
  # should gate on {"Codex","opencode"} & selected_names -- both ARE detected
  # clients (cli/init.py:313-318), so the gate is available and simply unused.
  # Claude Code never reads AGENTS.md, so for a claude-code-only install it is
  # pure litter.
  #
  # Conditional on purpose, twice over:
  #   - only when install CREATED it (had_agents==0), so an authored AGENTS.md
  #     that install merely appended to is never destroyed;
  #   - only when it exists, so this quietly becomes a no-op if upstream fixes
  #     the gate. Nothing to un-wire later.
  if [[ $had_agents -eq 0 && -f "$TARGET/AGENTS.md" ]]; then
    rm -f "$TARGET/AGENTS.md"
    echo "  removed AGENTS.md (install writes it unconditionally; Claude Code does not read it)"
  fi

  # The policy block follows the surface; everything outside it is left alone.
  CLAUDE_CONFIG_DIR="$HOME_CLAUDE" jcodemunch-mcp claude-md --refresh --yes \
    || echo "  WARNING: policy block not refreshed; run: jcodemunch-mcp claude-md --refresh" >&2

  # Local scope is keyed by the launch directory, /workspace in every container
  # of this family, so the normalisation only makes sense from inside one.
  if [[ "$TARGET" == /workspace ]] && command -v claude >/dev/null 2>&1; then
    ( cd "$TARGET" && export CLAUDE_CONFIG_DIR="$HOME_CLAUDE" && \
      { claude mcp remove jcodemunch -s user  >/dev/null 2>&1 || true; } && \
      { claude mcp remove jcodemunch -s local >/dev/null 2>&1 || true; } && \
      claude mcp add -s local jcodemunch "$HOME/.local/bin/jcodemunch-mcp" ) \
      || echo "  WARNING: MCP registration failed" >&2
  fi
}

# --- .devcontainer/ ---
echo "Setting up .devcontainer/..."
mkdir -p "$DEVCONTAINER"
cp "$SCRIPT_DIR/dot_devcontainer/Dockerfile" "$DEVCONTAINER/"
cp "$SCRIPT_DIR/dot_devcontainer/init-firewall.sh" "$DEVCONTAINER/"
cp "$SCRIPT_DIR/dot_devcontainer/post-create.sh" "$DEVCONTAINER/"

# The jCodeMunch file watcher, baseline-owned like the scripts above.
#
# Two pieces, and they are separate on purpose:
#   - jcodemunch-watch/ is a local devcontainer Feature. install.sh puts
#     jcodemunch-mcp (with watchfiles) into the IMAGE, and launch.sh is spliced
#     into PID 1's startup so the watcher starts before postCreateCommand runs.
#   - start-jcodemunch-watch.sh holds the actual logic and is read from the
#     workspace at every container start, so editing it needs a restart, not a
#     rebuild.
# Both files explain the reasoning at length; read them before changing either.
#
# The directory is replaced rather than merged, so a file dropped from the
# template does not linger in the project.
cp "$SCRIPT_DIR/dot_devcontainer/start-jcodemunch-watch.sh" "$DEVCONTAINER/"
chmod +x "$DEVCONTAINER/start-jcodemunch-watch.sh"
rm -rf "$DEVCONTAINER/jcodemunch-watch"
cp -r "$SCRIPT_DIR/dot_devcontainer/jcodemunch-watch" "$DEVCONTAINER/"
chmod +x "$DEVCONTAINER/jcodemunch-watch/install.sh" "$DEVCONTAINER/jcodemunch-watch/launch.sh"

# The deferred egress firewall: a second local Feature, same mechanism as the
# watcher's launch.sh and for the same reason -- a background process started
# from postStartCommand does not survive the hook (measured 2026-10-25; the
# container ran wide open). init-firewall.sh (copied above) and its sudoers rule
# belong to the Dockerfile; this Feature only owns the PID 1 entrypoint that
# launches it in --after-extensions mode. Replaced, not merged, like the watcher.
rm -rf "$DEVCONTAINER/firewall-deferred"
cp -r "$SCRIPT_DIR/dot_devcontainer/firewall-deferred" "$DEVCONTAINER/"
chmod +x "$DEVCONTAINER/firewall-deferred/install.sh" "$DEVCONTAINER/firewall-deferred/launch.sh"

if should_seed "$DEVCONTAINER/devcontainer.json"; then
  cp "$SCRIPT_DIR/dot_devcontainer/devcontainer.json" "$DEVCONTAINER/"
fi

# devcontainer.json is seeded only when missing (or on --reset), so an existing
# project keeps its own -- and would then carry the watcher's files without ever
# registering the Feature that installs and starts them. That is worse than not
# copying them: post-create.sh no longer installs jcodemunch-mcp itself, because
# the Feature is supposed to have done it at image build. Say so loudly rather
# than leave a container with no jcodemunch-mcp and a watcher that never runs.
if ! grep -q "jcodemunch-watch" "$DEVCONTAINER/devcontainer.json"; then
  echo "  WARNING: $DEVCONTAINER/devcontainer.json does not register the" >&2
  echo "           jcodemunch-watch Feature. Add this to its \"features\" block:" >&2
  echo "               \"./jcodemunch-watch\": {}" >&2
  echo "           or re-run with --reset to take the template's copy." >&2
  echo "           Until then jcodemunch-mcp is not installed and the index" >&2
  echo "           updates on Edit/Write only, so it WILL drift." >&2
fi
if ! grep -q "firewall-deferred" "$DEVCONTAINER/devcontainer.json"; then
  echo "  WARNING: $DEVCONTAINER/devcontainer.json does not register the" >&2
  echo "           firewall-deferred Feature. Add this to its \"features\" block:" >&2
  echo "               \"./firewall-deferred\": {}" >&2
  echo "           and drop any postStartCommand that runs init-firewall.sh" >&2
  echo "           (set \"waitFor\" to \"postCreateCommand\"). Until then the" >&2
  echo "           egress firewall never comes up: the Feature is what starts it." >&2
fi

# --- devcontainer-state/ (mount targets) ---
echo "Setting up devcontainer-state/..."
mkdir -p "$HOME_CLAUDE"
mkdir -p "$STATE/commandhistory/commandhistory"

# --- ~/.claude/ baseline files ---
echo "Seeding ~/.claude/ baseline..."
if should_seed "$HOME_CLAUDE/CLAUDE.md"; then
  cp "$SCRIPT_DIR/home_dot_claude/CLAUDE.md" "$HOME_CLAUDE/"
fi
# statusline always overwrites (baseline-owned).
# settings.json: full overwrite on init/--reset-memory; merge on --reset so an
# in-flight session keeps its preferences.
if [[ $RESET -eq 1 && -f "$HOME_CLAUDE/settings.json" ]]; then
  merge_json "$SCRIPT_DIR/home_dot_claude/settings.json" "$HOME_CLAUDE/settings.json"
else
  cp "$SCRIPT_DIR/home_dot_claude/settings.json" "$HOME_CLAUDE/"
fi
cp "$SCRIPT_DIR/home_dot_claude/statusline-context.py" "$HOME_CLAUDE/"
chmod +x "$HOME_CLAUDE/statusline-context.py"
# rules/ always overwrite (baseline-owned)
mkdir -p "$HOME_CLAUDE/rules"
cp "$SCRIPT_DIR/home_dot_claude/rules/"*.md "$HOME_CLAUDE/rules/"
# hooks/ always overwrite (baseline-owned)
mkdir -p "$HOME_CLAUDE/hooks"
cp "$SCRIPT_DIR/home_dot_claude/hooks/"*.py "$HOME_CLAUDE/hooks/"
chmod +x "$HOME_CLAUDE/hooks/"*.py

# --- <workspace>/.claude/ ---
echo "Seeding project .claude/..."
mkdir -p "$PROJ_CLAUDE/skills/implement"
if [[ ! -f "$PROJ_CLAUDE/settings.json" ]]; then
  cp "$SCRIPT_DIR/project_dot_claude/settings.json" "$PROJ_CLAUDE/"
elif [[ $RESET -eq 1 ]]; then
  merge_json "$SCRIPT_DIR/project_dot_claude/settings.json" "$PROJ_CLAUDE/settings.json"
fi
if should_seed "$PROJ_CLAUDE/skills/implement/SKILL.md"; then
  cp "$SCRIPT_DIR/project_dot_claude/skills/implement/SKILL.md" "$PROJ_CLAUDE/skills/implement/"
fi

# --- <workspace>/docs/invariants.md ---
# The project's global rules; the implement skill checks every change against
# them. Seeded when missing and NEVER overwritten -- not even by --reset, and
# deliberately not via should_seed. From the moment it exists the file is the
# project's own: its rules get added, reworded and amended there, and a reset
# that restored the template's copy would silently erase them.
if [[ ! -f "$TARGET/docs/invariants.md" ]]; then
  echo "Seeding docs/invariants.md..."
  mkdir -p "$TARGET/docs"
  cp "$SCRIPT_DIR/project_docs/invariants.md" "$TARGET/docs/"
fi

# --- jCodeMunch ---
# Runs on init, --reset and --reset-memory alike. Placed after settings.json is
# written so install re-applies its hooks on top of the freshly-seeded baseline;
# that is what makes --reset self-healing rather than a churn cycle.
echo "Configuring jCodeMunch..."
run_jcm_install

# --- Memory ---
if [[ $RESET_MEMORY -eq 1 ]]; then
  echo "Wiping auto memory..."
  shopt -s nullglob
  for m in "$HOME_CLAUDE"/projects/*/memory; do rm -rf "$m"; done
  shopt -u nullglob
fi

# --- .gitignore ---
if [[ ! -f "$TARGET/.gitignore" ]] || ! grep -q "devcontainer-state/" "$TARGET/.gitignore"; then
  echo "Adding devcontainer-state/ to .gitignore..."
  echo "devcontainer-state/" >> "$TARGET/.gitignore"
fi

echo ""
echo "Done."
