# Homelab

Автоматизированное развёртывание и управление домашним сервером на Ubuntu Server. Docker-сервисы с Traefik reverse proxy, Cloudflare Tunnel для внешнего доступа, mDNS для локальной сети.

## Документация

- `README.md` — установка, настройка, использование (EN)
- `ENVIRONMENT.md` — серверное окружение: железо, хранилище, сеть, известные проблемы
- `PLAN.md` — roadmap: планируемые сервисы и идеи

## Структура проекта

```
scripts/
  setup.sh              # Точка входа (curl | bash)
  bootstrap.sh          # Docker, папки, права, firewall, smartd
  healthcheck.sh        # Проверка состояния после установки
  setup/                # Модульные шаги установки (00-10)
  docker/               # Управление сервисами (deploy/stop/rebuild/remove/status)
  lib/config.sh         # Все переменные (пользователи, пакеты, пути)
  lib/tui.sh            # TUI-библиотека
services/               # Docker-сервисы: ls services/ = полный список
dotfiles/               # Симлинкуются в ~ при установке
```

## Архитектура

- **Локальная сеть:** `*.home.local` (HTTP, mDNS через Avahi)
- **Внешний доступ:** `*.1218217.xyz` (HTTPS через Cloudflare Tunnel + Let's Encrypt)
- **Reverse Proxy:** Traefik v3, auto-discovery через Docker labels
- **Dashboard:** Homepage с Docker auto-discovery
- **Хранилище:** SSD для appdata (конфиги контейнеров), HDD для данных. Подробности в `ENVIRONMENT.md`

## Ключевые пути на сервере

```
/opt/homelab/           # Репозиторий (symlink ~/homelab)
/opt/homelab/appdata/   # Конфиги контейнеров (SSD)
/mnt/data/public/       # Общие файлы (HDD)
/mnt/data/users/        # Приватные данные пользователей
/mnt/data/backups/      # Бэкапы
```

## AI Quick Reference

### Добавить новый сервис
1. Создать `services/myservice/docker-compose.yml`
2. Добавить Traefik + Homepage labels (см. существующие сервисы как пример)
3. `./scripts/docker/deploy.sh myservice`

### Управление сервисами
```bash
./scripts/docker/deploy.sh svc1 svc2    # деплой (без аргументов — все)
./scripts/docker/stop.sh svc1 svc2      # остановка
./scripts/docker/rebuild.sh svc1        # pull + restart
./scripts/docker/remove.sh svc1         # остановка + удаление контейнеров
./scripts/docker/status.sh              # статус всех
```

### Добавить пакет в установку
Обновить массивы в `scripts/lib/config.sh`: `APT_PACKAGES`, `CARGO_PACKAGES`

### Добавить dotfile
1. Создать файл в `dotfiles/` (для `.config/*` — в `dotfiles/.config/<app>/`)
2. Скрипт `05-apply-dotfiles.sh` автоматически симлинкует

### Перезапустить шаг установки
```bash
./scripts/setup/07-setup-ssh-key.sh  # любой шаг можно запустить отдельно
```

## Важные заметки

- **Claude Code работает на локальной машине (macOS), НЕ на сервере.** Docker-контейнеры, логи, `docker ps` — всё на удалённом сервере Ubuntu. НЕ запускай `docker` команды локально. Когда пользователь показывает вывод `docker ps`/`docker logs` — это с сервера
- Все сервисы используют Docker сеть `traefik-net`
- Traefik подхватывает сервисы через Docker labels автоматически
- Homepage + Docker socket требует `user: root`
- Cloudflare: SSL mode = Flexible, Always Use HTTPS = ON
- **NUT (UPS)** работает на хосте, НЕ в Docker — для надёжного shutdown. Конфиг: `/etc/nut/`, setup: `09-setup-nut.sh`. PeaNUT (web UI) в Docker подключается к хосту через `host.docker.internal:3493`
- **Tailscale (mesh VPN)** работает на хосте, НЕ в Docker — как NUT. Setup: `10-setup-tailscale.sh`, переменные в `config.sh` (`TS_*`). Удалённый доступ: `tailscale ssh seigiard@home`. **`accept-dns=false` обязательно** — иначе Tailscale переписывает `/etc/resolv.conf` на свой MagicDNS и ломает split-horizon AdGuard. Аутентификация интерактивная (без auth-key)
- **Auth для feed-сервисов**: подкаст/OPDS-клиенты не проходят cookie-редирект Authelia. Для них общий middleware `basic-auth@docker` (определён на контейнере traefik, креды в `.env` → `BASIC_AUTH_USERS`, htpasswd) вместо `authelia@docker`. Используют `opds`, `opml`, `ytpod`. Подписка: `https://user:pass@host/...`. **Значение в `.env` в одинарных кавычках с одинарным `$`**: `BASIC_AUTH_USERS='feeds:$2y$05$...'`. deploy.sh делает `source .env` (bash) — без кавычек `$$` раскроется в PID и хэш испортится. Генерация: `htpasswd -nbB feeds 'pass'`, обернуть в `'...'`
- **ytpod: временный обход клиента yt-dlp** (2026-08-18). YouTube сломал дефолтный клиент `android_vr` (403 на все stream URL, yt-dlp/yt-dlp#17456), клиент `android` — SABR-only без прямых URL. В compose форсим `YOUTUBE_YT_DLP_GET_URL_EXTRA_ARGS=["--extractor-args","youtube:player_client=visionos,web_embedded"]`. Убрать, когда стабильный yt-dlp с фиксом `dae52d8` попадёт в образ `madiele/vod2pod-rss:beta`. Симптом возврата проблемы: 520 через Cloudflare, 403 на `googlevideo.com` в `docker logs ytpod`. Важно: vod2pod кэширует stream URL в Redis — после смены клиента нужен `docker exec ytpod-redis redis-cli FLUSHALL`. Быстрый подбор живого клиента: `docker exec ytpod yt-dlp -q -f bestaudio --get-url --extractor-args "youtube:player_client=<клиент>" <video-url>` + curl полученного URL
- **NVMe Kingston DC2000B**: не использовать `smartctl` — генерирует ложные ошибки. `nvme smart-log /dev/nvme0n1` для проверки. Sensor 2 (~82°C) — фейковый датчик прошивки. Подробности в `ENVIRONMENT.md`
- **`udisks2` замаскирован намеренно** (`bootstrap.sh`, из-за ложных NVMe-ошибок). Следствие: `fwupdmgr` всегда пишет `UEFI ESP partition not detected` и не ставит обновления Secure Boot. Это не баг, чинить не нужно — Secure Boot выключен, обновлений прошивки железа нет. `EspLocation` в `fwupd.conf` не помогает (проверено). Подробности в `ENVIRONMENT.md`
- **`/mnt/data` = RAID1-зеркало `/dev/md0`** (2× Seagate 6 ТБ, ext4, по UUID в fstab). Состояние: `cat /proc/mdstat` → `[2/2] [UU]`. Зеркало ≠ бэкап: холодная копия — на отдельный 8 ТБ диск `sdd`. **Живые данные сервисов пока лежат в `/mnt/data-tmp`** (`.env` → `DATA_PATH`), зеркало ещё пустое — перенос отдельной задачей. Подробности в `ENVIRONMENT.md`
- После завершённой задачи обновляй PLAN.md, README.md, ENVIRONMENT.md, CLAUDE.md если изменения затрагивают соответствующий файл
