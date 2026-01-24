# Homelab

Automated setup scripts for Ubuntu home server.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash
```

The script will:

1. Install git and clone repository to `/opt/homelab`
2. Update system (apt update/upgrade)
3. Install packages (zsh, micro, zoxide, htop, mc, jq, etc.)
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
│   ├── lib/
│   │   ├── config.sh         # Shared variables
│   │   └── tui.sh            # TUI library
│   └── setup/
│       ├── --init.sh         # Orchestrator
│       ├── 00-update-system.sh
│       ├── 01-install-packages.sh
│       ├── 02-setup-zsh.sh
│       ├── 03-setup-git.sh
│       ├── 04-setup-avahi.sh
│       ├── 05-apply-dotfiles.sh
│       ├── 06-run-bootstrap.sh
│       ├── 07-setup-ssh-key.sh
│       └── 08-show-summary.sh
├── dotfiles/                  # Symlinked to ~
├── services/                  # Docker services
│   ├── traefik/               # Reverse proxy + avahi-helper (*.home.local)
│   └── homepage/              # Dashboard with Docker auto-discovery
└── tests/                     # Docker testing (see TESTING.md)
```

## Running Services

```bash
./scripts/docker/deploy.sh           # Deploy all services
./scripts/docker/stop.sh             # Stop all
./scripts/docker/status.sh           # Container status
./scripts/docker/rebuild.sh          # Rebuild (pull + restart)
./scripts/docker/deploy.sh traefik   # Deploy single service
```

After first deployment, containers auto-start on reboot (`restart: unless-stopped`).

## Current Services

| Service        | Local URL                 | External URL                | Description                          |
| -------------- | ------------------------- | --------------------------- | ------------------------------------ |
| Homepage       | http://home.local         | —                           | Dashboard with Docker auto-discovery |
| Traefik        | http://traefik.home.local | —                           | Reverse proxy dashboard              |
| Dozzle         | http://dozzle.home.local  | —                           | Docker logs viewer                   |
| Glances        | http://glances.home.local | —                           | System monitoring                    |
| FileBrowser    | http://files.home.local   | https://files.1218217.xyz   | Web file manager                     |
| OPDS Generator | http://opds.home.local    | https://opds.1218217.xyz    | E-book OPDS catalog                  |
| Calibre        | http://calibre.home.local | https://calibre.1218217.xyz | E-book library (CWA)                 |
| Backrest       | http://backup.home.local  | —                           | Backup management (restic + rclone)  |
| Cloudflared    | —                         | \*.1218217.xyz              | Cloudflare Tunnel (external access)  |
| Samba          | —                         | —                           | SMB file shares (ports 139, 445)     |

## Adding New Services

1. Create `services/myservice/docker-compose.yml`
2. Add Traefik labels for routing
3. Add Homepage labels for auto-discovery
4. Run `./scripts/docker/deploy.sh myservice`

Example labels:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.myservice.rule=Host(`myservice.home.local`)
  - traefik.http.routers.myservice.entrypoints=web
  - homepage.group=Services
  - homepage.name=My Service
  - homepage.icon=myservice
  - homepage.href=http://myservice.home.local
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
