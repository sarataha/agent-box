#!/usr/bin/env bash
set -euo pipefail

log() { echo "[entrypoint] $*"; }

# ---------------------------------------------------------------------------
# Persistent state. Everything that must survive a redeploy lives under /data
# (the Fly volume). The container filesystem is rebuilt on every deploy.
# ---------------------------------------------------------------------------
mkdir -p /data/home /data/repos /data/tailscale /data/log

# Point root's home at the volume so ssh logins, tmux and Claude Code all
# land in persistent storage without needing HOME exported everywhere.
# Edited directly rather than via usermod, which refuses to touch an account
# that already owns running processes (PID 1 is root here).
sed -i 's|^root:x:0:0:root:/root:|root:x:0:0:root:/data/home:|' /etc/passwd
export HOME=/data/home

# ---------------------------------------------------------------------------
# First boot
# ---------------------------------------------------------------------------
if [ ! -f /data/home/.bootstrapped ]; then
  log "first boot, seeding home"
  cp -n /etc/skel/.bashrc /data/home/.bashrc 2>/dev/null || true
  cp -n /etc/skel/.profile /data/home/.profile 2>/dev/null || true
  touch /data/home/.bootstrapped
fi

# ---------------------------------------------------------------------------
# sshd. authorized_keys is read from the volume so keys can be added or
# rotated without rebuilding the image.
# ---------------------------------------------------------------------------
mkdir -p /data/home/.ssh
chmod 700 /data/home/.ssh
if [ -f /data/authorized_keys ]; then
  cp /data/authorized_keys /data/home/.ssh/authorized_keys
  chmod 600 /data/home/.ssh/authorized_keys
  log "installed authorized_keys"
else
  log "WARNING no /data/authorized_keys - plain ssh will refuse you"
fi

# Port 2222 - port 22 belongs to Fly's hallpass daemon. See Dockerfile.
log "starting sshd on 2222"
/usr/sbin/sshd -t   # fail loudly on a bad config rather than silently not listening
/usr/sbin/sshd -D -e >>/data/log/sshd.log 2>&1 &

# ---------------------------------------------------------------------------
# Tailscale. Userspace networking avoids depending on /dev/net/tun being
# available to the container. State on the volume keeps one stable node
# instead of a new registration per deploy.
# ---------------------------------------------------------------------------
if [ -n "${TS_AUTHKEY:-}" ]; then
  log "starting tailscaled"
  tailscaled \
    --state=/data/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --tun=userspace-networking \
    --socks5-server=localhost:1055 \
    --outbound-http-proxy-listen=localhost:1055 \
    >>/data/log/tailscaled.log 2>&1 &

  # give the daemon a moment to open its socket
  for _ in $(seq 1 15); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
  done

  # Deliberately no --ssh: Tailscale SSH wants port 22, which is hallpass's.
  # Userspace networking should keep that off the host port, but this box has
  # already been panicked once by a port 22 collision. Use sshd on 2222.
  tailscale up \
    --authkey="${TS_AUTHKEY}" \
    --hostname="${TS_HOSTNAME:-stelab}" \
    || log "WARNING tailscale up failed, see /data/log/tailscaled.log"
  log "tailscale: $(tailscale ip -4 2>/dev/null || echo unknown)"
else
  log "TS_AUTHKEY unset, skipping tailscale (use: fly proxy 2222:2222)"
fi

# ---------------------------------------------------------------------------
# Long-lived tmux sessions. These survive your disconnects; the machine
# staying up is what makes them survive your laptop sleeping.
#   main  - interactive Claude Code / general work
#   svc   - resident processes (trading loop, bots)
# ---------------------------------------------------------------------------
tmux has-session -t main 2>/dev/null || tmux new-session -d -s main -c /data/repos
tmux has-session -t svc  2>/dev/null || tmux new-session -d -s svc  -c /data/repos
log "tmux sessions ready: $(tmux ls | tr '\n' ' ')"

log "box up"
exec sleep infinity
