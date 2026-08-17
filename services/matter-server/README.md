# Matter Server

Matter fabric controller (`python-matter-server`) for Home Assistant. HA runs in a
container here, so it has **no add-on store** — the Matter integration needs this
standalone server. WebSocket API: `ws://localhost:5580/ws` (host networking, both
containers share the host stack).

## Requirements

- **IPv6 must be enabled on the host.** Matter operational discovery is IPv6-only.
  Check: `sysctl net.ipv6.conf.all.disable_ipv6` → must be `0`.
- **mDNS on the LAN.** Server and device must be in the same broadcast domain;
  the device joins 2.4 GHz Wi-Fi only.
- Firewall: nothing to open for the LAN side, HA talks to 5580 over loopback.

## Deploy

The compose file pins `--primary-interface eno1` (the server's LAN NIC). Change it
if the interface is ever renamed — without it the server logs
`Using 'None' as primary interface` and cannot scope device link-local addresses.
Harmless noise in the log: `Failed to advertise records: Network is unreachable` —
CHIP announces mDNS on every host interface and the docker `veth*`/`br-*` ones have
no IPv6. Also `Failed to get WiFi interface`: the server is Ethernet-only.


```bash
./scripts/docker/deploy.sh matter-server
docker logs -f matter-server        # wait for "Matter Server successfully initialized"
```

## Connect to Home Assistant

Settings → Devices & Services → Add integration → **Matter (BETA)** → untick
"Use the official Matter Server Add-on" → URL `ws://localhost:5580/ws`.

## Commissioning devices

BLE is **not** enabled on the server (see the commented `command:` in the compose
file), so pairing is done from the phone — the phone provides the Bluetooth link
that hands the device its Wi-Fi credentials.

1. Install the Home Assistant Companion app, log into this HA instance.
2. Companion app → Settings → Devices & Services → Add integration → Matter →
   scan the QR code / pairing code from the device.
3. The phone must be on the same Wi-Fi as the server, Bluetooth on.

If the device was already paired into another ecosystem (eWeLink, Apple Home,
Google Home), do **not** factory reset it — use that app's "share device / add to
another Matter ecosystem" function to get a fresh 11-digit pairing code, then enter
it in HA. That path commissions over IP and needs no Bluetooth at all.

## Devices

- **SONOFF SAWF-08P AirGuard** — CO₂ / temperature / humidity, Matter over Wi-Fi
  (2.4 GHz). Powered by USB-C; keep it powered, it is not battery-friendly for
  continuous CO₂ measurement.

## Notes

- Backup `appdata/matter-server/` — it holds the fabric credentials. Losing it
  means re-commissioning every Matter device.
- One device can join several fabrics (HA + eWeLink + Apple) at once via the
  share-code flow; a factory reset drops all of them.
