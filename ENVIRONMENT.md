# Серверное окружение

Детали серверного железа, хранилища и сетевой архитектуры. Список сервисов: `ls services/`.

## Железо

**AOOSTAR WTR Pro** — 4-bay NAS-платформа. Миграция с HP ProDesk 600 G3 методом lift-and-shift (системный NVMe переставлен физически, 2026-06).

| Компонент | Характеристики                                              |
| --------- | ----------------------------------------------------------- |
| CPU       | AMD Ryzen 7 5825U with Radeon Graphics — 8 ядер / 16 потоков (Zen3 «Barcelo») |
| RAM       | 32 GB DDR4 (≈30 GiB доступно)                                |
| NVMe      | Kingston SEDC2000BM8240G 240 GB (система; перенесён с HP)    |
| HDD данные | 2× Seagate ST6000VN006 6 TB — зеркало RAID1 (`/dev/md0`) → `/mnt/data`, 5.4 TiB |
| HDD бэкап  | Seagate ST8000VN002 8 TB (`sdd`) — холодный бэкап, монтируется вручную раз в неделю |
| GPU       | AMD Radeon Vega 8 (iGPU Ryzen 5825U), драйвер `amdgpu` (in-kernel) |
| Сеть      | 2× 2.5GbE onboard: `eno1` (активный) + `enp2s0` (резерв)     |
| Отсеки    | 4× hot-swap bay (3.5"/2.5")                                 |

**Load average:** при 8 ядрах load < 8.0 — норма.

### Известные проблемы железа

**Kingston DC2000B NVMe (прошивка EIEK51.3):**
- `smartctl` непригоден — генерирует ложные ошибки `Invalid Field in Command` при любом SMART-запросе
- Для проверки здоровья: `nvme smart-log /dev/nvme0n1`
- Sensor 2 (Temperature) зафиксирован на ~82°C — фейковый датчик прошивки, игнорировать
- smartd мониторит только HDD, NVMe исключён (`/etc/smartd.conf`)
- Glances скрывает Sensor 2 (`services/glances/glances.conf`)
- `lm-sensors`: фейк виден как `Sensor 2` (`temp3` чипа `nvme-pci-*`, ~82°C), и его `temp3_min/max` сыплют `I/O error` в выводе `sensors`. Реальная температура — `Composite` (`temp1`). Оба прячутся `/etc/sensors.d/kingston-nvme.conf` → `ignore temp3` для `nvme-pci-*`
- **`udisks2` замаскирован** (`bootstrap.sh` → `systemctl mask udisks2`): служба периодически опрашивает диски и засоряет журнал теми же ложными NVMe-ошибками. Побочный эффект — предупреждение fwupd, см. ниже

### fwupd: «UEFI ESP partition not detected»

`fwupdmgr get-upgrades` печатает предупреждение и не может применить обновления Secure Boot:

```
WARNING: UEFI ESP partition not detected or configured
Update Error: Not updatable as UEFI ESP partition not detected
```

**Это не поломка, а следствие маскировки `udisks2`.** ESP на месте (`nvme0n1p1`, 1 GB, vfat, смонтирован в `/boot/efi`), но fwupd перечисляет разделы только через D-Bus API udisks2, а не через `/etc/fstab`. Диагностика упирается в `fwupdtool esp-list` → `Unit udisks2.service is masked`.

Цепочка: `udisks2 замаскирован` → fwupd не видит ESP → dbx/db-обновления показываются, но не ставятся.

**Действий не требуется.** Secure Boot на этой машине **выключен** (`mokutil --sb-state` → `SecureBoot disabled`), поэтому предлагаемые dbx/db — списки ключей UEFI, которые никто не читает. Обновлений прошивки самого железа fwupd не находит вообще (все устройства в «no available firmware updates»). Размаскировать udisks2 ради этого = вернуть спам NVMe-ошибок в журнал без выигрыша.

**Что уже пробовали и что не работает** (чтобы не повторять):

- `EspLocation=/boot/efi` в секции `[fwupd]` файла `/etc/fwupd/fwupd.conf` — **не помогает** (проверено на fwupd 2.0.20, Ubuntu 24.04). Предупреждение и `Update Error` остаются: явный путь к ESP не снимает зависимость от udisks2, она нужна fwupd и дальше по коду. Настройку откатили.
- `apt install udisks2` — пакет и так установлен (`2.10.1`), дело именно в маске службы, а не в отсутствии пакета.

Единственный работающий способ убрать предупреждение — `sudo systemctl unmask udisks2 && sudo systemctl enable --now udisks2`, что возвращает спам ложных NVMe-ошибок в журнал. **Не делаем.**

**Прочее из вывода fwupd:** `OEMCOMPUTER PK` / `OEMCOMPUTER KEK CA` / `OWN CA` — Secure Boot ключи, прошитые производителем AOOSTAR вместо стандартных Microsoft. Нормально для этой платы, на выключенном Secure Boot роли не играет.

### Платформа AMD (после миграции)

- **`amdgpu` из коробки** на ядре Ubuntu 24.04 (6.8) — переход Intel→AMD прозрачен, проприетарных драйверов не нужно. `i915` (Intel GPU) просто не подгружается.
- **CPU-микрокод:** доустановить `amd64-microcode` (`sudo apt install amd64-microcode && sudo update-initramfs -u`); `intel-microcode`, если остался от прошлого железа, на AMD не используется (можно `apt purge`). Не критично для загрузки, рекомендуется для фиксов CPU.
- **VAAPI-транскодинг** (если появится Jellyfin/Immich): на AMD — `mesa-va-drivers` (radeonsi), **не** Intel `intel-media-va-driver`.
- **Сенсоры:** температуры читаются через `k10temp` (AMD), не `coretemp`; при необходимости `sudo sensors-detect`.

### Управление вентиляторами (Super-I/O IT8613E)

Платой управляет Super-I/O чип **ITE IT8613E** (`sensors-detect` находит его на `0xa30`). **Штатное ядро Ubuntu 24.04 (6.8) его не поддерживает** — chip ID `0x8613` нет в in-kernel `it87`, поэтому по умолчанию `/sys/class/hwmon` показывает только `nvme`/`k10temp`/`amdgpu`, обороты/PWM не видны.

**Вентилятором рулит EC/BIOS** (автоматическая кривая по температуре) — и делает это хорошо: при остывании наблюдалось `fan2` 1412 → 1008 RPM. Управление **оставлено за EC**, своя кривая не настраивается (manual mode рискует «застывшими оборотами», если управляющий процесс упадёт).

**Чтение оборотов под Linux** — через out-of-tree DKMS-драйвер [`frankcrawford/it87`](https://github.com/frankcrawford/it87):

```bash
sudo apt install dkms build-essential git linux-headers-$(uname -r)
git clone https://github.com/frankcrawford/it87.git && cd it87 && sudo ./dkms-install.sh
sudo modprobe it87 force_id=0x8613 ignore_resource_conflict=1
```

Persistent (видимость после ребута, без вмешательства в управление):

```bash
echo "options it87 force_id=0x8613 ignore_resource_conflict=1" | sudo tee /etc/modprobe.d/it87.conf
echo "it87" | sudo tee /etc/modules-load.d/it87.conf
```

- `force_id=0x8613` обязателен (автодетект не срабатывает); `ignore_resource_conflict=1` — вместо системного `acpi_enforce_resources=lax` (тот ломает загрузку).
- **Маппинг:** `fan2`/`pwm2` (≈CPU, низкий duty ~16%) и `fan3`/`pwm3` (≈HDD-корзина, ~51%); `fan4` не подключён. Оба `pwmX_enable = 2` (авто).
- **Шум в `sensors` — игнорировать:** вольтажные `ALARM` (`in0`, `3VSB`…) и абсурдные пороги температур — мусорные дефолты generic-драйвера, не настоящие тревоги. Реальные данные — только `fanX` (RPM) и `temp2`/`temp3`. Прячется через `/etc/sensors.d/aoostar-it8613.conf` (`ignore` напряжений / `fan1,4,5` / `temp1` / `intrusion0`). После фильтра вывод `it8613` полностью чистый: `fan2`/`fan3` + `temp2`/`temp3`. Конфиг пишет шаг `11-setup-fan-sensors.sh`. _Две строки `temp3_min/max I/O error` в общем выводе `sensors` относятся к **NVMe Kingston** (фейковый Sensor 2), а не к it8613 — см. «Известные проблемы железа»._
- **Мониторинг в Home Assistant:** температуры (CPU/NVMe/GPU) и обороты `it8613 0/1` выведены в HA через интеграцию Glances — графики + алерты (перегрев, отказ вентилятора). Подробности: `services/homeassistant/README.md` → «Server hardware monitoring». Board-температуры it8613 в HA недоступны (коллизия лейблов Glances).

### Планы по апгрейду

- Перенести живые данные из `/mnt/data-tmp` (временно на системном NVMe) в `/mnt/data` на зеркале и вернуть `DATA_PATH=/mnt/data` в `.env`. См. «Хранилище» → «Переходное состояние».
- Автоматизировать недельный бэкап зеркала на 8 ТБ диск `sdd` (сейчас монтируется и копируется вручную).
- Один отсек из четырёх свободен (в четвёртом временно стоит Samsung 186 ГБ, с которого стягиваются старые данные).

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

### Диски

| Устройство | Диск                        | Роль |
| ---------- | --------------------------- | ---- |
| `sda`+`sdb` | 2× Seagate ST6000VN006 6 TB | RAID1 `md0` → `/mnt/data` |
| `sdd`      | Seagate ST8000VN002 8 TB    | Холодный бэкап, обычно не смонтирован |
| `sdc`      | Samsung SP2004C 186 GB      | **Временный** — стягивание старых данных, после переноса вынимается |
| `nvme0n1`  | Kingston SEDC2000BM8240G 240 GB | Система + appdata |

Инвентаризация: `lsblk -d -o NAME,SIZE,MODEL,SERIAL,ROTA,TRAN` (`ROTA=1` — HDD, `0` — SSD/NVMe).

**SMART на SATA-дисках работает нормально** — запрет `smartctl` касается только NVMe Kingston (см. «Известные проблемы железа»). Приёмка новых дисков: `sudo smartctl -x /dev/sdX` (интересуют `Power_On_Hours`, `Reallocated_Sector_Ct`, `Current_Pending_Sector`, `Offline_Uncorrectable`, `UDMA_CRC_Error_Count` — все нули у нового диска), затем `sudo smartctl -t long /dev/sdX` (≈10–13 ч на 6–8 ТБ, идёт в прошивке диска, обрыв SSH не мешает, перезагрузка прерывает) и `sudo smartctl -l selftest /dev/sdX` → ждём `Extended offline  Completed without error`.

### RAID1 (`/dev/md0`)

Зеркало на **целых дисках, без разделов** (`mdadm --create /dev/md0 --level=1 --raid-devices=2 --bitmap=internal /dev/sda /dev/sdb`) — оба диска одной модели, возни с выравниванием разделов нет. `--bitmap=internal` (write-intent bitmap): после аварийного выключения пересинхронизируются только изменённые участки, а не все 5.5 ТБ.

- ФС: `mkfs.ext4 -L data -m 1` — резерв под root снижен 5% → 1%, это ~220 ГБ обратно в доступное место. `/mnt/data` не корневая ФС, её заполнение систему не валит.
- Монтирование по UUID в `/etc/fstab`: `defaults,noatime,nofail,x-systemd.device-timeout=30 0 2`. `nofail` обязателен — иначе неподнявшийся массив уронит загрузку в аварийную консоль на сервере без монитора.
- **`ARRAY`-строка в `/etc/mdadm/mdadm.conf` + `update-initramfs -u` обязательны** (`sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf`). Без этого массив после перезагрузки поднимается как `/dev/md127`.

Проверка состояния:

```bash
cat /proc/mdstat                    # [2/2] [UU] — оба диска в строю; [U_] — деградация
sudo mdadm --detail /dev/md0
```

Первичная синхронизация после создания — ~8.5 часа (186 МБ/с), массив при этом уже пригоден к работе.

**Замена сбойного диска:** `sudo mdadm --manage /dev/md0 --fail /dev/sdX --remove /dev/sdX`, физически заменить, затем `sudo mdadm --manage /dev/md0 --add /dev/sdY` и следить за `resync` в `/proc/mdstat`. Зеркало ≠ бэкап: удаление файла удаляет его с обоих дисков, поэтому холодная копия на `sdd` нужна отдельно.

### Переходное состояние (данные ещё не на зеркале)

Массив собран и смонтирован в `/mnt/data`, но **пустой**. Живые данные сервисов лежат в `/mnt/data-tmp` на системном NVMe (`.env` → `DATA_PATH=/mnt/data-tmp`) — временный фоллбэк с тех пор, как выпал прежний одиночный HDD. Пока `DATA_PATH` не переключён, все контейнеры (`syncthing`, `filebrowser`, `samba` и прочие, монтирующие `${DATA_PATH}/public` и `${DATA_PATH}/users`) пишут именно туда. Реальный путь любого тома: `docker inspect <svc> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'`.

### Структура на сервере

```
/opt/homelab/                 # Репозиторий (SSD)
/opt/homelab/appdata/         # Конфиги контейнеров (SSD)

/mnt/data/                    # RAID1 md0 (2× 6 TB HDD), 5.4 TiB
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
| Внешний    | `*.1218217.xyz`    | HTTPS    | Cloudflare Tunnel → Authelia    |

### Инфраструктурные компоненты

- **Traefik v3** — reverse proxy, auto-discovery сервисов через Docker labels
- **Authelia** — SSO аутентификация (forwardAuth middleware `authelia@docker` для Traefik)
- **HTTP Basic Auth** — общий middleware `basic-auth@docker` (определён на контейнере traefik, креды в `.env` → `BASIC_AUTH_USERS`). Для feed-клиентов (OPDS/подкасты: `opds`, `opml`, `ytpod`), которые не проходят SSO-редирект Authelia — подписка через `user:pass@host`
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

`/etc/netplan/01-netcfg.yaml` (генерируется `bootstrap.sh` из `NET_INTERFACE_MATCH` в `config.sh`):

```yaml
network:
  version: 2
  ethernets:
    lan:
      match:
        name: "en*"           # wildcard, не имя устройства — не зависит от железа (eno1, enpXsY, 2.5GbE NAS)
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

- **Почему wildcard, а не имя интерфейса:** при миграции на другое железо имя меняется (`eno1` → `enpXsY` и т.п.), хардкод имени оставил бы сервер без статики и DNS. `match: name: "en*"` совпадает с любым Ethernet-именем Ubuntu 24.04.
- **Двойной NIC на AOOSTAR.** Под `en*` подпадают оба onboard 2.5GbE: `eno1` (активный, кабель здесь) и `enp2s0` (резерв, без линка). Любой USB-Ethernet (`enxXXXX`) тоже совпал бы. `.41` пропишется на все совпавшие порты — пока кабель воткнут в **один** порт, конфликта нет (осознанный компромисс). Держать линк в одном onboard-порту.
- **EEE-off** (`nic-tuning.service`) резолвит активный интерфейс в рантайме по дефолтному маршруту (`ip route show default`) — тоже без привязки к имени.

`1.1.1.1` — строгий fallback (только когда AdGuard недоступен), задаётся через drop-in `/etc/systemd/resolved.conf.d/fallback.conf`:

```ini
[Resolve]
FallbackDNS=1.1.1.1 1.0.0.1
```

- **Не добавлять `1.1.1.1` в `nameservers.addresses`** — systemd-resolved считает все адреса списка равноправными и ротирует их, из-за чего часть запросов уходит мимо AdGuard (split-horizon ломается непредсказуемо).
- **`accept-ra: false`** убирает третий DNS-сервер (`fe80::...`), который роутер навязывает по IPv6 Router Advertisement. Без него `resolvectl status` показывает на интерфейсе 3 DNS вместо одного.
- Применение: `sudo netplan apply && sudo systemctl restart systemd-resolved`.
- Проверка: `resolvectl status` → на активном Link (имя зависит от железа, см. `ip -br addr`) должно быть `DNS Servers: 127.0.0.1`, в Global — `Fallback DNS Servers: 1.1.1.1 1.0.0.1`. `resolvectl query dns.1218217.xyz` должен вернуть локальный `192.168.1.41`. Офлайн (без линка) локальный резолв проверяется напрямую: `dig @127.0.0.1 dns.1218217.xyz +short` → `192.168.1.41`.

### Tailscale (mesh VPN)

**SSH к хосту и mesh между устройствами** по приватной сети tailnet (WireGuard), без проброса портов наружу. Работает на хосте, не в Docker (как NUT). Setup: `scripts/setup/10-setup-tailscale.sh`, переменные — в `config.sh` (`TS_*`). Роль — только SSH+mesh; удалённый доступ к сервисам — через Cloudflare (см. доменную таблицу).

| Параметр       | Значение | Зачем |
| -------------- | -------- | ----- |
| Имя ноды       | `home` (`100.78.130.93`) | hostname в tailnet |
| Tailscale SSH  | вкл (`--ssh`) | `tailscale ssh seigiard@home` — без проброса портов и SSH-ключей; доступ по tailnet-идентичности |
| `accept-dns`   | **`false`** | критично, см. ниже |
| Subnet router  | **выкл** (`TS_ADVERTISE_ROUTES=""`) | НЕ анонсируем — см. Грабли |
| Exit node      | выкл | `TS_ADVERTISE_EXIT_NODE=false` |

- **`accept-dns=false` обязательно.** С `accept-dns=true` Tailscale перехватывает `/etc/resolv.conf` (`nameserver 100.100.100.100`, MagicDNS) и хост начинает резолвить в обход AdGuard → ломается split-horizon для `*.1218217.xyz` (всё, что читает resolv.conf напрямую — приложения, Docker-контейнеры — получает публичный IP вместо `192.168.1.41`). Серверу MagicDNS не нужен. При `false` `/etc/resolv.conf` остаётся managed by systemd-resolved (`nameserver 127.0.0.1`).
- **Tailscale SSH и ACL.** Подключение управляется политикой tailnet (Access Controls), а не файлами на хосте. Дефолтная политика содержит `ssh` с `action: "check"` — при входе бывает разовая браузер-проверка. Если доступ отклоняется — нужно добавить `ssh`-правило в админке (https://login.tailscale.com/admin/acls); серверным скриптом это не воспроизводится.
- **Аутентификация интерактивная** (без auth-key): при первом `tailscale up` печатается URL для входа в браузере. Auth-key намеренно не используем — нет секрета в репо и нечему протухать.
- Проверка: `tailscale status`; `sudo tailscale debug prefs | grep -E '"RunSSH"|"CorpDNS"|"AdvertiseRoutes"'` → `RunSSH: true`, `CorpDNS: false`, `AdvertiseRoutes: null`.

**Граница доверия.** tailnet — single-user (только свои устройства, без shared nodes), это **доверенная зона**. Поэтому: SSH к `home` гарантируется членством в tailnet (не зависит от UFW `:22` key-auth); прямой доступ к Traefik по tailnet-IP `100.78.130.93` (включая `:80` без Authelia) приемлем как diagnostic/admin путь. Основной удалённый доступ к сервисам — через Cloudflare (`*.1218217.xyz`), не через tailnet.

**Грабли:**

- **НЕ анонсировать маршрут, содержащий собственный IP сервера** (`--advertise-routes=192.168.1.41/32` и т.п.). Самореферентный subnet-route: Tailscale на хосте перехватывает трафик к этому IP и **ломает локальный доступ LAN-клиентов** (TCP-коннект есть, ответы сервера не доходят — `:443` виснет на ServerHello). Доступ к серверу по tailnet берётся через его tailnet-IP напрямую — subnet-router для этого не нужен. Если когда-нибудь понадобится доступ к **другим** LAN-устройствам — анонсировать `192.168.1.0/24` (НЕ свой IP) и не принимать маршрут на домашних устройствах.
- **macOS: `tailscale down` не выгружает сетевое расширение.** Остаточный extension может глотать входящий TLS к LAN-серверу (симптом: `:443` к `192.168.1.41` виснет на ServerHello, при этом `:80` и `ping` работают). Полный сброс — Quit приложения Tailscale + перезагрузка мака.
- Терминология: «Tailscale split-DNS» (роутинг домена на nameserver в админке tailnet) ≠ «AdGuard split-horizon» (LAN-резолв `*.1218217.xyz` → `192.168.1.41`). Последний живёт в AdGuard и этим разделом не управляется.
