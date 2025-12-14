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
- **mDNS:** traefik-avahi-helper (автоматические *.home.local записи)
- **Reverse Proxy:** Traefik v3 (роутинг по *.home.local)
- **Dashboard:** Homepage с Docker auto-discovery
- **Shell:** Zsh + Oh-My-Zsh
- **Хранение:** Data vs Appdata паттерн (см. ENVIRONMENT.md)

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
│   └── deploy.sh         # Запуск всех сервисов
├── services/
│   ├── traefik/          # ✅ Reverse proxy
│   ├── homepage/         # ✅ Dashboard (home.local)
│   ├── adguard/          # DNS (планируется)
│   └── ...
└── .env.example
```

## Текущий прогресс

Смотри PLAN.md — там чеклист с текущим статусом.

## Команды

```bash
# Первичная настройка сервера (на чистой Ubuntu)
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash

# После setup.sh — развернуть все сервисы
./scripts/deploy.sh

# Управление сервисами
./scripts/deploy.sh stop      # Остановить
./scripts/deploy.sh restart   # Перезапустить
./scripts/deploy.sh rebuild   # Пересобрать (pull + restart)
./scripts/deploy.sh status    # Статус
```

## Полезные алиасы (после установки)

```bash
hl          # cd /opt/homelab
dc          # docker compose
dcu         # docker compose up -d
dcl         # docker compose logs -f
hldeploy    # запуск deploy.sh
```

## Важные заметки

- Все сервисы используют общую Docker сеть `traefik-net`
- Переменные окружения берутся из корневого `.env` файла
- Traefik автоматически подхватывает сервисы через Docker labels
- Hostname сервера: `home.local` (mDNS через Avahi)
- traefik-avahi-helper создаёт mDNS записи для всех доменов из Traefik labels

## Добавление новых сервисов

Для автоматического появления на Homepage добавь labels:

```yaml
labels:
  # Traefik routing
  - traefik.enable=true
  - traefik.http.routers.myservice.rule=Host(`myservice.home.local`)
  - traefik.http.routers.myservice.entrypoints=websecure
  - traefik.http.routers.myservice.tls=true
  # Homepage auto-discovery
  - homepage.group=Services
  - homepage.name=My Service
  - homepage.icon=myservice
  - homepage.href=https://myservice.home.local
  - homepage.description=Description here
```

## Известные особенности

- **Homepage + Docker socket:** требует `user: root` в docker-compose, т.к. внутренний пользователь `node` не имеет доступа к socket
- **Docker GID:** на сервере группа docker имеет GID=988
