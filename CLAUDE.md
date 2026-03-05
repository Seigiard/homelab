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
  setup/                # Модульные шаги установки (00-09)
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
- Cloudflare: SSL mode = Flexible, Always Use HTTPS = OFF
- **NUT (UPS)** работает на хосте, НЕ в Docker — для надёжного shutdown. Конфиг: `/etc/nut/`, setup: `09-setup-nut.sh`. PeaNUT (web UI) в Docker подключается к хосту через `host.docker.internal:3493`
- **NVMe Kingston DC2000B**: не использовать `smartctl` — генерирует ложные ошибки. `nvme smart-log /dev/nvme0n1` для проверки. Sensor 2 (~82°C) — фейковый датчик прошивки. Подробности в `ENVIRONMENT.md`
- После завершённой задачи обновляй PLAN.md, README.md, ENVIRONMENT.md, CLAUDE.md если изменения затрагивают соответствующий файл
