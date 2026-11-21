# Settings for the devcontainer template.
#
# init.sh copies this file into each project's .devcontainer/ on every run, so a
# project always carries the settings of the template it was last stamped from.
# A project adds to them in .devcontainer/project-specific/conf.sh, which init.sh
# seeds once and never overwrites.
#
# Both files are sourced by bash, so they hold plain assignments and nothing
# else. Two scripts read them.
#   - ensure-base-image.sh reads BASE_IMAGE_VERSION from this file alone, on the
#     host. A project cannot change the version.
#   - init-firewall.sh, in the container, sources the copies that were baked into
#     the image as root: this file from the base image, then the project's file
#     from the project layer. It never reads the copies in the workspace, which
#     anything in the container can edit, so a change to either file reaches the
#     firewall only when the container is rebuilt.

# The version of the shared base image, which ensure-base-image.sh tags as
# devcontainer-base:<version>. Every project on the same version shares that
# image, and a project builds it only when it is missing. Bump this whenever you
# change dot_devcontainer/Dockerfile or anything it copies, which includes
# init-firewall.sh and this file. Without a bump, projects keep using the image
# they already have. The value must be a valid Docker tag, which is at most 128
# characters of letters, digits, ".", "_" and "-", and does not start with "."
# or "-".
BASE_IMAGE_VERSION=1

# The hosts the egress firewall lets the container reach, in addition to
# GitHub's published address ranges, which init-firewall.sh always allows. Each
# host is resolved to its IPv4 addresses once, when the rules are applied. A
# project appends its own hosts with FIREWALL_ALLOWED_DOMAINS+=( ... ).
FIREWALL_ALLOWED_DOMAINS=(
    "registry.npmjs.org"
    "api.anthropic.com"
    "sentry.io"
    "statsig.anthropic.com"
    "statsig.com"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
    "pypi.org"
    "files.pythonhosted.org"
    "claude.ai"
    "downloads.claude.ai"
)

# Set to true to lift the firewall entirely and leave egress unrestricted. A
# project sets it in its own conf.sh. init-firewall.sh treats any value other
# than true or false as false, and warns.
FIREWALL_ALLOW_ALL=false
