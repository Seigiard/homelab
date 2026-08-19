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
  Also self-heals the Glances integration: if its sensors sit `unavailable` for
  5 min (stuck failed-setup after a restart race), the `server_glances_autoreload`
  automation calls `homeassistant.reload_config_entry` — the programmatic Reload.

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
- First card of the Bedroom view is "Повітря" — the SONOFF SAWF-08P AirGuard
  (Matter, see `services/matter-server/`): CO₂ in ppm plus the device's own
  qualitative rating, temperature and humidity as flat pills, tap → CO₂ history.
  Icon turns amber at 1000 ppm and red at 1400 ppm. Entity ids are prefixed
  `sensor.bedroom_sonoff_air_quality_monitor_*`.
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
- The AC3737 fan mode used to be unreadable while humidifying; **fixed locally by
  patching the HACS integration** — see "AC3737 mode readback patch" below. The
  Bubble Card highlight now lights Auto/Sleep/Turbo from `preset_mode` in every
  state. Manual speeds 1 and 2 are not presets (`preset_mode: null`,
  `percentage: 50/75`), so no button lights up for them.

### AC3737 mode readback patch

`philips_airpurifier_coap` v0.37 cannot read the AC3737's fan mode while
humidification runs — `fan.preset_mode` and `percentage` are both `null`
(upstream issue
[kongo09/philips-airpurifier-coap#356](https://github.com/kongo09/philips-airpurifier-coap/issues/356)).

Cause: in `custom_components/philips_airpurifier_coap/philips.py`, class
`PhilipsAC3737` lists field `D0310A` (`NEW2_MODE_A`) in all seven mode dicts with
value 2 or 3, and both properties require every field to match. The same repo's
`const.py` declares `D0310A` a *humidification* binary sensor (`value == 4`), and
this device reports 4 whenever it humidifies — so the match never succeeds. Same
bug shape as AC3420 / issue #371, fixed upstream in PR #374 by commenting the
offending field out.

Local fix: comment out the seven `PhilipsApi.NEW2_MODE_A: <n>,` lines inside
`class PhilipsAC3737` only. **Do not touch** `AVAILABLE_BINARY_SENSORS`, which
legitimately uses the same field for the humidification sensor.

```bash
docker exec -i homeassistant python - <<'PATCH'
import re, glob, shutil
p = '/config/custom_components/philips_airpurifier_coap/philips.py'
shutil.copy(p, p + '.orig-v0.37')
src = open(p).read()
i, j = src.index('class PhilipsAC3737('), src.index('class PhilipsAC3829(')
new, n = re.subn(r'(?m)^(\s*)(PhilipsApi\.NEW2_MODE_A: [0-9]+,)$',
                 r'\1# \2  # AC3737: humidification flag, not a fan mode field (upstream #356)',
                 src[i:j])
open(p, 'w').write(src[:i] + new + src[j:])
for d in glob.glob('/config/custom_components/philips_airpurifier_coap/**/__pycache__', recursive=True):
    shutil.rmtree(d)
print('patched lines:', n)
PATCH
```

Must print `patched lines: 7`, then restart HA core. A backup of the original is
left next to the file as `philips.py.orig-v0.37`.

**The patch lives in `appdata/`, not in git, and any HACS update of the
integration silently reverts it.** `binary_sensor.ac3737_mode_unreadable` in
`config/packages/philips_ac3737.yaml` watches for that and pushes to the phone.

Verified on AC3737/10 fw 1.0.4, integration v0.37, 2026-08-19. Modes were switched
on the appliance panel, so Home Assistant could not be echoing its own command
back (its setter writes the requested mode straight into the coordinator state,
which makes "set from HA, then read from HA" prove nothing):

| Mode set on the appliance | `preset_mode` | `percentage` | before the patch |
|---|---|---|---|
| Auto | `auto` | `null` | `null` / `null` |
| Sleep | `sleep` | 25 | `null` / `null` |
| Speed 1 | `null` | 50 | `null` / `null` |
| Speed 2 | `null` | 75 | `null` / `null` |
| Turbo | `turbo` | 100 | `null` / `null` |

Identical with the humidifier module in (humidifying) and removed (dry). Turbo was
unreadable in *both* states before the patch.

Also measured, and worth knowing: unpatched v0.37 sends `D0310A` together with the
mode (`{"D03102":1,"D0310A":2,"D0310C":17}` for sleep), the device silently ignores
that field and obeys `D0310C` alone, and humidification never stops — so the bug is
read-side only. Field `D0310D` tracks the fan mode (auto/sleep 5, turbo 4,
speed 1 → 1, speed 2 → 2), so it is not a humidification indicator on this model.

> Do not read device state with `docker exec homeassistant python -m aioairctrl …`
> while HA is running: the appliance serves a single status observation, the CLI
> steals it, HA's client dies with `aiocoap.error.LibraryShutdown`, and every
> service call fails with "unknown error" until HA's 180 s watchdog reconnects.
> Read HA's own `observation status:` debug lines instead:
> `docker logs --since 5m homeassistant | grep 'observation status' | tail -1`
> (needs `logger.set_level` with `aioairctrl.coap.client: debug`).

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
- **Self-heal:** if HA and Glances restart at the same time (e.g. a server reboot),
  HA can hit Glances mid-restart and permanently fail the integration setup — the
  HA Glances integration does not wrap the connection error in `ConfigEntryNotReady`,
  so it never retries and every sensor stays `unavailable` until a manual Reload. The
  `server_glances_autoreload` automation detects 5 min of `unavailable` and reloads
  the entry automatically.

## Notes

- **No Authelia** in front of HA — its SSO redirect breaks the HA mobile app and
  API/webhooks. HA has its own login; enable 2FA in HA for external exposure.
- Traefik routing is configured via the **file provider**, not docker labels,
  because a host-network container is not on `traefik-net`. See
  `services/traefik/config/dynamic/homeassistant.yml`. Domains there are hardcoded
  (`ha.home.local` / `ha.1218217.xyz`) since the file provider does not expand
  env vars.
- **Matter devices** need a separate controller container — this HA has no add-on
  store. See `services/matter-server/`.
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
