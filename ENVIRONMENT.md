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

## Сеть

### Доменная модель

| Уровень    | Домен              | Протокол | Механизм                       |
| ---------- | ------------------ | -------- | ------------------------------ |
| Локальный  | `*.home.local`     | HTTP     | mDNS через Avahi (системный)   |
| Локальный  | `*.1218217.xyz`    | HTTPS    | Split-horizon DNS (AdGuard Home) + Let's Encrypt (Cloudflare DNS challenge) |
| Внешний    | `*.1218217.xyz`    | HTTPS    | Cloudflare Tunnel              |

### Инфраструктурные компоненты

- **Traefik v3** — reverse proxy, auto-discovery сервисов через Docker labels
- **Authelia** — SSO аутентификация (forwardAuth middleware для Traefik)
- **Cloudflared** — Cloudflare Tunnel для внешнего доступа
- **AdGuard Home** — DNS + блокировка рекламы + split-horizon для локального HTTPS
- **Avahi** — mDNS для `*.home.local` (системный сервис, не Docker)

### Важные настройки

- Все Docker-сервисы в сети `traefik-net`
- Cloudflare: SSL mode = Flexible, Always Use HTTPS = OFF
- Homepage + Docker socket требует `user: root`
