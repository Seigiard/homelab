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

## Git-versioned automations (packages)

Automations defined in code live in `config/packages/` (this repo) and are
mounted read-only into the container at `/config/packages` — so they survive a
fresh install and are restorable from git. The UI-managed `automations.yaml`
(in appdata) is left untouched.

Enable once: add to `appdata/homeassistant/configuration.yaml` on the server,
then restart HA:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

```bash
./scripts/docker/rebuild.sh homeassistant
```

Each `.yaml` under `config/packages/` is one package and may contain
`automation:`, `sensor:`, `template:`, etc. Current packages:

- `philips_ac3737.yaml` — Philips AC3737 air purifier (schedule, PM2.5 boost,
  filter + water-tank notifications). Entity ids verified against this install;
  push goes to `notify.nothingphone`.
  - Schedule: 22:00 → sleep mode + humidify to 50%; 08:00 → auto mode +
    humidify to minimum 40%.
  - The morning step lowers the humidity target instead of turning the
    humidifier off. On the AC3737 the humidifier entity has
    `supported_features: 0` and no separate function control, so
    `humidifier.turn_off` powers off the **whole appliance**, not just
    humidification — same reason the dashboard humidification button uses
    `button_type: state` rather than a power toggle.
  - Defines a template `binary_sensor.ac3737_humidifier_module_removed`
    (humidifier `on` + `binary_sensor…_humidification` `off`) — the only
    reliable signal that the humidification module is physically out. The
    `water_tank` sensor is unreliable for this: it falsely reads `on` when the
    module is removed (verified by swapping the module in/out). The dashboard
    uses this template sensor to hide the humidification tiles when the module
    is gone. Full entity inventory + the A/B findings live in the file header.

- `hardware_health.yaml` — server hardware alerts from Glances data (see
  "Server hardware monitoring" below). CPU/NVMe overheat (warning + critical) and
  fan-failure (`it8613` fan = 0 RPM) → push via `notify.mobile_app_nothingphone`.
  Messages read values via `states()` (not `trigger.*`) so manual "Run" also works.

## Git-versioned dashboard

The Lovelace dashboard in `config/dashboards/home.yaml` (this repo) is mounted
read-only at `/config/dashboards` and added as a **YAML-mode dashboard** alongside
the default UI-editable one — so the default dashboard stays clickable in the UI
while this one is restorable from git.

Enable once: add to `appdata/homeassistant/configuration.yaml` on the server,
then restart HA:

```yaml
lovelace:
  mode: storage          # default dashboard stays UI-editable
  dashboards:
    home-yaml:
      mode: yaml
      title: Дом
      icon: mdi:home
      show_in_sidebar: true
      filename: dashboards/home.yaml
```

```bash
./scripts/docker/rebuild.sh homeassistant
```

- YAML dashboards have **no visual editor**. To author a card visually, build it on
  the default dashboard, open "Edit → Show code editor", and copy the YAML in.
- Edits to `home.yaml` are picked up by a **browser refresh** (F5) — no HA restart.
- `home.yaml` currently covers the Bedroom ("Спальня") view (AC3737 controls + air/
  filter sensors) in two styles for comparison: stock HA cards on top, a Bubble Card
  variant below. Labels are in Ukrainian. Order: Очищення → Повітря → Зволоження →
  Фільтри. The humidification block reacts to two template/binary sensors:
  - `binary_sensor.ac3737_humidifier_module_removed` on → a single "Зволожувач знято"
    warning replaces the humidification card.
  - module present: the Bubble Card merges humidification + humidity into ONE card.
    Title shows `Зволоження, <target>%` and the subtitle `Поточна <current>%`, both
    written into `.bubble-name`/`.bubble-state` from `styles` (Bubble Card has no
    name/state templating). With water it shows the 40/50/60 presets; without water
    (`…_water_tank` off) it shows a "Немає води" badge. The stock variant keeps a
    separate humidifier card + humidity glance (it can't render the templated lines).
  The Bubble Card block needs Bubble Card installed via HACS, otherwise those cards
  render an error. Lights and the robot vacuum get tiles there once their entity
  ids exist.
- Known limitation: the AC3737's active fan mode cannot be highlighted reliably
  while humidifying. The `philips_airpurifier_coap` integration reports
  `fan.preset_mode: null` whenever humidification is active (device field
  `D0310A=4` breaks its preset match — upstream bug
  [kongo09/philips-airpurifier-coap#356](https://github.com/kongo09/philips-airpurifier-coap/issues/356)),
  and the real mode field is not exposed to HA. Verified mode readback (module
  out, no humidification): Auto→`preset_mode: auto`, Sleep→`sleep`,
  Speed 1/2→`percentage: 50/75` (no `preset_mode`), Turbo→`null/null` (unreadable
  even when dry). So the Bubble Card highlight lights **Auto/Sleep only when not
  humidifying**; Turbo is never highlighted, and while humidifying the mode
  buttons stay neutral (mode unknown) rather than guessing.

## Server hardware monitoring (Glances)

The server's hardware health (CPU/NVMe/GPU temperatures + IT8613E fan RPM) is
surfaced in HA via the **Glances integration**, reusing the running Glances
instance (`services/glances/`, REST API on the host's `127.0.0.1:61208` — that
port is loopback-published in the Glances compose for this).

Setup (one-time, UI): Settings → Devices & Services → Add → **Glances**, host
`127.0.0.1`, port `61208`, API version `4`. Entities get a `127_0_0_1_` prefix,
e.g. `sensor.127_0_0_1_tctl_temperature`, `sensor.127_0_0_1_it8613_0_fan_speed`.

- **Alerts:** `config/packages/hardware_health.yaml` — CPU >85/95 °C, NVMe
  >75/82 °C, fan-failure (`it8613 0/1` = 0 RPM for 2 min). Push via
  `notify.mobile_app_nothingphone` (legacy mobile_app service — supports
  `data.priority/ttl`, unlike the `notify.send_message` path philips uses).
- **Dashboard:** the "Сервер" view in `config/dashboards/home.yaml` — current
  temps/fans + 24 h history graphs.
- **Board temps unavailable:** Glances reuses one label (`it8613 N`) for both a
  temperature and a fan, so HA keeps only the fan entity per label. IT8613E board
  temperatures are therefore not in HA; CPU/NVMe/GPU cover the thermal picture.
  Fan `it8613 2` is unconnected (always 0, excluded from the alert).

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
