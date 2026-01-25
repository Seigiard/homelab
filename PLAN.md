# План развёртывания Homelab

Roadmap проекта и статус реализации.

> Описание проекта и структуру см. в `README.md` и `CLAUDE.md`

---

## Статус по фазам

### Фаза 0: Настройка сервера ✅

- [x] `scripts/setup.sh` — главный скрипт (curl | bash)
- [x] `dotfiles/.zshrc`, `.aliases`, `.gitconfig`

### Фаза 1: Подготовка репозитория ✅

- [x] Структура папок (`scripts/`, `services/`)
- [x] `.env.example`
- [x] `scripts/bootstrap.sh` (Docker, папки, права)
- [x] `scripts/lib/tui.sh` — TUI библиотека
- [x] Модульный setup (`scripts/setup/00-08-*.sh`)

### Фаза 2: Traefik + Cloudflare Tunnel ✅

- [x] `services/traefik/` — reverse proxy (HTTP:80 + HTTPS:443)
- [x] traefik-avahi-helper — автоматические mDNS записи (\*.home.local)
- [x] `services/cloudflared/` — внешний доступ (\*.1218217.xyz)
- [x] HTTPS для локального доступа (Let's Encrypt via Cloudflare DNS challenge)

### Фаза 3: AdGuard Home ✅

> mDNS через traefik-avahi-helper решает задачу \*.home.local.
> AdGuard понадобится для блокировки рекламы.

- [x] `services/adguard/`

### Фаза 4: Samba ✅

- [x] `services/samba/` — SMB shares (andrew, yuliia, public)

### Фаза 5: Immich (Фото) — в планах

- [ ] `services/immich/` (PostgreSQL + Redis + ML)

### Фаза 6: Вспомогательные сервисы

- [x] `services/homepage/` — dashboard с Docker auto-discovery
- [x] `services/glances/` — системный мониторинг
- [x] `services/dozzle/` — просмотр логов Docker
- [x] `services/filebrowser/` — web файловый менеджер
- [x] `services/opds-generator/` — OPDS каталог книг
- [ ] `services/syncthing/` — синхронизация файлов

### Фаза 7: Финализация

- [x] `scripts/docker/deploy.sh`
- [x] README.md

### Фаза 8: Аутентификация для внешнего доступа ✅

> Для безопасного внешнего доступа к чувствительным сервисам.

- [x] `services/authelia/` — SSO аутентификация (forwardAuth)
- [x] Все сервисы защищены через Authelia middleware
- [x] Три пользователя: admin (полный доступ), andrew, yuliia (ограниченный)
- [x] Матрица доступа: admin → всё, andrew → торренты + личные файлы, yuliia → личные файлы

### Фаза 9: Медиа-сервисы

- [x] `services/jellyfin/` — медиа-стриминг
- [x] `services/qbittorrent/` — торрент-клиент

---

## Отложено

- [ ] Paperless (документы)
- [ ] Home Assistant
- [ ] Prowlarr / Sonarr / Radarr (автоматизация медиа)
