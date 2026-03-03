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

Example: Add Google Drive remote named `gdrive`:

1. Choose `n` (new remote)
2. Name: `gdrive`
3. Storage: `drive` (Google Drive)
4. Follow OAuth flow in browser

Verify configuration:

```bash
rclone listremotes        # Should show: gdrive:
rclone lsd gdrive:        # List folders
```

### 2. Configure Backrest

After deploying Backrest (`./scripts/docker/deploy.sh backrest`):

1. Open http://backup.home.local
2. **Add Repository**:
   - URI: `rclone:gdrive:backups/homelab`
   - Password: create a strong encryption password (save it!)
3. **Add Backup Plans**:
   - Path: `/backup/appdata` → container configs
   - Path: `/backup/users` → user data
   - Schedule: `0 3 * * *` (daily at 3 AM)
4. **Test**: Run backup manually, verify in Google Drive

Backrest uses [restic](https://restic.net/) for encrypted, deduplicated backups.

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
