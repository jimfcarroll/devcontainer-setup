#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# --- When this script locks the network down ---------------------------------
#
# Default: immediately. That is what postStartCommand wants -- rules in place
# before anything in the container gets to use the network.
#
# `--after-extensions`: wait for post-create to finish and for VS Code to
# finish installing its extensions, then lock down. Launched from PID 1 by the
# firewall-deferred Feature -- NOT from postStartCommand: a background process
# started there does not survive the hook (measured 2026-10-25: it died before
# its first echo and the container ran wide open). This mode exists because the
# devcontainer lifecycle has no hook that runs late enough. Measured 2026-10-25:
#
#     101.7s  postStartCommand  -> firewall up
#     102.8s  postAttachCommand -> the last hook there is
#     107.5s  first extension finishes installing
#     116.6s  anthropic.claude-code finishes installing
#
# Every hook fires before the installer does. With the firewall already up, all
# nine extensions died on EHOSTUNREACH and only survived because VS Code fell
# back to ~/.vscode-server/extensionsCache -- and anthropic.claude-code landed
# 14s after the extension host had already enumerated what was installed, so it
# never activated at all.
#
# The allowlist cannot simply be taught to permit them. VSIX bytes come from
# <publisher>.gallerycdn.vsassets.io -- a fresh hostname for every publisher,
# resolving through rotating Akamai edge IPs -- so an ipset built by resolving a
# fixed list of domains can never cover the set.
#
# THE TRADE, STATED PLAINLY: in this mode the container has unrestricted egress
# from the moment it starts until the rules land. On a stop/start that is about
# EXT_SETTLE_QUIET seconds. On first creation it is however long post-create
# takes (it fetches an embedding model from huggingface.co, which the allowlist
# does not carry) plus the extension settle -- bounded by PC_TIMEOUT and
# EXT_SETTLE_TIMEOUT. That window is the price of installing extensions and
# fetching models at runtime; baking both into the image would remove it.
#
# Fail-closed by construction: every exit from the wait -- settled, timed out,
# or no extensions directory at all -- falls through to applying the rules.

EXT_USER="${EXT_USER:-node}"
PC_MARKER="${PC_MARKER:-/home/node/.devcontainer/.post-create-finished}"   # written by post-create.sh's EXIT trap
PC_TIMEOUT="${PC_TIMEOUT:-900}"                   # first creation only: wait this long for post-create
EXT_APPEAR_TIMEOUT="${EXT_APPEAR_TIMEOUT:-90}"    # wait this long for the dir to appear
EXT_SETTLE_QUIET="${EXT_SETTLE_QUIET:-10}"        # this many seconds of no change = settled
EXT_SETTLE_TIMEOUT="${EXT_SETTLE_TIMEOUT:-300}"   # hard cap on the whole wait

ext_dir() {
    local home
    home="$(getent passwd "$EXT_USER" | cut -d: -f6)"
    echo "${EXT_DIR:-$home/.vscode-server/extensions}"
}

# Directory contents plus the registry's mtime and size. An extract, a rename
# or a rewrite of extensions.json all move this.
ext_signature() {
    local dir="$1"
    { ls -A "$dir" 2>/dev/null || true
      stat -c '%Y %s' "$dir/extensions.json" 2>/dev/null || true
    } | sha1sum
}

# The installer extracts into .<uuid> and then renames into place, so a dotted
# directory means a VSIX is mid-flight even if the signature happens to be still.
ext_installs_in_flight() {
    local dir="$1"
    find "$dir" -mindepth 1 -maxdepth 1 -type d -name '.*' 2>/dev/null | grep -q .
}

wait_for_extensions() {
    local dir waited=0
    dir="$(ext_dir)"

    while [ ! -d "$dir" ]; do
        if [ "$waited" -ge "$EXT_APPEAR_TIMEOUT" ]; then
            echo "No $dir after ${EXT_APPEAR_TIMEOUT}s -- no VS Code client. Locking down now."
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    local last="" quiet=0 elapsed=0 now
    while [ "$elapsed" -lt "$EXT_SETTLE_TIMEOUT" ]; do
        now="$(ext_signature "$dir")"
        if [ "$now" != "$last" ] || ext_installs_in_flight "$dir"; then
            last="$now"
            quiet=0
        else
            quiet=$((quiet + 1))
            if [ "$quiet" -ge "$EXT_SETTLE_QUIET" ]; then
                echo "Extensions settled after ${elapsed}s. Locking down."
                return 0
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "WARNING: extensions still changing after ${EXT_SETTLE_TIMEOUT}s. Locking down anyway."
    return 0
}

# The marker lives on the container filesystem, so a rebuild starts without it
# (and waits for the new post-create) while a stop/start finds it at once.
wait_for_post_create() {
    local waited=0
    while [ ! -e "$PC_MARKER" ]; do
        if [ "$waited" -ge "$PC_TIMEOUT" ]; then
            echo "WARNING: no $PC_MARKER after ${PC_TIMEOUT}s. Locking down anyway."
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "post-create finished ($(cat "$PC_MARKER" 2>/dev/null || true)) -- seen after ${waited}s."
    return 0
}

if [ "${1:-}" = "--after-extensions" ]; then
    echo "Deferred mode: waiting for post-create, then for extension installs to settle..."
    wait_for_post_create
    wait_for_extensions
fi

# Serialise rule application. The wait above is deliberately outside this lock,
# so running the script by hand during the wait locks down immediately and wins;
# the deferred run then re-applies the same rules later, which is a no-op.
exec 9>/run/init-firewall.lock
flock 9

# --- Settings ----------------------------------------------------------------
#
# The allowed hosts and the allow-all switch come from two files baked into the
# image as root: the template's conf.sh, which the base Dockerfile copies, and
# the project's, which project-specific/Dockerfile copies as its last step. They
# are sourced here, before anything is flushed, so a broken file stops the
# script while the existing rules still stand.
#
# Sourcing runs whatever a file holds, and this script runs as root through a
# sudoers rule that node may use. A file node could edit would therefore let
# anything in the container run code as root. So both paths are fixed rather
# than taken from the environment, each file and its directory must be owned by
# root and writable by no one else, and the copies in /workspace are never read.
# A change to either file reaches the firewall only when the image is rebuilt.
TEMPLATE_CONF=/etc/devcontainer/conf.sh
PROJECT_CONF=/etc/devcontainer/project-specific/conf.sh

# Succeeds when root owns the path and neither its group nor others can write to
# it. A symlink always reports mode 777, so a symlink fails this check.
only_root_can_write() {
    local owner mode
    owner="$(stat -c '%u' "$1")" || return 1
    mode="$(stat -c '%a' "$1")" || return 1
    [ "$owner" = 0 ] && [ $(( 8#$mode & 8#022 )) -eq 0 ]
}

# Succeeds when the path is a regular file, not a symlink, and both it and its
# directory pass only_root_can_write.
safe_to_source() {
    [ -f "$1" ] && [ ! -L "$1" ] \
        && only_root_can_write "$1" && only_root_can_write "$(dirname "$1")"
}

if ! safe_to_source "$TEMPLATE_CONF"; then
    echo "ERROR: $TEMPLATE_CONF is missing, or something other than root can write to it. The base image is broken; rebuild it."
    exit 1
fi
FIREWALL_ALLOWED_DOMAINS=()
FIREWALL_ALLOW_ALL=false
echo "Reading the template's settings from $TEMPLATE_CONF"
# shellcheck source=/dev/null
. "$TEMPLATE_CONF"

if [ -e "$PROJECT_CONF" ] || [ -L "$PROJECT_CONF" ]; then
    if safe_to_source "$PROJECT_CONF"; then
        echo "Reading the project's settings from $PROJECT_CONF"
        # shellcheck source=/dev/null
        . "$PROJECT_CONF"
    else
        echo "WARNING: Ignoring $PROJECT_CONF: it must be a regular file that only root can write, in a directory only root can write"
    fi
fi

case "$FIREWALL_ALLOW_ALL" in
    true|false) ;;
    *)
        echo "WARNING: FIREWALL_ALLOW_ALL is \"$FIREWALL_ALLOW_ALL\", which is neither true nor false. Treating it as false."
        FIREWALL_ALLOW_ALL=false
        ;;
esac

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# A project that sets FIREWALL_ALLOW_ALL=true gets no firewall at all. The rules
# are already flushed, and the default policies are reset to ACCEPT in case an
# earlier run set them to DROP.
if [ "$FIREWALL_ALLOW_ALL" = true ]; then
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo "WARNING: FIREWALL_ALLOW_ALL is true. The firewall is lifted, and egress is UNRESTRICTED."
    exit 0
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
# Allow inbound connections to dev server (single entrypoint, proxies to backend)
iptables -A INPUT -p tcp --dport 3000 -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Resolve and add the allowed domains from the settings: the template's, then any
# the project appended. A value that is not a domain name is skipped, so a typo
# leaves the firewall narrower rather than handing something odd to dig.
DOMAIN_RE='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'
for domain in "${FIREWALL_ALLOWED_DOMAINS[@]}"; do
    if [[ ! "$domain" =~ $DOMAIN_RE ]]; then
        echo "WARNING: Skipping \"$domain\" in FIREWALL_ALLOWED_DOMAINS: it is not a domain name"
        continue
    fi
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain, skipping"
        continue  # Changed from exit 1
    fi
    
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "WARNING: Invalid IP from DNS for $domain: $ip, skipping"
            continue  # Changed from exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip" 2>/dev/null || echo "WARNING: Could not add $ip (may be duplicate)"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
