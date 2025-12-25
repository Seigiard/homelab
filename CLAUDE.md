# Homelab Setup

Скрипты развёртывания серверного окружения на домашнем сервере Ubuntu Server.

## Быстрый старт

```bash
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash
```

## Документация

- `README.md` — пользовательская документация (EN)
- `PLAN.md` — roadmap проекта, статус реализации
- `TESTING.md` — Docker-тестирование скриптов
- `.env.example` — шаблон переменных окружения

## Ключевые файлы для понимания проекта

### Конфигурация
- `scripts/lib/config.sh` — все переменные (пользователи, пакеты, пути)
- `.env.example` — переменные окружения для Docker

### Установка (порядок выполнения)
1. `scripts/setup.sh` — точка входа (curl | bash)
2. `scripts/setup/--init.sh` — оркестратор, запускает шаги 00-08
3. `scripts/setup/0*.sh` — модульные шаги установки
4. `scripts/bootstrap.sh` — Docker, папки, права, firewall

### Управление сервисами
- `scripts/docker/deploy.sh` — деплой
- `scripts/docker/stop.sh` — остановка
- `scripts/docker/rebuild.sh` — пересборка (pull + restart)
- `scripts/docker/status.sh` — статус

### Сервисы
Каждый сервис в `services/<name>/docker-compose.yml`. Смотри labels для понимания роутинга.

## Архитектура

- **Локальная сеть:** `*.home.local` (HTTP, mDNS через Avahi)
- **Внешний доступ:** `*.1218217.xyz` (HTTPS через Cloudflare Tunnel)
- **Reverse Proxy:** Traefik v3 с auto-discovery через Docker labels
- **Dashboard:** Homepage с Docker auto-discovery

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

### Добавить пакет в установку
Обновить массивы в `scripts/lib/config.sh`:
- `APT_PACKAGES` — apt пакеты
- `SNAP_PACKAGES` — snap пакеты
- `CARGO_PACKAGES` — cargo пакеты

### Добавить dotfile
1. Создать файл в `dotfiles/`
2. Для `.config/*` — создать `dotfiles/.config/<app>/`
3. Скрипт `05-apply-dotfiles.sh` автоматически симлинкует

### Перезапустить шаг установки
```bash
./scripts/setup/07-setup-ssh-key.sh  # любой шаг можно запустить отдельно
```

## Важные заметки

- Все сервисы используют Docker сеть `traefik-net`
- Traefik подхватывает сервисы через Docker labels автоматически
- Homepage + Docker socket требует `user: root`
- Cloudflare: SSL mode = Flexible, Always Use HTTPS = OFF
