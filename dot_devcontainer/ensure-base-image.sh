#!/usr/bin/env bash
#
# ensure-base-image.sh [--rebuild] [ALIAS]
#
# Makes sure the template's shared base image exists, and optionally points a
# project's alias at it. It runs on the HOST, not in the container:
# devcontainer.json names it as the initializeCommand, which the devcontainer
# tooling runs on the host before it builds the container image.
#
# The base image is built from the Dockerfile next to this script and tagged
# devcontainer-base:<version>, where the version is BASE_IMAGE_VERSION in the
# conf.sh next to this script. Every project on the same template version
# shares that image, so it is built only when it is missing. The container image
# itself is built from project-specific/Dockerfile, which starts FROM ALIAS.
# devcontainer.json passes devcontainer-base:project-${devcontainerId} as ALIAS,
# and this script re-points that alias at the current version on every start, so
# devcontainer.json never has to change when the version does.
#
# VS Code's "Rebuild Without Cache" cannot reach this image, because the
# devcontainer tooling never tells initializeCommand that it was chosen. To
# refresh the base image, run this script by hand with --rebuild, which builds
# the current version again with --no-cache --pull, and then rebuild the
# container normally.
#
# The project build finds ALIAS only in the local Docker image store. That is
# where the default buildx builder looks, but a builder that uses the
# docker-container driver cannot see local images and tries to pull it instead.
#
# This runs on whatever bash the host has, which on macOS is 3.2, so it avoids
# features newer than that.
set -euo pipefail

usage() {
    echo "usage: $(basename "$0") [--rebuild] [ALIAS]" >&2
    exit 2
}

fail() {
    echo "ensure-base-image.sh: $*" >&2
    exit 1
}

rebuild=0
alias_name=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rebuild) rebuild=1; shift ;;
        -h|--help) usage ;;
        -*)        echo "unknown option: $1" >&2; usage ;;
        *)         [ -z "$alias_name" ] || usage; alias_name="$1"; shift ;;
    esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
conf="$here/conf.sh"

command -v docker >/dev/null 2>&1 \
    || fail "docker is not on PATH. This script runs on the host, which needs the Docker CLI."
[ -f "$conf" ] \
    || fail "$conf is missing. Re-run the template's init.sh to restore it."

# conf.sh is sourced in a subshell, so the only thing it hands this script is the
# one value printed back. The version is cleared first so that a value already
# in the host's environment cannot stand in for a missing one. The project's own
# project-specific/conf.sh is not read, because the base image's version belongs
# to the template.
version="$(BASE_IMAGE_VERSION=""; . "$conf" && printf '%s' "$BASE_IMAGE_VERSION")" \
    || fail "$conf could not be sourced."
[ -n "$version" ] \
    || fail "$conf does not set BASE_IMAGE_VERSION."

# A Docker tag is at most 128 characters: a letter, digit or underscore,
# followed by letters, digits, underscores, periods and dashes.
tag_re='^[A-Za-z0-9_][A-Za-z0-9_.-]*$'
if [[ ! "$version" =~ $tag_re ]] || [ "${#version}" -gt 128 ]; then
    fail "BASE_IMAGE_VERSION \"$version\" in $conf is not a valid Docker tag."
fi

image="devcontainer-base:$version"

if [ "$rebuild" -eq 1 ]; then
    echo "Rebuilding the devcontainer base image $image from scratch..."
    docker build --no-cache --pull --tag "$image" --file "$here/Dockerfile" "$here"
elif docker image inspect "$image" >/dev/null 2>&1; then
    echo "The devcontainer base image $image already exists."
else
    echo "Building the devcontainer base image $image..."
    docker build --tag "$image" --file "$here/Dockerfile" "$here"
fi

if [ -n "$alias_name" ]; then
    docker tag "$image" "$alias_name"
    echo "Tagged $image as $alias_name."
fi
