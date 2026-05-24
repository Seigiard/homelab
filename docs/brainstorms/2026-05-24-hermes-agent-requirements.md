# Hermes Agent — Requirements

**Date:** 2026-05-24
**Status:** Approved
**Scope:** Standard

## Problem

Need a persistent AI agent accessible via Telegram with long-term memory, skill learning, and access to personal knowledge base (Obsidian vaults). Should run as a Docker service on the homelab server alongside existing infrastructure.

## Solution

Deploy [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research as a new Docker service with:
- Telegram bot as primary interface
- Web dashboard via Traefik for monitoring
- OpenAI (gpt-5.4-mini) as LLM provider
- Read-write access to Obsidian vaults (knowledge-base, ttrpg)

## Requirements

### Service Configuration
- Docker image: `nousresearch/hermes-agent:latest`
- Container runs in `gateway run` mode with dashboard enabled
- Network: `traefik-net`
- Restart policy: `unless-stopped`

### LLM Provider
- Provider: OpenAI
- Default model: `openai/gpt-5.4-mini`
- API key stored in `.env` file within data volume

### Telegram Integration
- Bot created via @BotFather
- Access restricted to single user via `TELEGRAM_ALLOWED_USERS`
- Token stored in `.env`

### Web Dashboard
- Local: `hermes.home.local` (HTTP, port 9119)
- External: `hermes.1218217.xyz` (HTTPS, Authelia SSO)
- Gateway API port 8642 (internal only, not exposed through Traefik)

### Storage
- Agent data (config, memories, skills, sessions): `appdata/hermes/` on SSD → `/opt/data` in container
- Obsidian vaults (read-write):
  - `/mnt/data/users/andrew/sync/knowledge-base` → `/data/knowledge-base`
  - `/mnt/data/users/andrew/sync/ttrpg` → `/data/ttrpg`

### Resource Limits
- Memory: 2G (no browser automation needed)
- CPUs: 2.0

### Homepage Integration
- Group: AI
- Name: Hermes Agent
- Icon: robot (or custom)
- Link to dashboard

## Post-Deploy Steps (on server)
1. Create Telegram bot via @BotFather, get token
2. Get own Telegram user ID (via @userinfobot or similar)
3. Run interactive setup: `docker run -it --rm -v /opt/homelab/appdata/hermes:/opt/data nousresearch/hermes-agent setup`
4. Set provider to OpenAI, model to gpt-5.4-mini
5. Configure Telegram gateway with bot token and allowed user ID
6. Start the service: `./scripts/docker/deploy.sh hermes`

## Non-Goals
- Voice mode
- Discord/Slack/WhatsApp integration
- Local LLM inference
- Browser automation tools (saves memory)
