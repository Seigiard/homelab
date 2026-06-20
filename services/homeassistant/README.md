# Home Assistant

Home automation hub. Runs in `network_mode: host` so it can discover WiFi/LAN
devices (bulbs, vacuums, air purifiers, etc.) via mDNS/SSDP broadcast — this does
not work over a docker bridge.

## Deploy

```bash
./scripts/docker/deploy.sh traefik        # recreate Traefik: new dynamic mount + host-gateway
./scripts/docker/deploy.sh homeassistant
```

## First-run setup

1. **Onboarding** — open Home Assistant directly (host networking exposes it on the
   LAN), create your account:

   ```
   http://<server-ip>:8123        # e.g. http://192.168.1.41:8123
   ```

   Port 8123 must be open in the firewall (bootstrap.sh adds it). On an already
   provisioned server run once: `sudo ufw allow 8123/tcp comment "Home Assistant"`

2. **Enable reverse-proxy access** — by default HA rejects requests coming through
   a proxy with HTTP 400. Add this block to `appdata/homeassistant/configuration.yaml`
   on the server, then restart HA:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 172.16.0.0/12   # docker bridge networks (Traefik reaches HA via host-gateway)
       - 127.0.0.1
       - ::1
   ```

   ```bash
   ./scripts/docker/rebuild.sh homeassistant
   ```

3. Access via Traefik:
   - Local:    `http://ha.home.local`
   - External: `https://ha.1218217.xyz` (Cloudflare Tunnel)

## Notes

- **No Authelia** in front of HA — its SSO redirect breaks the HA mobile app and
  API/webhooks. HA has its own login; enable 2FA in HA for external exposure.
- Traefik routing is configured via the **file provider**, not docker labels,
  because a host-network container is not on `traefik-net`. See
  `services/traefik/config/dynamic/homeassistant.yml`. Domains there are hardcoded
  (`ha.home.local` / `ha.1218217.xyz`) since the file provider does not expand
  env vars.
- **Adding a Zigbee/Z-Wave USB stick later:** pass the device through by adding to
  this compose file:
  ```yaml
  devices:
    - /dev/ttyUSB0:/dev/ttyUSB0
  ```
- **Switching off host networking later:** possible without data loss (config lives
  in appdata). You would lose LAN broadcast discovery — only do this if all devices
  are cloud/API based. Then move routing back to docker labels and drop the file
  provider config.
