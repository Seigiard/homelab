# Миграция сервера: HP ProDesk 600 G3 → AOOSTAR WTR Pro

**Дата:** 2026-06-25
**Стратегия:** lift-and-shift — физически переставить системный NVMe на новое железо, Ubuntu грузится как есть.

## Контекст

| | Старое (HP ProDesk 600 G3 SFF) | Новое (AOOSTAR WTR Pro) |
| --- | --- | --- |
| CPU | Intel Core i5-6400 (4 ядра) | AMD Ryzen 7 |
| Формат | SFF десктоп | 4-bay NAS Mini PC |
| Слоты | 1× M.2 (адаптер) + SATA | 2× M.2 + 4 отсека SATA |

- Мигрирует **один диск** — NVMe Kingston SEDC2000BM8240G 240 ГБ (система + данные на нём же).
- HDD 6 ТБ сейчас **отключён**, данных на нём нет → `/mnt/data`, fstab, smartd `/dev/sda` неактуальны.
- ОС: Ubuntu 24.04.3 LTS, ядро 6.8.0-106-generic → `amdgpu` для Ryzen из коробки, HWE-ядро не нужно.
- Ни один сервис не использует GPU-транскодинг или USB-проброс (нет `/dev/dri`, нет `devices:` в compose) → переход Intel→AMD для сервисов прозрачен.

## 🔴 Критично — без этого сервер не поднимется

### 1. Сетевой интерфейс — wildcard-match вместо `eno1`
Главный блокер. `/etc/netplan/01-netcfg.yaml` жёстко прибит к `eno1` со статикой `192.168.1.41`. На AOOSTAR NIC получит другое имя → статика не применится → нет сети → AdGuard DNS недоступен → всё ложится.

**Решение: заменить точное имя на `match: name: "en*"` ДО переноса (на старом сервере).**
Тогда первая загрузка на AOOSTAR поднимется headless сама на `.41` — монитор уже не обязателен, только как страховка.

Статику оставляем — DHCP здесь нельзя: split-horizon DNS, AdGuard rewrites и Samba-домены ждут сервер строго на `192.168.1.41`, а `nameservers` обязан быть только `127.0.0.1` (DHCP навяжет DNS роутера и сломает split-horizon).

`/etc/netplan/01-netcfg.yaml`:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    lan:
      match:
        name: "en*"
      addresses:
        - 192.168.1.41/24
      routes:
        - to: default
          via: 192.168.1.1
      accept-ra: false              # без IPv6 RA-DNS от роутера в обход AdGuard
      nameservers:
        addresses:
          - 127.0.0.1               # единственный DNS — локальный AdGuard
```

Проверка после загрузки:
```bash
ip -br addr                                # интерфейс с .41 и state UP
resolvectl status                          # на Link → DNS Servers: 127.0.0.1
resolvectl query dns.1218217.xyz           # должен вернуть локальный 192.168.1.41
```

**Нюанс — двойной NIC:** у WTR Pro обычно 2× 2.5GbE. При `en*` адрес `.41` пропишется на оба порта. Пока кабель в одном — ок (второй без carrier не маршрутизируется). Воткнёшь оба — будет конфликт IP.

`scripts/lib/config.sh:35` `NET_INTERFACE="eno1"` нужен только для `ethtool --set-eee` в bootstrap. С wildcard реальное имя узнаёшь после загрузки (`ip -br link`) и подставляешь, если будешь перепрогонять bootstrap. Не блокирует.

### 2. BIOS AOOSTAR
- UEFI boot — **ON** (NVMe установлен в UEFI-режиме на HP).
- Secure Boot — **OFF** (как было).
- Boot order — NVMe Kingston первым.

## 🟡 Проверить после первой загрузки

- **UPS / NUT:** `sudo upsc eaton@localhost ups.status` → ждём `OL`. USB usbhid-ups переподключится сам, PeaNUT через `host.docker.internal:3493` не меняется.
- **AMD GPU:** `lspci -k | grep -A3 -i vga` → драйвер `amdgpu` загружен. На сервисы не влияет.
- **smartd:** будет ругаться на отсутствующий `/dev/sda` (HDD отключён) — безвредно. Если мешает — временно закомментировать строку в `/etc/smartd.conf`.

## 🟢 Переезжает прозрачно (трогать не надо)
Docker + все volume, `/opt/homelab` (symlink на том же NVMe), appdata, hostname, Avahi/mDNS (перепривяжется к новому интерфейсу), Cloudflare Tunnel, Traefik, NUT-конфиги.

## Порядок действий

1. **На старом сервере:** заменить netplan на wildcard `en*` (шаг 1), `sudo netplan apply` проверить, что сеть жива.
2. Бэкап appdata перед вскрытием (на всякий случай).
3. Graceful stop сервисов на HP, затем выключение хоста.
4. Переставить NVMe Kingston в M.2-слот AOOSTAR.
5. BIOS: UEFI ON, Secure Boot OFF, boot order → NVMe.
6. Загрузка (headless ок) → проверить сеть/DNS (шаг 1), UPS, amdgpu, smartd.
7. `docker compose` сервисы поднимутся сами; прогнать `./scripts/healthcheck.sh`.

## 💡 Возможность на потом (не часть переезда)
WTR Pro — 4-bay NAS, а 6 ТБ HDD лежит отключённый и всё крутится на 240 ГБ SSD.
Удачный момент вернуть исходную схему из `ENVIRONMENT.md` (appdata на SSD, данные на HDD):
воткнуть HDD в bay, поднять `/mnt/data` по UUID, снять давку с системного SSD.
Корпус всё равно вскрывается сейчас. Рассмотреть и второй диск под mirror/бэкап — сейчас единичный HDD = нет избыточности.

## Открытые вопросы
- Точная модель Ryzen 7 в этом экземпляре WTR Pro (для финальной уверенности по amdgpu, хотя 6.8 покрывает и Vega, и RDNA-iGPU).
- Имя нового интерфейса больше не критично (wildcard `en*`), но узнать его стоит для `config.sh`/ethtool.
