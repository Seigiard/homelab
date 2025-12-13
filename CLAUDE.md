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
- **DNS:** AdGuard Home (порт 53 + web UI на 3000)
- **Reverse Proxy:** Traefik v3 (роутинг по *.home.local)
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
