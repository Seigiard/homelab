# Backups — восстановление после смерти HDD

Бэкапы appdata (конфиги на SSD) для сервисов, отключённых после выхода из строя
data-HDD (Seagate ST6000VN006 6TB, `/mnt/data`). Здесь только **ценные настройки**;
сами медиафайлы были на мёртвом диске и в бэкап не входят.

Дата: 2026-06-20

> Историческая справка. С 2026-08-18 `/mnt/data` — это RAID1-зеркало из двух Seagate 6 ТБ (`/dev/md0`), данные перенесены на него с временного каталога на системном NVMe. Утверждение ниже про то, что `/mnt/data/users` не бэкапится ни одним планом restic, остаётся верным.

> **Восстановление выполнено 2026-08-19, архивы не понадобились.** `appdata` обоих сервисов пережил смерть диска, потому что лежит на SSD: `stash-go.sqlite` и полный конфиг transmission-omg (`settings.json`, `torrents/`, `resume/`) нашлись на месте. Архивы распаковывать **не нужно** — они старше живого состояния и затрут его. Инструкция ниже оставлена на случай, если однажды умрёт сам SSD.
>
> Что сделано вместо этого: четыре сервиса включены обратно (`stash`, `transmission`, `transmission-omg`, `opml-generator`), заодно восстановлены удалённые `jellyfin` и `navidrome`. Медиафайлы при этом не вернулись — они были на мёртвом диске, так что stash показывает каталог с пометкой missing, а transmission-omg перекачивает раздачи заново.

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

### Что бэкапит backrest (важно!)
Планы backrest (`Dropbox`, `FtpBackup`) бэкапят **только `/backup/appdata/`** на
удалённые хранилища (FTP StorageBox `949745329.xyz` + Dropbox через rclone).
**`/mnt/data/users` НЕ бэкапится** ни одним планом — маунт `/backup/users:ro`
в compose есть, но в планах не используется.

Следствия:
- `/mnt/data/users` (вкл. `andrew/OMG`, `yuliia`, всё несинкаемое) в restic **нет**.
  Восстановление только через **syncthing-пиры** и только для синкаемых папок
  (`/users/andrew/sync`, `/public`).
- В restic лежит только **appdata** (он и так на SSD) — защита от смерти SSD.

Для доступа к restic-репо нужен rclone-конфиг:
- `~/.config/rclone/rclone.conf` — копия в **1Password: "RClone conf"**.

Конфиг backrest (список репо/планов) — в `appdata/backrest/config/config.json`.

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

Приём, которым сервисы были отключены: переименование `docker-compose.yml` →
`docker-compose.yml.disabled` (тогда `deploy.sh` и ребут их не поднимают).
Включить = переименовать обратно. Уже сделано 2026-08-19 в коммите `3c5ed40`,
команда оставлена как образец приёма:

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
