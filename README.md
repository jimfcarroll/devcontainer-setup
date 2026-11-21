# devcontainer-setup

A template and an installer for a sandboxed Claude Code devcontainer. Running
`init.sh` against a project stamps in a `.devcontainer/`, a bind-mounted home for
Claude Code's state, a baseline `~/.claude/` configuration, a project-level
`implement` skill and a `docs/invariants.md`. A project that uses it keeps a
clone at `related/devcontainer-setup`, gitignored, for reference.

## What the container provides

- Claude Code runs as the native binary under the `node` user on a `node:20`
  image with Python 3.14, `uv`, zsh, `gh`, `git-delta`, and Chromium's headless
  shell with its libraries, baked in so Playwright can take screenshots behind
  the firewall.
- An egress firewall (`init-firewall.sh`) drops everything except GitHub, npm,
  PyPI, Anthropic, the VS Code marketplace, outbound SSH, and any hosts the
  project adds. The
  `firewall-deferred` Feature launches it from PID 1, and it waits for
  post-create and for VS Code's extension installs to settle before locking
  down, because both need hosts the allowlist cannot carry. The container has
  open egress until then.
- The jCodeMunch MCP server is installed into the image by the
  `jcodemunch-watch` Feature and registered, configured and indexed by
  `post-create.sh`. The same Feature starts a file watcher from PID 1 so the
  index follows git and shell edits, not only Claude's Edit and Write tools.
  The template leaves out jCodeMunch's policy block and steering hooks, to keep
  `CLAUDE.md` short, and `CLAUDE.md` carries a two-sentence rule instead.
- State survives rebuilds. `~/.claude` and the shell history are bind mounts of
  `devcontainer-state/` in the project, which `init.sh` adds to the project's
  `.gitignore`.
- `post-create.sh` builds a `.venv` from `requirements.txt` or `pyproject.toml`
  when either exists.
- The image has two layers. The template's `Dockerfile` is a base image that
  every project on the same template version shares, and each project adds its
  own layer in `.devcontainer/project-specific/Dockerfile`. See
  [Extending the image for one project](#extending-the-image-for-one-project).

## Layout

| In the template | Lands at |
|---|---|
| `dot_devcontainer/` | `<project>/.devcontainer/` |
| `home_dot_claude/` | `<project>/devcontainer-state/claude/.claude/`, mounted as `/home/node/.claude` |
| `project_dot_claude/` | `<project>/.claude/` |
| `project_docs/` | `<project>/docs/` |
| `conf.sh` | `<project>/.devcontainer/conf.sh` |

`conf.sh` holds the template's settings as bash assignments. They are
`BASE_IMAGE_VERSION`, the version of the shared base image, and the firewall's
`FIREWALL_ALLOWED_DOMAINS` and `FIREWALL_ALLOW_ALL`. A project adds to them in
`.devcontainer/project-specific/conf.sh`; see
[Opening the firewall for one project](#opening-the-firewall-for-one-project).

`home_dot_claude/` carries the global `CLAUDE.md`, `settings.json`, the
`memory-gate.py` hook that turns auto-memory writes into a permission prompt,
`statusline-context.py`, `rules/safety.md` and `rules/invariants.md`, the global
invariants (G1 to G3) that every session loads.

## Usage

```
init.sh [--reset] [--reset-memory] TARGET_PROJECT_DIR
```

Run it from the host before the first container build, and again from inside
the container after pulling a newer template. Which files it touches depends on
who owns them.

- The template owns everything in `.devcontainer/` except `devcontainer.json`
  and `project-specific/`, including the copy of `conf.sh`, plus
  `CLAUDE.md`, the statusline, hooks and rules under `~/.claude/`, and
  overwrites them on every run. Change those files here and re-run `init.sh`;
  a change made only in the project is lost on the next run.
- `devcontainer.json` and the project's `implement` skill are seeded when
  missing and replaced only by `--reset`.
- `.devcontainer/project-specific/`, which holds a `Dockerfile` and a `conf.sh`,
  is seeded file by file when missing and never overwritten, not even by
  `--reset`, because it holds the project's own layer of the image and its own
  settings.
- The home `settings.json` is merged on every run: template keys win, and the
  choices Claude Code writes itself, such as model and effort, survive. The
  project copy is seeded when missing and merged on `--reset`.
- `docs/invariants.md` is never overwritten, not even by `--reset`. Once seeded
  it belongs to the project and holds only that project's rules; the global
  rules are `rules/invariants.md`.
- `--reset-memory` wipes Claude's auto-memory under `~/.claude/projects/*/memory`.
  It does not imply `--reset`.

When `jcodemunch-mcp` is on `PATH`, which is only the case inside a container,
`init.sh` also re-runs its installer so its hooks, skill and MCP registration
are laid back over the fresh baseline. On a host that step is
skipped, and `post-create.sh` does it at container creation.

The scripts carry their reasoning in comments. Read them before changing the
startup order, the firewall mode or where the watcher is launched; each has
been wrong before in a way that was measured and written down there.

## Extending the image for one project

The container image is built in two layers, so that a project's own packages
never have to go into the template.

1. `devcontainer.json` runs `.devcontainer/ensure-base-image.sh` as its
   `initializeCommand`, on the host, before the container build. The script
   reads `BASE_IMAGE_VERSION` from `.devcontainer/conf.sh` and builds the
   template's `Dockerfile` as `devcontainer-base:<version>`, but only when that
   image does not exist yet. Every project on the same template version shares
   it. The script then tags it `devcontainer-base:project-${devcontainerId}`, an
   alias that belongs to this project alone.
2. `devcontainer.json` then builds `.devcontainer/project-specific/Dockerfile`,
   which starts `FROM` that alias. Its build context is `project-specific/`, so
   a `COPY` there takes paths relative to that directory.

The alias is what lets `devcontainer.json` stay untouched across template
versions. A project on version 1 and a project on version 2 each point their
alias at their own base image, and a container start re-points the alias, so a
project that is stamped with a newer template picks up the new base image on
its next rebuild.

The seeded `project-specific/Dockerfile` adds nothing of its own except its last
step, which copies `project-specific/conf.sh` into the image. A project puts its
system packages, tools and files above that step. The base image ends as the
`node` user, so a step that needs root switches to `USER root` and switches back
to `USER node` before the end.

### Opening the firewall for one project

`.devcontainer/project-specific/conf.sh` holds the project's additions to the
template's settings. To let the container reach more hosts, append them to the
template's list:

```bash
FIREWALL_ALLOWED_DOMAINS+=("repo.maven.apache.org" "repo1.maven.org")
```

To lift the firewall entirely, set `FIREWALL_ALLOW_ALL=true`.

Then rebuild the container. A plain restart, or running
`sudo /usr/local/bin/init-firewall.sh` again, is not enough. `init-firewall.sh`
runs as root, and the `node` user can run it through sudo, so it never reads the
copies of `conf.sh` in the workspace, which anything in the container can edit.
It reads only the copies baked into the image as root: the template's from the
base image, and the project's from the last step of `project-specific/Dockerfile`.
Each file must be owned by root and writable by no one else, or the firewall
refuses it. Keep both files to plain assignments, because they are sourced.

### Changing the base image

Bump `BASE_IMAGE_VERSION` in `conf.sh` whenever you change
`dot_devcontainer/Dockerfile` or a file it copies, such as `init-firewall.sh` or
`conf.sh` itself.
The script builds the base image only when its tag is missing, so without a bump
every project keeps using the image it already has. Re-run `init.sh` to carry
the new version into a project, and rebuild its container.

### Refreshing the base image

VS Code's "Rebuild Without Cache" rebuilds only the project's layer. The
devcontainer tooling never tells `initializeCommand` which rebuild was chosen,
so the base image keeps its cached layers. To refresh it, for example to pick
up newer packages or a newer `node:20`, run this on the host:

```
.devcontainer/ensure-base-image.sh --rebuild
```

It rebuilds the current version with `--no-cache --pull`. Then rebuild the
container normally. The container start re-points the project's alias at the
fresh image, and the project's layer is rebuilt on top of it. Other projects on
the same version pick up the refreshed image the next time they rebuild.

### Removing old base images

Old versions stay in Docker's image store until you remove them. List them with
`docker images devcontainer-base` and remove one with `docker image rm`. While a
project's alias still points at the same image, removing the version's tag
frees no space, because Docker only drops that one tag, so remove the aliases of
projects you no longer use as well.

### Limits

- The host runs `ensure-base-image.sh` with `bash` on every container start, so
  a host without bash, such as Windows outside WSL, cannot build the container.
- The project build finds the alias only in the local Docker image store. The
  default buildx builder reads that store, but a builder that uses the
  `docker-container` driver does not, and it fails trying to pull the alias.
- The firewall resolves each allowed host to its addresses once, when the rules
  are applied. A host behind a CDN, such as Maven Central or PyPI, can move to
  new addresses during a long session. Running
  `sudo /usr/local/bin/init-firewall.sh` resolves them again.
