#!/usr/bin/env bash
#
# firewall-deferred Feature -- IMAGE BUILD step.
#
# The firewall script itself (/usr/local/bin/init-firewall.sh) and the sudoers
# rule that lets the remote user run it are the Dockerfile's job, and Features
# build on top of the Dockerfile image, so both exist by the time this runs.
# This Feature only installs the entrypoint PID 1 will call at every start.

set -euo pipefail

if [ ! -x /usr/local/bin/init-firewall.sh ]; then
    echo "firewall-deferred: /usr/local/bin/init-firewall.sh missing -- Dockerfile did not install it" >&2
    exit 1
fi

install -D -m 0755 "$(dirname "$0")/launch.sh" /usr/local/share/firewall-deferred/launch.sh
echo "firewall-deferred: entrypoint installed"
