# Filebrowser → Filebrowser Quantum Migration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 3 separate filebrowser containers with a single Filebrowser Quantum instance using multiple sources and proxy authentication via Authelia.

**Architecture:** One FBQ container with proxy auth. External access via Authelia SSO (per-user sources). Local access auto-injects `Remote-User: admin` header via Traefik middleware for full access without login.

**Tech Stack:** Filebrowser Quantum (gtstef/filebrowser:stable), Traefik v3 (Docker labels), Authelia (existing)

---

## Context

### Current state
- 3 containers: `filebrowser-public`, `filebrowser-andrew`, `filebrowser-yuliia`
- All use `FB_NOAUTH=true`
- HTTPS routes protected by `authelia@docker` middleware
- HTTP (local) routes open without auth
- Separate subdomains: `files.*`, `a.files.*`, `y.files.*`

### Target state
- 1 container: `filebrowser`
- Proxy auth via `Remote-User` header from Authelia
- Single subdomain: `files.*`
- Local: Traefik injects `Remote-User: admin` → full access
- External: Authelia → per-user access (andrew sees public + own, yuliia sees public + own)

### Key reference
- Traefik Authelia middleware already passes `Remote-User` header (defined in `services/traefik/docker-compose.yml:32`)
- FBQ proxy auth docs: https://filebrowserquantum.com/en/docs/configuration/authentication/proxy
- FBQ sources docs: https://filebrowserquantum.com/en/docs/configuration/sources

---

## Task 1: Create FBQ config.yaml

**Files:**
- Create: `services/filebrowser/config.yaml`

**Step 1: Create the config file**

```yaml
server:
  port: 80
  sources:
    - path: /srv/public
      name: "Public Files"
      config:
        defaultEnabled: true
    - path: /srv/users
      name: "My Files"
      config:
        defaultEnabled: true
        createUserDir: true

auth:
  adminUsername: admin
  methods:
    proxy:
      enabled: true
      header: "Remote-User"
      createUser: true
    password:
      enabled: false
```

**Step 2: Verify file exists**

Run: `cat services/filebrowser/config.yaml`
Expected: config contents shown above

---

## Task 2: Rewrite docker-compose.yml

**Files:**
- Rewrite: `services/filebrowser/docker-compose.yml`

**Step 1: Replace the file with new single-container setup**

```yaml
services:
  filebrowser:
    image: gtstef/filebrowser:stable
    container_name: filebrowser
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 256M
    volumes:
      - ./config.yaml:/home/filebrowser/config.yaml:ro
      - ${DATA_PATH:-/mnt/data}/public:/srv/public
      - ${DATA_PATH:-/mnt/data}/users:/srv/users
      - ${APPDATA_PATH:-/opt/homelab/appdata}/filebrowser/data:/home/filebrowser/data
    networks:
      - traefik-net
    labels:
      - traefik.enable=true
      # --- HTTP (local) — auto-admin via header middleware ---
      - traefik.http.routers.filebrowser.rule=Host(`files.${LOCAL_DOMAIN:-home.local}`)
      - traefik.http.routers.filebrowser.entrypoints=web
      - traefik.http.routers.filebrowser.middlewares=filebrowser-local-admin@docker
      - traefik.http.services.filebrowser.loadbalancer.server.port=80
      # Middleware: inject Remote-User=admin for local access
      - traefik.http.middlewares.filebrowser-local-admin.headers.customrequestheaders.Remote-User=admin
      # --- HTTPS (external) — Authelia proxy auth ---
      - traefik.http.routers.filebrowser-secure.rule=Host(`files.${EXTERNAL_DOMAIN:-1218217.xyz}`)
      - traefik.http.routers.filebrowser-secure.entrypoints=websecure
      - traefik.http.routers.filebrowser-secure.tls=true
      - traefik.http.routers.filebrowser-secure.tls.certresolver=cloudflare
      - traefik.http.routers.filebrowser-secure.middlewares=authelia@docker
      - traefik.http.routers.filebrowser-secure.service=filebrowser
      # --- Homepage ---
      - homepage.group=Files
      - homepage.name=Files
      - homepage.icon=filebrowser
      - homepage.href=https://files.${EXTERNAL_DOMAIN:-1218217.xyz}
      - homepage.description=File manager (Quantum)

networks:
  traefik-net:
    external: true
```

**Step 2: Verify the file**

Run: `cat services/filebrowser/docker-compose.yml`
Expected: single `filebrowser` service with Traefik labels

---

## Task 3: Commit changes

**Step 1: Stage files**

```bash
git add services/filebrowser/config.yaml services/filebrowser/docker-compose.yml
```

**Step 2: Commit**

```bash
git commit -m "Replace filebrowser with Filebrowser Quantum

- Single FBQ instance instead of 3 separate containers
- Proxy auth via Authelia Remote-User header
- Multiple sources: Public Files + per-user My Files
- Local access auto-injects admin user via Traefik header middleware
- Subdomains a.files.* and y.files.* removed"
```

---

## Task 4: Deploy on server (manual)

These steps are performed on the server, not by Claude:

**Step 1: Pull changes**
```bash
cd /opt/homelab && git pull
```

**Step 2: Stop old containers**
```bash
docker compose -f services/filebrowser/docker-compose.yml down
```

**Step 3: Create data directory for FBQ**
```bash
mkdir -p /opt/homelab/appdata/filebrowser/data
```

**Step 4: Start new container**
```bash
docker compose -f services/filebrowser/docker-compose.yml up -d
```

**Step 5: Verify**
- Local: open `http://files.home.local` → should show all files as admin, no login
- External: open `https://files.1218217.xyz` → Authelia login → per-user access
- Check logs: `docker logs filebrowser`

**Step 6: Clean up old appdata (after verification)**
```bash
rm -rf /opt/homelab/appdata/filebrowser/{public,andrew,yuliia}
```
