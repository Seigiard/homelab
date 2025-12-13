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

pi-hole/adguard
cloudflared to 1218217.xyz
syncthing
gopeed or transmission
immich
dozzle
glances

[GitHub - hardillb/traefik-avahi-helper: A container to create mDNS CNAMEs for Traefik exposed container](https://github.com/hardillb/traefik-avahi-helper)

[Home - Homepage](https://gethomepage.dev/)
