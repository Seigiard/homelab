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

- [x] `services/traefik/` — reverse proxy (HTTP на порту 80)
- [x] traefik-avahi-helper — автоматические mDNS записи (*.home.local)
- [x] `services/cloudflared/` — внешний доступ (*.1218217.xyz)

### Фаза 3: AdGuard Home — отложено

> mDNS через traefik-avahi-helper решает задачу *.home.local.
> AdGuard понадобится для блокировки рекламы.

- [ ] `services/adguard/`

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

### Фаза 8: Аутентификация для внешнего доступа — в планах

> Для безопасного внешнего доступа к чувствительным сервисам.

- [ ] Authelia
- [ ] Включить внешний доступ к Dozzle/Glances с аутентификацией

---

## Отложено

- [ ] Торренты (transmission/qbittorrent)
- [ ] Jellyfin (медиа-сервер)
- [ ] Paperless (документы)
- [ ] Home Assistant
