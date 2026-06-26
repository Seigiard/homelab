# folder2podcast Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add folder2podcast service to serve audiobooks and podcasts as standard RSS feeds for any podcast client.

**Architecture:** Single stateless container mounting both audiobooks and podcasts directories read-only. Traefik reverse proxy with local + external access (Authelia-protected). Runs alongside Audiobookshelf — same data, different access pattern.

**Tech Stack:** Docker Compose, Traefik labels, folder2podcast (Go)

---

### Task 1: Create docker-compose.yml

**Files:**
- Create: `services/folder2podcast/docker-compose.yml`

**Step 1: Create the service directory**

```bash
mkdir -p services/folder2podcast
```

**Step 2: Write docker-compose.yml**

```yaml
services:
  folder2podcast:
    image: yaotutu/folder2podcast:latest
    container_name: folder2podcast
    restart: unless-stopped
    environment:
      - TZ=${TZ:-Europe/Bratislava}
      - PORT=3000
      - AUDIO_DIR=/podcasts
      - BASE_URL=https://podcasts.${EXTERNAL_DOMAIN:-1218217.xyz}
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
    volumes:
      - ${DATA_PATH:-/mnt/data}/public/audiobooks:/podcasts/audiobooks:ro
      - ${DATA_PATH:-/mnt/data}/public/podcasts:/podcasts/podcasts:ro
    networks:
      - traefik-net
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 128M
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik-net
      # Local
      - traefik.http.routers.folder2podcast.rule=Host(`podcasts.${LOCAL_DOMAIN:-home.local}`)
      - traefik.http.routers.folder2podcast.entrypoints=web
      - traefik.http.services.folder2podcast.loadbalancer.server.port=3000
      # External
      - traefik.http.routers.folder2podcast-secure.rule=Host(`podcasts.${EXTERNAL_DOMAIN:-1218217.xyz}`)
      - traefik.http.routers.folder2podcast-secure.entrypoints=websecure
      - traefik.http.routers.folder2podcast-secure.tls=true
      - traefik.http.routers.folder2podcast-secure.tls.certresolver=cloudflare
      - traefik.http.routers.folder2podcast-secure.service=folder2podcast
      - traefik.http.routers.folder2podcast-secure.middlewares=authelia@docker
      # Homepage
      - homepage.group=Media
      - homepage.name=Folder2Podcast
      - homepage.icon=podcast
      - homepage.href=https://podcasts.${EXTERNAL_DOMAIN:-1218217.xyz}
      - homepage.description=Podcast RSS feeds

networks:
  traefik-net:
    external: true
```

**Step 3: Commit**

```bash
git add services/folder2podcast/docker-compose.yml
git commit -m "Add folder2podcast service for podcast RSS feeds"
```

---

### Task 2: Update project documentation

**Files:**
- Modify: `PLAN.md`

**Step 1: Add folder2podcast to realized plans in PLAN.md**

Add link to the design doc under "Realized plans".

**Step 2: Commit**

```bash
git add PLAN.md
git commit -m "Add folder2podcast to realized plans"
```

---

### Task 3: Deploy and verify on server (manual)

**Step 1: Deploy the service**

```bash
./scripts/docker/deploy.sh folder2podcast
```

**Step 2: Verify local access**

```bash
curl -s http://podcasts.home.local/podcasts | head -20
```

Expected: HTML page listing podcast sources.

**Step 3: Verify external access**

Open `https://podcasts.1218217.xyz` in browser — should redirect to Authelia login, then show folder2podcast UI after auth.

---

## Open Questions

- RSS feed URLs behind Authelia won't work in podcast apps (they can't handle forward-auth). May need to bypass auth for `/rss/` or `/feed/` paths via a separate Traefik router, or use basic auth as a fallback for feed URLs.
