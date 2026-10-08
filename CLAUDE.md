# Homelab

Автоматизированное развёртывание и управление домашним сервером на Ubuntu Server: Docker-сервисы за Traefik, Cloudflare Tunnel для внешнего доступа, mDNS для локальной сети.

**Claude Code работает на локальной машине (macOS), сервер — удалённый Ubuntu.** Docker-контейнеры, логи, `docker ps` — всё на сервере; `docker`-команды запускаются там, а вывод `docker ps`/`docker logs` от пользователя — тоже с сервера.

## Документация

- `README.md` — установка, настройка, использование (EN)
- `ENVIRONMENT.md` — серверное окружение: железо, хранилище, сеть, бэкапы, известные проблемы
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
- **Reverse Proxy:** Traefik v3, auto-discovery через Docker labels, общая сеть `traefik-net`
- **Dashboard:** Homepage с Docker auto-discovery
- **Хранилище:** SSD для appdata, HDD (RAID1) для данных

## Ключевые пути на сервере

```
/opt/homelab/           # Репозиторий (symlink ~/homelab)
/opt/homelab/appdata/   # Конфиги контейнеров (SSD)
/mnt/data/public/       # Общие файлы (HDD)
/mnt/data/users/        # Приватные данные пользователей
/mnt/data/backups/      # Бэкапы
```

<important if="you need to deploy, stop, rebuild, remove, or check the status of services, or rerun an install step">

```bash
./scripts/docker/deploy.sh svc1 svc2    # деплой (без аргументов — все)
./scripts/docker/stop.sh svc1 svc2      # остановка
./scripts/docker/rebuild.sh svc1        # pull + restart
./scripts/docker/remove.sh svc1         # остановка + удаление контейнеров
./scripts/docker/status.sh              # статус всех
./scripts/setup/07-setup-ssh-key.sh     # любой шаг установки запускается отдельно
```
</important>

<important if="you are adding a new service or editing a service's docker-compose.yml">

1. Создать `services/myservice/docker-compose.yml`, сеть `traefik-net`.
2. Добавить Traefik + Homepage labels — пример в любом существующем сервисе.
3. `./scripts/docker/deploy.sh myservice`

- Homepage с Docker socket требует `user: root`.
- **Образ объявляет `VOLUME` → биндить корень тома.** Иначе docker создаёт анонимный том и при каждом пересоздании контейнера бросает предыдущий. Пример починки: `opml-generator` (`/audiobooks` → `appdata/opml-generator/shelves`). Исключение — `samba` (`dperson/samba` объявляет `/etc`, `/var/lib/samba`, `/var/cache/samba`, `/run/samba`): эти пути биндить нельзя, состояние пересобирается из флагов `-u` при старте. Чистка: `docker volume prune -f`.
</important>

<important if="you are choosing or changing the auth middleware of a service">

- По умолчанию снаружи — `authelia@docker` (cookie-редирект SSO).
- **Feed-клиенты** (подкасты, OPDS) редирект не проходят → общий middleware `basic-auth@docker` (определён на контейнере traefik). Используют `opds`, `opml`, `ytpod`. Подписка: `https://user:pass@host/...`.
- **Jellyfin и Navidrome снаружи без middleware** — телевизоры и мобильные плееры не проходят редирект; защищает собственный логин сервиса.
</important>

<important if="you are editing a value in .env that contains `$`, such as BASIC_AUTH_USERS">

Значение — в одинарных кавычках с одинарным `$`: `BASIC_AUTH_USERS='feeds:$2y$05$...'`. `deploy.sh` делает `source .env` в bash, и без кавычек `$$` раскроется в PID. Генерация: `htpasswd -nbB feeds 'pass'`, результат обернуть в `'...'`.
</important>

<important if="you are working on NUT/UPS, PeaNUT, or Tailscale">

NUT и Tailscale работают на хосте, вне Docker.

- **NUT:** хост даёт надёжный shutdown. Конфиг `/etc/nut/`, setup `09-setup-nut.sh`. PeaNUT (web UI, Docker) ходит к хосту через `host.docker.internal:3493`.
- **Tailscale:** setup `10-setup-tailscale.sh`, переменные `TS_*` в `config.sh`, аутентификация интерактивная. Доступ: `tailscale ssh seigiard@home`. **`accept-dns=false` обязательно** — с `true` Tailscale переписывает `/etc/resolv.conf` на MagicDNS и ломает split-horizon AdGuard.
</important>

<important if="you are touching Cloudflare, the tunnel, TLS, or HTTPS redirects">

Cloudflare: SSL mode = Flexible, Always Use HTTPS = ON.
</important>

<important if="you are debugging ytpod, or YouTube playback returns 403 or 520">

**Временный обход клиента yt-dlp** (с 2026-08-18). Дефолтный клиент `android_vr` получает 403 на все stream URL (yt-dlp/yt-dlp#17456), `android` — SABR-only без прямых URL. В compose форсится `YOUTUBE_YT_DLP_GET_URL_EXTRA_ARGS=["--extractor-args","youtube:player_client=visionos,web_embedded"]`.

- Убрать, когда стабильный yt-dlp с фиксом `dae52d8` попадёт в образ `madiele/vod2pod-rss:beta`.
- Симптом возврата: 520 через Cloudflare, 403 на `googlevideo.com` в `docker logs ytpod`.
- vod2pod кэширует stream URL в Redis → после смены клиента `docker exec ytpod-redis redis-cli FLUSHALL`.
- Подбор живого клиента: `docker exec ytpod yt-dlp -q -f bestaudio --get-url --extractor-args "youtube:player_client=<клиент>" <video-url>`, затем curl полученного URL.
</important>

<important if="you are working on Backrest/restic backups, retention, excludes, or the Dropbox quota">

- **Dropbox-репо ~10 ГБ, держать запас.** Всё крупное и восстановимое — в excludes (веса моделей, `home-assistant_v2.db*`, бинарники). Полный репо не лечится prune: restic не пишет даже lock (`path/insufficient_space`) → только `rclone purge dropbox:backups` + `restic init` и новый GUID в конфиге.
- Конфиг планов — `appdata/backrest/config/config.json`, в git не лежит. Правка: `docker cp` + рестарт, старый сохранить как `config.json.bak.*`.
- Проверка: `rclone about dropbox:` и `restic snapshots --no-lock --compact` — колонка размеров ровная, выброс = что-то крупное проскочило мимо excludes.
- Инцидент 2026-09-23, текущие excludes и retention — `ENVIRONMENT.md` → «Бэкапы (Backrest/restic)».
</important>

<important if="you are checking disk health, SMART, NVMe, or firmware updates">

- **NVMe Kingston DC2000B:** проверять через `nvme smart-log /dev/nvme0n1`; `smartctl` даёт ложные ошибки. Sensor 2 (~82°C) — фейковый датчик прошивки.
- **`udisks2` замаскирован намеренно** (`bootstrap.sh`). Поэтому `fwupdmgr` пишет `UEFI ESP partition not detected` — это ожидаемо, Secure Boot выключен, чинить нечего (`EspLocation` в `fwupd.conf` проверен, не помогает).
- Подробности — `ENVIRONMENT.md`.
</important>

<important if="you are working with /mnt/data, the RAID array, DATA_PATH, or deleting old data directories">

- **`/mnt/data` = RAID1 `/dev/md0`** (2× 6 ТБ, ext4, UUID в fstab). Норма: `cat /proc/mdstat` → `[2/2] [UU]`.
- **`/mnt/data-tmp.DELETE-20260818` хранить, пока нет холодной копии на диске `sdd`** — до неё это единственный второй экземпляр данных. Зеркало ≠ бэкап: `/mnt/data/users` не входит ни в один restic-план.
- При незамонтированном массиве деплой сервисов с данными прерывается (`check_data_mount` в `scripts/docker/_lib.sh`), каталог под точкой монтирования защищён `chattr +i`.
- Подробности — `ENVIRONMENT.md` → «RAID1».
</important>

<important if="you are restoring appdata, or working on stash, transmission, transmission-omg, jellyfin, or navidrome">

- **Источник истины — живой appdata**: он пережил смерть диска и свежее архивов в `backups/`. Архивы оставить нераспакованными.
- Медиафайлы после переезда на зеркало не вернулись: stash показывает каталог как missing, transmission-omg качает раздачи заново.
- **VAAPI на AMD Vega 8:** пробрасывается весь `/dev/dri`, доступ даёт `group_add` с GID группы `render` из `.env` → `RENDER_GROUP_ID` (`getent group render`). Неверный GID = молчаливый софтверный транскодинг без ошибок в логах.
</important>

<important if="you are adding an install package or a dotfile">

- Пакеты: массивы `APT_PACKAGES`, `CARGO_PACKAGES` в `scripts/lib/config.sh`.
- Dotfile: файл в `dotfiles/` (для `.config/*` — `dotfiles/.config/<app>/`), `05-apply-dotfiles.sh` симлинкует автоматически.
</important>

<important if="you have finished a change to services, setup, hardware, or the roadmap">

Обновить `PLAN.md`, `README.md`, `ENVIRONMENT.md`, `CLAUDE.md` — те, которые затрагивает изменение.
</important>

<important if="you are creating, reading, or triaging issues, writing specs or tickets, or editing GLOSSARY.md or ADRs">

## Agent skills

### Issue tracker

Issues live in GitHub Issues of `Seigiard/homelab`, managed through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

</important>
