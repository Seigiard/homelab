---
title: "feat: Add SillyTavern AI chat frontend service"
type: feat
status: active
date: 2026-04-09
---

# feat: Add SillyTavern AI chat frontend service

## Overview

Add SillyTavern as a Docker service to the homelab. SillyTavern is a self-hosted AI chat frontend that connects to various LLM APIs. Uses the prebuilt GHCR image with standard homelab patterns (Traefik routing, Homepage dashboard, resource limits).

## Problem Frame

Need a self-hosted AI chat interface accessible both locally and externally. SillyTavern provides a rich chat UI supporting multiple LLM backends (OpenAI, Anthropic, local models, etc.) with character management and conversation history.

## Requirements Trace

- R1. SillyTavern runs as a Docker service using prebuilt `ghcr.io/sillytavern/sillytavern:latest` image
- R2. Accessible locally at `chat.home.local` and externally at `chat.1218217.xyz`
- R3. Config stored on SSD (`appdata`), user data on SSD (characters, conversations are small)
- R4. Integrated with Homepage dashboard
- R5. Healthcheck enabled for automatic restart on failure
- R6. Non-root mode via PUID/PGID
- R7. Built-in Basic Auth enabled for access protection
- R8. Whitelist disabled (Traefik handles routing; Docker gateway IPs make whitelist unreliable)
- R9. Host whitelisting configured for both domains

## Scope Boundaries

- No LLM backend setup (user configures API keys in SillyTavern UI after deployment)
- No plugins setup — vanilla deployment

## Key Technical Decisions

- **Subdomain `chat`**: Descriptive and short. `sillytavern` is too long for a subdomain.
- **All volumes on SSD (appdata)**: SillyTavern stores config, characters, and conversation data. These are small text/JSON files — SSD is appropriate, no HDD data path needed.
- **PUID/PGID over `--user` flag**: SillyTavern's entrypoint auto-fixes permissions with PUID/PGID. Matches the pattern used by other services (navidrome).
- **Heartbeat healthcheck enabled**: Official image supports it via `SILLYTAVERN_HEARTBEATINTERVAL`. Ensures auto-recovery.
- **Homepage group: AI**: New category for AI-related services, separate from Media.
- **Internal port 8000**: SillyTavern default, no reason to change.
- **Built-in Basic Auth over Authelia**: SillyTavern supports `basicAuthMode` natively. Simpler than adding Authelia middleware — one less moving part. Credentials set via env vars in docker-compose.
- **Whitelist disabled**: Behind Traefik, source IPs are Docker-internal. Whitelist becomes unreliable. Disable it and rely on Basic Auth + Traefik for access control.
- **Host whitelisting enabled**: Prevents DNS rebinding attacks. Whitelist both `chat.home.local` and `chat.1218217.xyz`.

## Implementation Units

- [x] **Unit 1: Create SillyTavern docker-compose.yml**

**Goal:** Deployable SillyTavern service with Traefik routing, Homepage labels, healthcheck, and resource limits.

**Requirements:** R1, R2, R3, R4, R5, R6, R7, R8, R9

**Dependencies:** None

**Files:**
- Create: `services/sillytavern/docker-compose.yml`

**Approach:**
- Follow the navidrome/kima docker-compose pattern exactly
- Image: `ghcr.io/sillytavern/sillytavern:latest`
- Four volume mounts: config, data, plugins, extensions — all under `${APPDATA_PATH}/sillytavern/`
- Traefik labels: local router `chat.${LOCAL_DOMAIN}`, external router `chat.${EXTERNAL_DOMAIN}` with TLS
- Homepage labels: group=AI, name=SillyTavern, icon=sillytavern
- Environment: TZ, PUID, PGID, SILLYTAVERN_HEARTBEATINTERVAL=30, listen=true, whitelistMode=false, basicAuthMode=true
- Basic Auth credentials via env vars: SILLYTAVERN_BASICAUTHUSER__USERNAME, SILLYTAVERN_BASICAUTHUSER__PASSWORD (SillyTavern supports env var overrides with double underscore for nested config)
- Host whitelist configured via env vars for both domains
- Healthcheck block from official compose
- Resource limits: 1 CPU, 1G memory (Node.js app, moderate usage)
- Network: traefik-net (external)

**Patterns to follow:**
- `services/navidrome/docker-compose.yml` — Traefik labels structure, env vars pattern
- `services/kima/docker-compose.yml` — similar complexity service

**Verification:**
- File follows the same structure as existing services
- All four SillyTavern volume paths are mapped
- Both local and external Traefik routers are configured
- Healthcheck section matches official docs
- Deploy on server with `./scripts/docker/deploy.sh sillytavern`
- Accessible at `chat.home.local` and `chat.1218217.xyz`

- [x] **Unit 2: Update project documentation**

**Goal:** PLAN.md reflects that SillyTavern is deployed (no longer planned).

**Requirements:** Repo hygiene

**Dependencies:** Unit 1

**Files:**
- Modify: `PLAN.md`

**Approach:**
- If SillyTavern was listed in planned services, move to realized or remove
- No other docs changes needed — README lists services via `ls services/`

**Verification:**
- PLAN.md is accurate

## Risks & Dependencies

- **Env var config override**: SillyTavern supports environment variable overrides for config.yaml using `SILLYTAVERN_` prefix. Nested keys use double underscore (e.g., `SILLYTAVERN_BASICAUTHUSER__USERNAME`). Need to verify this works for all required settings — if not, a mounted config.yaml file will be needed instead.
- **Basic Auth credentials in .env**: Add credentials to `.env.example` so they're documented. Actual passwords in `.env` on server.
