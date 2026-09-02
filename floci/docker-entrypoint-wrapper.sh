#!/bin/sh
# =============================================================================
# Floci Docker-socket permission fix (Docker Desktop for Mac)
# =============================================================================
# Floci's own entrypoint drops from root to the unprivileged `floci` user
# (uid 1001, gid 0) via gosu, and only re-groups the bind-mounted Docker
# socket when its GID isn't 0 — on the assumption that Docker Desktop
# always ships the socket group-writable when its GID is 0.
#
# On this host, /var/run/docker.sock is root:root mode 0755 (rwx r-x r-x):
# `floci` is a member of group 0, so it gets read+execute but NOT write —
# and a Unix domain socket connect() needs write access. Every feature
# that talks to the Docker Engine API (the Floci UI sidecar, Lambda/ECS/
# RDS emulation) then fails with:
#   java.net.BindException: Permission denied
#
# Fix: add the group-write bit while we're still root, before Floci's own
# entrypoint does its privilege drop. Safe no-op on hosts where the socket
# is already group-writable or root:docker with a group Floci already
# joins correctly.
# =============================================================================
set -eu

if [ -S /var/run/docker.sock ] && [ "$(id -u)" = '0' ]; then
    chmod g+rw /var/run/docker.sock 2>/dev/null || true
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
