# План развёртывания Homelab

## Обзор проекта

Создание инфраструктуры домашнего сервера на Ubuntu Server с Docker.

**Принятые решения:**
- Организация: каждый сервис в `services/<name>/docker-compose.yml`
- Скрипты: все в `scripts/`
- DNS: AdGuard Home
- Reverse Proxy: Traefik v3
- Shell: Zsh + Oh-My-Zsh
- Точка входа: `curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash`

---

## Структура репозитория

```
homelab/
├── CLAUDE.md
├── ENVIRONMENT.md
├── PLAN.md
├── .env.example
├── .gitignore
├── dotfiles/
│   ├── .zshrc
│   ├── .aliases
│   └── .gitconfig
├── scripts/
│   ├── lib/
│   │   └── tui.sh                # Общие TUI функции
│   ├── setup.sh                  # curl | bash (минимальный: git + clone)
│   ├── setup/
│   │   ├── --init.sh             # Оркестратор setup-шагов
│   │   ├── 00-update-system.sh   # apt update/upgrade
│   │   ├── 01-install-packages.sh
│   │   ├── 02-setup-zsh.sh
│   │   ├── 03-setup-git.sh
│   │   ├── 04-setup-avahi.sh
│   │   ├── 05-apply-dotfiles.sh
│   │   ├── 06-run-bootstrap.sh
│   │   ├── 07-setup-ssh-key.sh   # Интерактивный, в конце
│   │   └── 08-show-summary.sh
│   ├── bootstrap.sh              # Docker, папки, права
│   └── deploy.sh                 # Запуск всех сервисов
├── services/
│   ├── traefik/                  # ✅ Reverse proxy
│   ├── homepage/                 # ✅ Dashboard (home.local)
│   ├── adguard/                  # DNS
│   ├── samba/                    # Файлы
│   ├── immich/                   # Фото
│   ├── syncthing/                # Синхронизация
│   └── monitoring/               # Dozzle + Glances
└── docs/
    └── manual-steps.md
```

---

## Пошаговый план реализации

### Фаза 0: Настройка сервера ✅

- [x] **Шаг 0.1:** Создать `scripts/setup.sh` — главный скрипт (curl | bash)
- [x] **Шаг 0.2:** Создать `dotfiles/.zshrc` — конфиг Zsh
- [x] **Шаг 0.3:** Создать `dotfiles/.aliases` — алиасы команд
- [x] **Шаг 0.4:** Создать `dotfiles/.gitconfig` — настройки Git

### Фаза 1: Подготовка репозитория ✅

- [x] **Шаг 1.1:** Создать структуру папок (`scripts/`, `services/`, `docs/`)
- [x] **Шаг 1.2:** Создать `.env.example` (APPDATA_PATH, DATA_PATH, LOCAL_DOMAIN, TZ, PUID, PGID)
- [x] **Шаг 1.3:** Создать `scripts/bootstrap.sh` (Docker, папки, права, пользователи)

### Фаза 1.5: TUI библиотека ✅

- [x] **Шаг 1.5.1:** Создать `scripts/lib/tui.sh` — общие TUI функции
- [x] **Шаг 1.5.2:** Обновить `scripts/bootstrap.sh` — source локального tui.sh

### Фаза 1.6: Модульный setup ✅

- [x] **Шаг 1.6.1:** Создать `scripts/setup/--init.sh` — оркестратор
- [x] **Шаг 1.6.2:** Создать step-скрипты `00-08-*.sh`
- [x] **Шаг 1.6.3:** Переписать `scripts/setup.sh` — минимальный (git + clone)

**Поток выполнения:**
```
curl | bash (setup.sh)
    ├── apt install git
    ├── git clone https://... /opt/homelab
    └── exec scripts/setup/--init.sh
              ├── source lib/tui.sh
              └── source 00-*.sh, 01-*.sh, ...
```

### Фаза 2: Traefik + Cloudflare Tunnel ✅

- [x] **Шаг 2.1:** `services/traefik/docker-compose.yml` (HTTP на порту 80)
- [x] **Шаг 2.2:** `services/traefik/config/traefik.yml` (роутинг *.home.local)
- [x] **Шаг 2.3:** traefik-avahi-helper для автоматических mDNS записей
- [x] **Шаг 2.4:** `services/cloudflared/docker-compose.yml` — внешний доступ через 1218217.xyz

### Фаза 3: AdGuard Home (DNS) — отложено

> mDNS через traefik-avahi-helper решает задачу *.home.local без AdGuard.
> AdGuard понадобится только для блокировки рекламы.

- [ ] **Шаг 3.1:** `services/adguard/docker-compose.yml` (порты 53, 3000)

### Фаза 4: Samba (Файлы)

- [ ] **Шаг 4.1:** `services/samba/docker-compose.yml` (public + users)
- [ ] **Шаг 4.2:** Конфигурация smb.conf (andrew, yuliia)

### Фаза 5: Immich (Фото)

- [ ] **Шаг 5.1:** `services/immich/docker-compose.yml` (PostgreSQL + Redis + ML)

### Фаза 6: Вспомогательные сервисы

- [x] **Шаг 6.1:** `services/homepage/docker-compose.yml` ✅
- [x] **Шаг 6.2:** Homepage Docker auto-discovery (homepage.* labels) ✅
- [ ] **Шаг 6.3:** `services/syncthing/docker-compose.yml`
- [x] **Шаг 6.4:** `services/glances/docker-compose.yml` — системный мониторинг ✅
- [x] **Шаг 6.5:** `services/dozzle/docker-compose.yml` — просмотр логов Docker ✅

### Фаза 7: Финализация

- [x] **Шаг 7.1:** `scripts/deploy.sh` ✅
- [ ] **Шаг 7.2:** Обновить README.md

---

### Фаза 8: Аутентификация для внешнего доступа

> Сейчас Dozzle доступен только локально (home.local). Для безопасного внешнего доступа нужна аутентификация.

- [ ] **Шаг 8.1:** Выбрать решение: Authelia
- [ ] **Шаг 8.2:** Настроить аутентификацию с поддержкой пользователей (andrew, yuliia)
- [ ] **Шаг 8.3:** Включить внешний доступ к Dozzle через 1218217.xyz с аутентификацией
- [ ] **Шаг 8.4:** Применить аутентификацию к другим чувствительным сервисам

---

### Фаза 9: Медиа-сервисы

- [x] **Шаг 9.1:** `services/komga/docker-compose.yml` — комиксы/манга ✅
- [x] **Шаг 9.2:** `services/opds-generator/docker-compose.yml` — OPDS каталог книг ✅

---

## Отложено на потом

- [ ] Торренты (transmission/qbittorrent)
- [ ] Jellyfin (медиа-сервер)
- [ ] Paperless (документы)
- [ ] Home Assistant
