# Node 24 "Krypton" (newest Active LTS) on Debian 13 "trixie" (current stable).
# Deliberately LTS rather than Node 26 (Current): this is a server that should
# stay boring. Claude Code requires node >=22.
FROM node:24-trixie

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server \
      tmux \
      git \
      curl \
      ca-certificates \
      gnupg \
      ripgrep \
      fd-find \
      jq \
      less \
      vim \
      rsync \
      build-essential \
      python3 \
      python3-venv \
      python3-pip \
      iproute2 \
      procps \
  && rm -rf /var/lib/apt/lists/*

# Claude Code is intentionally unpinned: it ships very frequently and is the one
# component that should track latest. Everything else above is pinned by base
# image. Rebuild to pick up new releases.
RUN npm install -g @anthropic-ai/claude-code@latest

# Tailscale (official install script; supports Debian trixie)
RUN curl -fsSL https://tailscale.com/install.sh | sh

# sshd: key-only root login, no passwords.
#
# Port 2222, NOT 22. Fly runs its own ssh daemon (hallpass, what `fly ssh
# console` uses) bound to port 22 on the machine's private IPv6. Binding 22
# here wins the race, hallpass then fails with "address already in use",
# restarts 10 times, and gives up - which takes Fly's init down with it and
# panics the kernel ("Attempted to kill init"). Leave 22 to Fly.
# Written as a drop-in rather than edited in place: Debian's sshd_config has
# `Include /etc/ssh/sshd_config.d/*.conf` at the top, and sshd takes the
# first value it sees for a keyword, so a drop-in reliably wins.
RUN mkdir -p /run/sshd /etc/ssh/sshd_config.d \
  && printf '%s\n' \
      'Port 2222' \
      'PermitRootLogin prohibit-password' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'ClientAliveInterval 60' \
      'ClientAliveCountMax 3' \
      'AcceptEnv COLORTERM' \
      > /etc/ssh/sshd_config.d/fly.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
