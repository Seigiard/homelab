# Homelab

Automated setup scripts for Ubuntu home server.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash
```

The script will:

1. Install git and clone repository to `/opt/homelab`
2. Update system (apt update/upgrade)
3. Install packages (zsh, micro, zoxide, htop, mc, jq, ffmpeg, mediainfo, chafa, etc.)
4. Setup Oh-My-Zsh with plugins
5. Configure git
6. Setup Avahi (mDNS)
7. Apply dotfiles
8. Install Docker
9. Generate SSH key for GitHub (interactive step)

## Project Structure

```
homelab/
├── scripts/
│   ├── setup.sh              # Entry point (curl | bash)
│   ├── bootstrap.sh          # Docker, directories, permissions
│   ├── healthcheck.sh        # Post-install verification
│   ├── lib/
│   │   ├── config.sh         # Shared variables
│   │   └── tui.sh            # TUI library
│   ├── setup/                # Modular install steps (00-08)
│   └── docker/               # Service management (deploy/stop/rebuild/remove/status)
├── dotfiles/                  # Symlinked to ~
├── services/                  # Docker services (one dir per service)
└── docs/plans/                # Implementation decision records
```

## Running Services

```bash
./scripts/docker/deploy.sh           # Deploy all services
./scripts/docker/deploy.sh traefik   # Deploy single service
./scripts/docker/stop.sh             # Stop all
./scripts/docker/rebuild.sh          # Rebuild (pull + restart)
./scripts/docker/remove.sh           # Stop + remove containers
./scripts/docker/status.sh           # Container status
```

After first deployment, containers auto-start on reboot (`restart: unless-stopped`).

## Services

Each service lives in `services/<name>/docker-compose.yml`. List all services:

```bash
ls services/
```

Services are accessed via two domain patterns:

- **Local HTTP:** `<name>.home.local` (mDNS via Avahi)
- **Local/External HTTPS:** `<name>.1218217.xyz` (Let's Encrypt + Cloudflare Tunnel)

> **Note:** Local HTTPS requires split-horizon DNS (AdGuard Home) to resolve `*.1218217.xyz` to local IP.
> External access via Cloudflare Tunnel works independently.

## Adding New Services

1. Create `services/myservice/docker-compose.yml`
2. Add Traefik labels for routing
3. Add Homepage labels for auto-discovery
4. Run `./scripts/docker/deploy.sh myservice`

Example labels:

```yaml
labels:
  # Traefik - HTTP (local backup)
  - traefik.enable=true
  - traefik.http.routers.myservice.rule=Host(`myservice.${LOCAL_DOMAIN:-home.local}`)
  - traefik.http.routers.myservice.entrypoints=web
  - traefik.http.services.myservice.loadbalancer.server.port=8080
  # Traefik - HTTPS (local primary)
  - traefik.http.routers.myservice-secure.rule=Host(`myservice.${EXTERNAL_DOMAIN:-1218217.xyz}`)
  - traefik.http.routers.myservice-secure.entrypoints=websecure
  - traefik.http.routers.myservice-secure.tls=true
  - traefik.http.routers.myservice-secure.tls.certresolver=cloudflare
  # Authelia protection (optional - for services requiring auth)
  - traefik.http.routers.myservice-secure.middlewares=authelia@docker
  # Homepage
  - homepage.group=Services
  - homepage.name=My Service
  - homepage.icon=myservice
  - homepage.href=https://myservice.${EXTERNAL_DOMAIN:-1218217.xyz}
```

> **Feed services (OPDS, podcast RSS):** podcast/OPDS clients can't follow
> Authelia's SSO cookie redirect. Use the shared HTTP Basic Auth middleware
> instead — `middlewares=basic-auth@docker` — so clients subscribe with
> `https://user:pass@myservice.1218217.xyz/...`. Credentials live in `.env` as
> `BASIC_AUTH_USERS` (htpasswd format). Wrap the value in single quotes with a
> single `$` — `deploy.sh` sources `.env` via bash, so single quotes stop `$`
> from being mangled: `BASIC_AUTH_USERS='feeds:$2y$05$...'`. Used by `ytpod`,
> `opds`, `opml`. Generate: `htpasswd -nbB feeds 'password'`, then wrap in `'...'`.

## Healthcheck

Verify system state after installation:

```bash
cd ~/homelab
./scripts/healthcheck.sh
```

Checks:

- Installed packages (zsh, git, jq, micro, zoxide, etc.)
- User shell (zsh)
- SSH key
- Git config
- Hostname
- Dotfiles (symlinks)
- Docker (daemon, compose, traefik-net network)

## Re-running Individual Steps

After installation, you can re-run any step:

```bash
cd ~/homelab
./scripts/setup/07-setup-ssh-key.sh
```

## Troubleshooting

### Chrome/Firefox can't open \*.home.local

Safari uses the system mDNS resolver and works immediately. Chrome and Firefox use their own DNS resolvers which may cache failed requests to `.local` domains.

**Solution — clear browser DNS cache:**

**Chrome:**

```
chrome://net-internals/#dns → Clear host cache
```

**Firefox:**

```
about:networking → DNS → Clear DNS Cache
```

After clearing cache, `*.home.local` should work in all browsers.

## Configuration

Main variables in `scripts/lib/config.sh`:

```bash
GITHUB_USER="seigiard"
GITHUB_EMAIL="seigiard@gmail.com"
INSTALL_PATH="/opt/homelab"
HOSTNAME="home"
```

## Backup Setup

### 1. Configure rclone

rclone is installed automatically. Configure a remote for backups:

```bash
rclone config
```

The server currently uses two remotes:

| Remote       | Storage                       | Capacity |
| ------------ | ----------------------------- | -------- |
| `dropbox`    | Dropbox                       | ~10 GB   |
| `ftp-backup` | HostBrr StorageBox (over FTP) | 1 TB     |

A copy of the finished config lives in 1Password as "RClone conf" — Backrest
mounts it read-only from `~/.config/rclone`.

Verify configuration:

```bash
rclone listremotes        # Should show: dropbox: ftp-backup:
rclone about dropbox:     # Quota — watch the free space, see below
```

### 2. Configure Backrest

After deploying Backrest (`./scripts/docker/deploy.sh backrest`):

1. Open http://backup.home.local
2. **Add Repository**:
   - URI: `rclone:dropbox:backups` (or `rclone:ftp-backup:<path>`)
   - Password: create a strong encryption password (save it!)
3. **Add Backup Plan**:
   - Path: `/backup/appdata` → container configs
   - Schedule: `0 3 * * *` (daily at 3 AM)
   - Retention: daily 7 / weekly 4 / monthly 2 on Dropbox, monthly 6 on the StorageBox
4. **Test**: Run backup manually, verify the snapshot appears

`/mnt/data/users` is deliberately *not* in any plan — the mount
`/backup/users:ro` exists in the container but nothing references it.

Backrest uses [restic](https://restic.net/) for encrypted, deduplicated backups.
The plan config (repos, excludes, retention) lives in
`appdata/backrest/config/config.json` on the server, not in this repo.

### 3. Keep the backup set small

Dropbox only holds ~10 GB, so anything large and regenerable must be excluded
or it eats the quota and takes the repo with it. With the current excludes a
snapshot of `appdata` is 233 MB (5.1 GB on disk) and the whole Dropbox repo sits
at 108 MB.

The excludes cover generated media (`stash/config/generated`, `blobs`),
downloaded binaries (`stash/config/ffmpeg`, `ffprobe`, `*.zip`), caches and
logs, `transmission-omg/resume`, and the Home Assistant recorder DB
(`home-assistant_v2.db*` — 300+ MB rewritten daily, and a copy taken from a live
sqlite is inconsistent anyway; the HA config itself lives in `.storage` and yaml
and is still backed up).

Two rules worth remembering:

- **A full repo cannot clean itself.** restic needs to write a lock file before
  it can prune, so once the remote is at quota every operation fails with
  `path/insufficient_space` and unused data stays forever. Keep headroom.
- **Retention pins mistakes.** One snapshot that accidentally caught 3 GB of
  Ollama model weights landed in the monthly bucket, where it would have sat for
  six months. Check the size column: `restic snapshots --no-lock --compact`
  should read as an even line, and any outlier means something large slipped
  past the excludes.

## SSL Setup (HTTPS for Local Access)

For local HTTPS access to `*.1218217.xyz`, configure Let's Encrypt certificates via Cloudflare DNS challenge.

### 1. Create Cloudflare API Token

1. Go to Cloudflare Dashboard → My Profile → API Tokens
2. Create Token with permissions: `Zone:DNS:Edit` for zone `1218217.xyz`
3. Save the token

### 2. Configure Environment Variables

Add to your `.env`:

```bash
ACME_EMAIL=your-email@example.com
CF_DNS_API_TOKEN=your-cloudflare-api-token
```

### 3. Create acme.json

```bash
touch services/traefik/data/acme.json
chmod 600 services/traefik/data/acme.json
```

### 4. Rebuild Traefik

```bash
./scripts/docker/rebuild.sh traefik
```

### 5. Configure Split-Horizon DNS (AdGuard Home)

In AdGuard Home (http://dns.home.local), add DNS rewrites:

```
*.1218217.xyz → 192.168.1.41  (your server IP)
```

This makes local devices resolve `*.1218217.xyz` to the local server while external access continues via Cloudflare Tunnel.

### 6. Verify

```bash
# Check certificate issuance
docker logs traefik 2>&1 | grep -i "acme\|certificate"

# Test HTTPS locally
curl -v https://traefik.1218217.xyz
```

## Remote Access (Tailscale)

Tailscale (mesh VPN) gives **SSH to the host and device-to-device mesh** over a private tailnet — no public port forwarding. Runs on the host (like NUT), not in Docker. Setup: `scripts/setup/10-setup-tailscale.sh` (interactive login on first run). Variables: `TS_*` in `scripts/lib/config.sh`.

- **Tailscale SSH** — `ssh seigiard@home` (or `tailscale ssh seigiard@home`) from any tailnet device, no SSH keys / port forwarding.
- **Mesh** — your devices reach each other over the tailnet.

The tailnet is single-user (trusted zone): SSH to `home` is gated by tailnet membership, independent of the UFW `:22` key-auth rule.

**Remote access to services** (`*.1218217.xyz` from outside) goes through the **Cloudflare Tunnel + Authelia**, independent of Tailscale — see "SSL Setup" and the `cloudflared` service. The server's tailnet IP also serves Traefik directly (`https://<tailnet-ip>` with the right `Host`), but that is a diagnostic/admin path, not the primary route.

> `accept-dns=false` on the server is intentional — it would otherwise break the AdGuard split-horizon. **Never advertise the server's own IP as a Tailscale subnet route** — it is self-referential and breaks local LAN access. Details and pitfalls are in `ENVIRONMENT.md` → "Tailscale".
