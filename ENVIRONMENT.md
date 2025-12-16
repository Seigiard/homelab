Для организации домашнего сервера используется стандарт **"Data vs Appdata"**. Это разделение данных на две категории:

1. **Appdata (Конфигурация):** Базы данных, настройки, логи, метаданные. Хранится на быстром диске (SSD/NVMe).

2. **Data (Контент):** Фильмы, фото, документы, загрузки. (HDD)

Тестовая настройка на одном диске

```
// Папка для настроек контейнеров (SSD)
// Sync with github repo
appdata/
  qbittorrent/
  jellyfin/
  homeassistant/
  pihole/
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

| Сервис | Статус | Описание |
|--------|--------|----------|
| traefik-avahi-helper | ✅ | mDNS CNAME для *.home.local |
| Homepage | ✅ | Dashboard с Docker auto-discovery |
| Cloudflared | ✅ | Туннель для внешнего доступа |
| Glances | ✅ | System monitoring |
| Dozzle | ✅ | Docker logs viewer (local only) |
| Samba | ✅ | SMB file shares (public, andrew, yuliia) |
| FileBrowser | ✅ | Web file manager (files.home.local) |
| AdGuard | ⏳ | DNS + блокировка рекламы |
| Syncthing | ⏳ | Синхронизация файлов |
| Immich | ⏳ | Фото-библиотека |
| Authelia | ⏳ | SSO аутентификация для внешнего доступа |
