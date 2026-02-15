# Добавление Syncthing, Navidrome, Audiobookshelf

## Решения

| Вопрос | Решение |
|--------|---------|
| Syncthing networking | traefik-net + ports: 22000/tcp, 22000/udp, 21027/udp |
| Audiobookshelf storage | `/mnt/data/public/audiobooks/`, `/mnt/data/public/podcasts/` |
| Подкасты | Да |
| Authelia | Нет для всех трёх (своя авторизация + мобильные приложения) |

## Архитектура

| Сервис | Образ | Порт | Authelia | HDD |
|--------|-------|------|----------|-----|
| Syncthing | `syncthing/syncthing:latest` | 8384 | Нет | `/mnt/data/users/andrew/sync/` |
| Navidrome | `deluan/navidrome:latest` | 4533 | Нет | `/mnt/data/public/music/` (ro) |
| Audiobookshelf | `ghcr.io/advplyr/audiobookshelf:latest` | 80 | Нет | audiobooks + podcasts |

## Ресурсы

- Syncthing: 0.50 CPU, 256M
- Navidrome: 0.50 CPU, 256M
- Audiobookshelf: 0.50 CPU, 512M
