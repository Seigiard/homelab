# Roadmap

Планы развития homelab. Работающие сервисы: `ls services/`.

## Планируемые сервисы

- [ ] **Immich** — фото-библиотека (директория `services/immich/` подготовлена)
- [ ] **Paperless** или [Papra](https://github.com/papra-hq/papra) — управление документами

## Планируемая интеграция

- [ ] **herdr remote** — сервер как SSH-машина для herdr 0.9.0 (`herdr machine add server` с mbp2026). SSH-доступ уже работает (Tailscale, ключи в 1Password на клиентах). Что нужно на сервере: бинарь herdr (шаг `scripts/setup/13-setup-herdr.sh`) и синхронизация агентского стека из my-mac-setup — herdr-плагины (`~/.config/herdr/plugins`), хелперы (`~/.local/bin`, `~/.local/lib`), скиллы агентов. herdr сам ничего не копирует на удалённые машины. Механизм связки решён (2026-09-10): chezmoi-роль `server` в my-mac-setup деплоит только агентские пути, а zsh и остальное остаётся за homelab (наборы путей должны быть непересекающимися; известное пересечение — `~/.ssh/config` против `07-setup-ssh-key.sh`, владельца назначит план реализации). Setup-шаг homelab сводится к установке chezmoi и `MMS_MACHINE_ROLE=server chezmoi init --apply`. Парная задача в my-mac-setup: `docs/issues/2026-09-09-001-set-up-herdr-0-9-0-multi-machine-remote.md`.

## Идеи

_(пока пусто)_

## Реализованные планы

Детали принятых решений в `docs/plans/`:

- [Syncthing + Navidrome + Audiobookshelf](docs/plans/2026-02-15-syncthing-navidrome-audiobookshelf.md)
- [FileBrowser Quantum миграция](docs/plans/2026-02-21-filebrowser-quantum-migration.md)
- [Folder2Podcast](docs/plans/2026-03-06-folder2podcast-design.md) — replaced by opml-generator
- **ytpod** — YouTube → audio podcast RSS ([vod2pod-rss](https://github.com/madiele/vod2pod-rss)), транскод MP3 on-demand, ничего не хранит
