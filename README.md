# always-on agent box

Personal Fly.io box for long-lived tmux sessions and background processes that
survive the laptop sleeping.

## State

Everything persistent lives on the `/data` volume:

```
/data/home
/data/repos
/data/authorized_keys
/data/tailscale
/data/log
```

## Deploy

```bash
fly auth login
fly launch --no-deploy --name APP_NAME --region REGION
fly volumes create APP_NAME_data --size 40 --region REGION
fly secrets set TS_AUTHKEY=tskey-auth-...
fly secrets set ANTHROPIC_API_KEY=...
fly deploy
```

Install an SSH key:

```bash
KEY="$(cat ~/.ssh/id_ed25519.pub)"
fly ssh console -a APP_NAME -C "/bin/bash -c \"echo '$KEY' > /data/authorized_keys\""
fly machine restart -a APP_NAME
```

## Connect

sshd listens on port `2222`; Fly uses port `22` internally.

```sshconfig
Host APP_NAME
  HostName HOSTNAME
  Port 2222
  User root
  ForwardAgent yes
```

Use Tailscale when available:

```bash
ssh APP_NAME
```

Fallback through Fly:

```bash
fly proxy 2222:2222 -a APP_NAME
ssh -p 2222 root@localhost
```

`fly ssh console -a APP_NAME` always works.

## Work

```bash
box              attach tmux session "main"
box <name>       attach/create any session
box stop         stop the machine (saves CPU/RAM, volume persists)
box status       show machine and proxy state
box ls           list tmux sessions
box kill         kill all tmux sessions except current
box kill -s <n>  kill a specific session
box -- <cmd>     run a command non-interactively
```

`main` is for interactive work; `svc` is for resident processes. `tmux`
survives disconnects, not machine restarts.

Tools added at runtime disappear on deploy; add them to the Dockerfile instead.

## OpenCode

Run `opencode`, then use `/connect` to add OpenRouter and `/models` to select
`qwen/qwen3-coder:free`.
