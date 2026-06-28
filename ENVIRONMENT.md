# Серверное окружение

Детали серверного железа, хранилища и сетевой архитектуры. Список сервисов: `ls services/`.

## Железо

**Hewlett Packard ProDesk 600 G3 SFF** ([datasheet](https://h10032.www1.hp.com/ctg/Manual/c05387853.pdf))

| Компонент | Характеристики                                        |
| --------- | ----------------------------------------------------- |
| CPU       | Intel Core i5-6400 @ 2.70GHz, 4 ядра                 |
| RAM       | 16 GB DDR4 (2 слота свободны)                         |
| NVMe      | Kingston SEDC2000BM8240G 240 GB (система, PCI-E адаптер) |
| HDD       | Seagate ST6000VN006 6 TB (данные)                     |
| GPU       | Intel HD Graphics 530                                 |
| Сеть      | Gigabit Ethernet                                      |
| Слоты     | PCIe x16 + PCIe x4                                   |
| Порты     | USB-C 3.0, USB-A 3.0, USB-A 2.0                      |
| Видео     | 2x DisplayPort + VGA                                  |

**Load average:** при 4 ядрах load < 4.0 — норма.

### Известные проблемы железа

**Kingston DC2000B NVMe (прошивка EIEK51.3):**
- `smartctl` непригоден — генерирует ложные ошибки `Invalid Field in Command` при любом SMART-запросе
- Для проверки здоровья: `nvme smart-log /dev/nvme0n1`
- Sensor 2 (Temperature) зафиксирован на ~82°C — фейковый датчик прошивки, игнорировать
- smartd мониторит только HDD, NVMe исключён (`/etc/smartd.conf`)
- Glances скрывает Sensor 2 (`services/glances/glances.conf`)

### Планы по апгрейду

6-pin разъём питания — проприетарный HP, порт называется "P160". Кабель для подключения доп. дисков: `m2-l20611` (eBay). Пока план: добавить M.2 SSD + один диск без решения вопроса питания.

## UPS

**Eaton Ellipse ECO 900 USB** — подключён по USB к серверу.

| Параметр          | Значение                       |
| ----------------- | ------------------------------ |
| Модель            | Eaton Ellipse ECO 900          |
| Подключение       | USB (usbhid-ups driver)        |
| Мощность          | 900 VA / 500 W                 |
| Мониторинг        | NUT на хосте (standalone mode) |
| Web UI            | PeaNUT (Docker)                |
| Auto-shutdown     | nut-monitor → shutdown при OB  |

**Архитектура:** NUT (`nut-server` + `nut-monitor`) работает на хосте — Docker не может выключить хост. PeaNUT в Docker подключается к хосту через `host.docker.internal:3493`.

**Конфигурация:** `/etc/nut/` (5 файлов, setup-скрипт `09-setup-nut.sh`)

**Проверка:**
```bash
sudo upsc eaton@localhost              # все данные UPS
sudo upsc eaton@localhost ups.status   # OL = online, OB = on battery
sudo upsc eaton@localhost battery.charge
```

## Хранилище

Разделение по принципу **"Appdata vs Data"**:

- **Appdata** (NVMe SSD) — конфиги, БД, метаданные контейнеров
- **Data** (HDD) — медиа, документы, загрузки, бэкапы

### Структура на сервере

```
/opt/homelab/                 # Репозиторий (SSD)
/opt/homelab/appdata/         # Конфиги контейнеров (SSD)

/mnt/data/                    # HDD
  public/                     # Общий доступ (Samba guest)
    movies/
    tv/
    music/
    .torrents-temp/           # Недокачанные файлы
  users/                      # Приватные данные (Samba auth)
    andrew/
      files/
      photos/                 # Immich External Library
      sync/                   # Syncthing
    yuliia/
      files/
      photos/
  backups/                    # Бэкапы контейнеров и БД
```

### Сетевые шары (Samba)

| Путь                | Samba-домен        | Web-домен            | Доступ |
| ------------------- | ------------------ | -------------------- | ------ |
| public/             | files.home.local   | files.home.local     | guest  |
| users/andrew/       | a.files.home.local | files.home.local     | auth   |
| users/andrew/photos |                    | a.photos.home.local  | auth   |
| users/yuliia/       | y.files.home.local | files.home.local     | auth   |
| users/yuliia/photos |                    | y.photos.home.local  | auth   |

### Syncthing

- **Receive Only папки должны иметь `Ignore Permissions = on`.** Файлы пишутся внутри контейнера от `root:root` (PUID/PGID из compose эта сборка не применяет), а permission-биты приходят с macOS-источника и не совпадают. Без Ignore Permissions Syncthing помечает каждый файл как «Locally Changed» (видно по сотням items с суммарным размером ~0 B) и в режиме Receive Only **застревает на полпути**, не докачивая остальное.
- Фикс застрявшей папки: Edit → Advanced → `Ignore Permissions` → Save → **Revert Local Changes** → дождаться, пока Local State догонит Global State.

## Сеть

### Доменная модель

| Уровень    | Домен              | Протокол | Механизм                       |
| ---------- | ------------------ | -------- | ------------------------------ |
| Локальный  | `*.home.local`     | HTTP     | mDNS через Avahi (системный)   |
| Локальный  | `*.1218217.xyz`    | HTTPS    | Split-horizon DNS (AdGuard Home) + Let's Encrypt (Cloudflare DNS challenge) |
| Внешний    | `*.1218217.xyz`    | HTTPS    | Cloudflare Tunnel → Authelia (когда Tailscale выключен) |
| Внешний + Tailscale | `*.1218217.xyz` | HTTPS | Напрямую на сервер по tailnet, минуя Cloudflare/Authelia (см. раздел «Tailscale») |

### Инфраструктурные компоненты

- **Traefik v3** — reverse proxy, auto-discovery сервисов через Docker labels
- **Authelia** — SSO аутентификация (forwardAuth middleware для Traefik)
- **Cloudflared** — Cloudflare Tunnel для внешнего доступа
- **AdGuard Home** — DNS + блокировка рекламы + split-horizon для локального HTTPS
- **Avahi** — mDNS для `*.home.local` (системный сервис, не Docker)
- **Tailscale** — mesh VPN (WireGuard) для удалённого SSH-доступа к хосту. Host-сервис, не Docker (как NUT). См. раздел «Tailscale» ниже

### Важные настройки

- Все Docker-сервисы в сети `traefik-net`
- Cloudflare: SSL mode = Flexible, Always Use HTTPS = ON
- Homepage + Docker socket требует `user: root`

### DNS хоста (netplan + systemd-resolved)

Хост резолвит **только через локальный AdGuard Home** (`127.0.0.1:53`), иначе ломается split-horizon для `*.1218217.xyz` и запросы не попадают в фильтры/статистику AdGuard.

`/etc/netplan/01-netcfg.yaml`:

```yaml
network:
  version: 2
  ethernets:
    eno1:
      addresses:
        - 192.168.1.41/24
      routes:
        - to: default
          via: 192.168.1.1
      accept-ra: false        # отключает IPv6 RA-DNS от роутера (fe80::...) в обход AdGuard
      nameservers:
        addresses:
          - 127.0.0.1         # единственный основной DNS — локальный AdGuard
```

`1.1.1.1` — строгий fallback (только когда AdGuard недоступен), задаётся через drop-in `/etc/systemd/resolved.conf.d/fallback.conf`:

```ini
[Resolve]
FallbackDNS=1.1.1.1 1.0.0.1
```

- **Не добавлять `1.1.1.1` в `nameservers.addresses`** — systemd-resolved считает все адреса списка равноправными и ротирует их, из-за чего часть запросов уходит мимо AdGuard (split-horizon ломается непредсказуемо).
- **`accept-ra: false`** убирает третий DNS-сервер (`fe80::...`), который роутер навязывает по IPv6 Router Advertisement. Без него `resolvectl status` показывает на интерфейсе 3 DNS вместо одного.
- Применение: `sudo netplan apply && sudo systemctl restart systemd-resolved`.
- Проверка: `resolvectl status` → на Link `eno1` должно быть `DNS Servers: 127.0.0.1`, в Global — `Fallback DNS Servers: 1.1.1.1 1.0.0.1`. `resolvectl query dns.1218217.xyz` должен вернуть локальный `192.168.1.41`.

### Tailscale (mesh VPN)

Удалённый доступ по приватной сети tailnet (WireGuard) без проброса портов наружу. Работает на хосте, не в Docker (как NUT). Setup: `scripts/setup/10-setup-tailscale.sh`, переменные — в `config.sh` (`TS_*`).

| Параметр       | Значение | Зачем |
| -------------- | -------- | ----- |
| Имя ноды       | `home` (`100.78.130.93`) | hostname в tailnet |
| Tailscale SSH  | вкл (`--ssh`) | `tailscale ssh seigiard@home` — без проброса портов и SSH-ключей; доступ по tailnet-идентичности |
| `accept-dns`   | **`false`** | критично, см. ниже |
| Subnet router  | `--advertise-routes=192.168.1.41/32` | доступ к сервисам напрямую по tailnet, см. ниже |
| Exit node      | выкл | `TS_ADVERTISE_EXIT_NODE=false`; машинерия (forwarding) готова, при true нужен approval в админке |

- **`accept-dns=false` обязательно.** С `accept-dns=true` Tailscale перехватывает `/etc/resolv.conf` (`nameserver 100.100.100.100`, MagicDNS) и хост начинает резолвить в обход AdGuard → ломается split-horizon для `*.1218217.xyz` (всё, что читает resolv.conf напрямую — приложения, Docker-контейнеры — получает публичный IP вместо `192.168.1.41`). Серверу MagicDNS не нужен. При `false` `/etc/resolv.conf` остаётся managed by systemd-resolved (`nameserver 127.0.0.1`).
- **Tailscale SSH и ACL.** Подключение управляется политикой tailnet (Access Controls), а не файлами на хосте. Дефолтная политика содержит `ssh` с `action: "check"` — при входе бывает разовая браузер-проверка. Если доступ отклоняется — нужно добавить `ssh`-правило в админке (https://login.tailscale.com/admin/acls); серверным скриптом это не воспроизводится.
- **Аутентификация интерактивная** (без auth-key): при первом `tailscale up` печатается URL для входа в браузере. Auth-key намеренно не используем — нет секрета в репо и нечему протухать.
- Проверка: `tailscale status`; `sudo tailscale debug prefs | grep -E '"RunSSH"|"CorpDNS"'` → `RunSSH: true`, `CorpDNS: false`.

#### Доступ к сервисам по tailnet (subnet router + split-DNS)

Цель: устройство **вне дома с поднятым Tailscale** ходит на `*.1218217.xyz` **напрямую на домашний сервер**, минуя Cloudflare и Authelia. Переключение автоматическое — рулит DNS:

| Откуда | Tailscale | Путь |
| ------ | --------- | ---- |
| Дома (LAN) | — | напрямую → `192.168.1.41` |
| Извне | выключен | Cloudflare → Authelia → сервер |
| Извне | включён | напрямую на сервер по tailnet |

Механика (две части — серверная воспроизводится скриптом, админская — вручную):

1. **Subnet router (сервер).** `--advertise-routes=192.168.1.41/32` + IP forwarding (`/etc/sysctl.d/99-tailscale.conf`) — чтобы удалённый клиент дотягивался до `192.168.1.41` через tailnet. `/32` (только сервер), а не `/24`: иначе конфликт с чужой сетью `192.168.1.0/24`. Маршрут нужно **одобрить** в админке (Machines → `home` → Edit route settings).
2. **Split-DNS (админка tailnet).** DNS → Nameservers → Custom: `1218217.xyz` → `100.78.130.93` (домашний AdGuard). Клиент с Tailscale шлёт запросы про этот домен в AdGuard, тот отдаёт split-horizon `192.168.1.41` — тот же ответ, что и дома. Сертификат валиден (Traefik отдаёт по Host-заголовку).
3. **Клиент.** Нужен `accept-routes` (на маке `sudo tailscale set --accept-routes`; на телефоне — галка subnets) + включённый Tailscale DNS.

Важно:
- **Global nameserver оставлен NextDNS** (не домашний AdGuard). Причина — надёжность: если global = AdGuard, весь DNS роуминг-устройств зависит от аптайма дома (сервер упал → у телефона на улице нет интернета вообще). NextDNS — облачный, фильтрует рекламу, не зависит от дома. Домашний AdGuard через split-DNS получает только `1218217.xyz`.
- **Android Private DNS (DoT) конфликтует с MagicDNS** — даёт «private DNS server cannot be accessed». Фикс: на телефоне Настройки → Private DNS → Off, затем включить Use Tailscale DNS.
- Проверка с устройства вне дома: `curl -s https://dns.1218217.xyz -o /dev/null -w '%{remote_ip}\n'` → `192.168.1.41`. На Android `dig +short` **не показателен** — Termux dig ходит мимо системного резолвера; верный признак — `remote_ip` у curl или `dig @100.78.130.93`.
