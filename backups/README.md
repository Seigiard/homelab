# Backups — восстановление после смерти HDD

Бэкапы appdata (конфиги на SSD) для сервисов, отключённых после выхода из строя
data-HDD (Seagate ST6000VN006 6TB, `/mnt/data`). Здесь только **ценные настройки**;
сами медиафайлы были на мёртвом диске и в бэкап не входят.

Дата: 2026-06-20

## Что в архивах

| Файл | Сервис | Что внутри | Размер |
|------|--------|-----------|--------|
| `stash-config.tar.gz` | stash | БД `stash-go.sqlite` (сцены, теги, метаданные), `config.yml`, `custom.css`, `icon.png`, `plugins/`, `scrapers/` | ~2 MB |
| `transmission-omg.tar.gz` | transmission-omg | `settings.json`, список торрентов (`torrents/*.torrent`), `resume/`, `stats.json`, `dht.dat` | ~15 MB |

**Не бэкапилось** (пересоздаётся само): stash `generated`/`blobs`/`cache` (превью, обложки),
`ffmpeg`/`ffprobe` (авто-скачка). transmission (public) — состояние не сохранялось.

## Что уцелело, а что потеряно

- **Уцелело** (было на SSD): настройки, список раздач, рейтинги torrent, БД stash со сценами и тегами.
- **Потеряно** (было на мёртвом HDD): сами файлы — скачанное в torrent, медиа stash (`/mnt/data/users/andrew/OMG`).

На новом диске:
- **transmission-omg** подхватит весь список торрентов и рейтинги, но данные пометит как missing → начнёт **перекачивать** заново, затем сидирование возобновится.
- **stash** сохранит все сцены/теги в БД, файлы будут missing → после повторного наполнения диска сматчит обратно; обложки/превью догенерятся при рескане.

## Восстановление

### 0. Предусловия
Новый диск смонтирован в `/mnt/data`, структура папок создана
(`/mnt/data/users/andrew/OMG`, `/mnt/data/public`, и т.д.), контейнеры остановлены.

### Восстановление `/users` из restic (backrest)
Данные `/mnt/data/users` бэкапились backrest'ом на удалённые хранилища
(FTP StorageBox `949745329.xyz` + Dropbox через rclone) — оттуда восстановимы.
**Сначала** верни rclone-конфиг, иначе до репо не достучаться:
- `~/.config/rclone/rclone.conf` — копия в **1Password: "RClone conf"**.

Конфиг backrest (список репо) — в `appdata/backrest/config/config.json`.

### 1. Распаковать appdata из бэкапов

> Важно: у архивов разная корневая структура — цели распаковки разные.

stash (файлы в корне архива → распаковка **в** `config/`):
```bash
sudo tar xzf stash-config.tar.gz -C /opt/homelab/appdata/stash/config/
```

transmission-omg (внутри папка `transmission-omg/` → распаковка **в** `appdata/`):
```bash
sudo tar xzf transmission-omg.tar.gz -C /opt/homelab/appdata/
```

### 2. Включить обратно отключённые сервисы

Сервисы отключены переименованием `docker-compose.yml` → `docker-compose.yml.disabled`
(чтобы `deploy.sh` и ребут их не поднимали). Включить = переименовать обратно:

```bash
cd /opt/homelab
for s in stash transmission-omg opml-generator transmission; do
  mv "services/$s/docker-compose.yml.disabled" "services/$s/docker-compose.yml"
done
```

(закоммить эти переименования, чтобы состояние репо совпадало с сервером)

### 3. Задеплоить

```bash
./scripts/docker/deploy.sh stash transmission-omg opml-generator transmission
```

### 4. После старта
- **transmission-omg**: проверь путь загрузок в settings, при необходимости запусти
  «Verify Local Data» по торрентам — недостающее начнёт качаться.
- **stash**: открой UI → Settings → Library, запусти Scan по `/data` после наполнения диска.

## Права доступа

Архивы созданы под `sudo` и хранят исходных владельцев. `sudo tar xzf` восстановит
владельца как был. Если контейнер не видит файлы — проверь владельца
(`PUID`/`PGID` из `.env`, по умолчанию 1000:1000 для transmission-omg; stash работает от root):

```bash
sudo chown -R 1000:1000 /opt/homelab/appdata/transmission-omg
```
