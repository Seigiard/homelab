# Homelab Setup

Скрипты развёртывания серверного окружения на домашнем сервере Ubuntu Server.

## Быстрый старт

На чистом Ubuntu Server выполнить:

```bash
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash
```

Это установит все необходимые пакеты, настроит shell и развернёт Docker-окружение.

## Цели проекта

- Задокументировать принятые решения
- Обеспечить легкую настройку в случае переустановки системы
- Версионировать конфигурации всех сервисов

## Архитектура

### Принятые решения

- **Организация:** каждый сервис в `services/<name>/docker-compose.yml`
- **Локальная сеть:** HTTP (без SSL) через *.home.local
- **Внешний доступ:** HTTPS через Cloudflare Tunnel (*.1218217.xyz)
- **mDNS:** traefik-avahi-helper (автоматические *.home.local записи)
- **Reverse Proxy:** Traefik v3
- **Dashboard:** Homepage с Docker auto-discovery
- **Shell:** Zsh + Oh-My-Zsh

### Пользователи

- `andrew` — основной пользователь
- `yuliia` — второй пользователь
- Каждый имеет свои папки: files/, photos/, sync/

### Ключевые пути на сервере

```
/opt/homelab/           # Репозиторий (symlink ~/homelab)
/opt/homelab/appdata/   # Конфиги контейнеров (SSD)
/mnt/data/public/       # Общие файлы (HDD)
/mnt/data/users/        # Приватные данные пользователей
/mnt/data/backups/      # Бэкапы
```

## Структура репозитория

```
homelab/
├── dotfiles/             # Конфиги shell (.zshrc, .aliases)
├── scripts/
│   ├── setup.sh          # curl | bash точка входа
│   ├── bootstrap.sh      # Docker, папки, права
│   ├── lib/tui.sh        # TUI библиотека
│   └── docker/           # Управление сервисами
│       ├── _lib.sh       # Общие функции
│       ├── deploy.sh     # Деплой сервисов
│       ├── stop.sh       # Остановка сервисов
│       ├── rebuild.sh    # Пересборка (pull + restart)
│       └── status.sh     # Статус контейнеров
├── services/
│   ├── traefik/          # ✅ Reverse proxy
│   ├── homepage/         # ✅ Dashboard (home.local)
│   ├── cloudflared/      # ✅ Cloudflare Tunnel
│   ├── glances/          # ✅ System monitoring
│   ├── dozzle/           # ✅ Docker logs viewer
│   └── ...
└── .env.example
```

## Текущий прогресс

Смотри PLAN.md — там чеклист с текущим статусом.

## Команды

```bash
# Первичная настройка сервера (на чистой Ubuntu)
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash

# Деплой сервисов
./scripts/docker/deploy.sh                      # Все сервисы
./scripts/docker/deploy.sh traefik homepage     # Конкретные сервисы

# Остановка сервисов
./scripts/docker/stop.sh                        # Все сервисы
./scripts/docker/stop.sh dozzle glances         # Конкретные сервисы

# Пересборка (pull + restart)
./scripts/docker/rebuild.sh                     # Все сервисы
./scripts/docker/rebuild.sh homepage            # Конкретные сервисы

# Статус контейнеров
./scripts/docker/status.sh
```

## Полезные алиасы (после установки)

```bash
hl          # cd /opt/homelab
dc          # docker compose
dcu         # docker compose up -d
dcl         # docker compose logs -f
hldeploy    # ./scripts/docker/deploy.sh
hlstop      # ./scripts/docker/stop.sh
hlrebuild   # ./scripts/docker/rebuild.sh
hlstatus    # ./scripts/docker/status.sh
```

## Важные заметки

- Все сервисы используют общую Docker сеть `traefik-net`
- Переменные окружения берутся из корневого `.env` файла
- Traefik автоматически подхватывает сервисы через Docker labels
- Hostname сервера: `home.local` (mDNS через Avahi)
- traefik-avahi-helper создаёт mDNS записи для всех доменов из Traefik labels

## Добавление новых сервисов

```yaml
labels:
  # Traefik routing (local + external)
  - traefik.enable=true
  - traefik.http.routers.myservice.rule=Host(`myservice.home.local`) || Host(`myservice.1218217.xyz`)
  - traefik.http.routers.myservice.entrypoints=web
  # Homepage auto-discovery
  - homepage.group=Services
  - homepage.name=My Service
  - homepage.icon=myservice
  - homepage.href=http://myservice.home.local
```

## Известные особенности

- **Homepage + Docker socket:** требует `user: root` в docker-compose
- **Cloudflare настройки:** SSL mode = Flexible, Always Use HTTPS = OFF
