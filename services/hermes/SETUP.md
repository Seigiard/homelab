# Hermes Agent — First-Time Setup

## Prerequisites

1. Create a Telegram bot via [@BotFather](https://t.me/BotFather):
   - Send `/newbot`, choose name and username (must end with `bot`)
   - Save the API token

2. Get your Telegram user ID via [@userinfobot](https://t.me/userinfobot)

3. Have your OpenAI API key ready

## Initial Setup

Run the setup wizard interactively (one time only):

```bash
mkdir -p /opt/homelab/appdata/hermes
docker run -it --rm \
  -v /opt/homelab/appdata/hermes:/opt/data \
  nousresearch/hermes-agent setup
```

During setup:
- Select **OpenAI** as provider
- Set model to **gpt-5.4-mini**
- Configure **Telegram** gateway with your bot token
- Set allowed users to your Telegram user ID

## Alternative: Manual Configuration

If you prefer to configure manually:

```bash
mkdir -p /opt/homelab/appdata/hermes
```

Create `/opt/homelab/appdata/hermes/.env`:
```
OPENAI_API_KEY=sk-...
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
```

Create `/opt/homelab/appdata/hermes/config.yaml`:
```yaml
model:
  provider: openai
  model: gpt-5.4-mini

gateway:
  platforms:
    telegram:
      enabled: true
      allowed_users:
        - "YOUR_TELEGRAM_USER_ID"
```

## Deploy

```bash
cd /opt/homelab
./scripts/docker/deploy.sh hermes
```

## Verify

- Telegram: send a message to your bot
- Dashboard: open https://hermes.1218217.xyz
- Logs: `docker logs -f hermes`
