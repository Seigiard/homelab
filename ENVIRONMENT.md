Для организации домашнего сервера используется стандарт **"Data vs Appdata"**. Это разделение данных на две категории:

1. **Appdata (Конфигурация):** Базы данных, настройки, логи, метаданные. Хранится на быстром диске (SSD/NVMe).

2. **Data (Контент):** Фильмы, фото, документы, загрузки. (HDD)

Тестовая настройка на одном диске

```
// Папка для настроек контейнеров (SSD)
// Sync with github repo
appdata/
  traefik/
  authelia/
  adguard/
  homepage/
  jellyfin/
  transmission/
  transmission-omg/
  backrest/
  ...
```

```
public/                   <-- Общий доступ (Read/Write для торрентов, Samba)
public/movies/
public/tv/
public/music/
public/.torrents-temp/    <-- Скрытая папка для недокачанных файлов

users/                    <-- Приватные данные (Auth Samba)
users/andrew/
users/andrew/files/       // Auth Samba
users/andrew/photos/      <-- Immich External Library
users/andrew/sync/        <-- Syncthing / Dropbox

users/yuliia/
users/yuliia/files/
users/yuliia/photos/

backups/                  <-- Бэкапы контейнеров и баз данных
```

|                        | Samba              | Domain               | Service     | Auth  |
| ---------------------- | ------------------ | -------------------- | ----------- | ----- |
| public/                | files.home.local   | files.home.local     | filemanager | guest |
| public/movies/         |                    |                      |             |       |
| public/tv/             |                    |                      |             |       |
| public/music/          |                    |                      |             |       |
| public/.torrents-temp/ |                    |                      |             |       |
|                        |                    |                      |             |       |
| data/                  |                    |                      |             |       |
| data/paperless         |                    | paperless.home.local | paperless   | auth  |
|                        |                    |                      |             |       |
| users/                 |                    |                      |             |       |
| users/andrew/          | a.files.home.local | a.files.home.local   | filemanager | auth  |
| users/andrew/files/    |                    |                      |             |       |
| users/andrew/photos/   |                    | a.photos.home.local  | immich      | auth  |
| users/andrew/sync/     |                    |                      |             |       |
|                        |                    |                      |             |       |
| users/yuliia/          | y.files.home.local | y.files.home.local   |             | auth  |
| users/yuliia/files/    |                    |                      |             |       |
| users/yuliia/photos/   |                    | y.photos.home.local  | immich      | auth  |

## Сервисы

### Инфраструктура

| Сервис | Статус | Описание |
|--------|--------|----------|
| Traefik | ✅ | Reverse proxy с Docker auto-discovery |
| Authelia | ✅ | SSO аутентификация (forwardAuth middleware) |
| Cloudflared | ✅ | Cloudflare Tunnel для внешнего доступа |
| AdGuard Home | ✅ | DNS + блокировка рекламы + split-horizon DNS |
| Avahi | ✅ | mDNS для *.home.local (системный сервис, не Docker) |

### Мониторинг и управление

| Сервис | Статус | Описание |
|--------|--------|----------|
| Homepage | ✅ | Dashboard с Docker auto-discovery |
| Glances | ✅ | System monitoring |
| Dozzle | ✅ | Docker logs viewer |
| Backrest | ✅ | Backup management (restic + rclone) |

### Файлы и медиа

| Сервис | Статус | Описание |
|--------|--------|----------|
| Samba | ✅ | SMB file shares (public, andrew, yuliia) |
| FileBrowser | ✅ | Web file manager (3 инстанса: public, andrew, yuliia) |
| OPDS Generator | ✅ | E-book OPDS catalog |
| Jellyfin | ✅ | Media streaming server |
| Transmission | ✅ | Public torrent client (public/downloads) |
| Transmission OMG | ✅ | Private torrent client (users/andrew/OMG) |

### Утилиты

| Сервис | Статус | Описание |
|--------|--------|----------|
| PriceBuddy | ✅ | Price tracker (MySQL + scraper) |

### Планируемые

| Сервис | Статус | Описание |
|--------|--------|----------|
| Syncthing | ⏳ | Синхронизация файлов |
| Immich | ⏳ | Фото-библиотека |
| Paperless | ⏳ | Document management |
