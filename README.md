# Homelab

Скрипты для автоматической настройки домашнего сервера Ubuntu.

## Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/seigiard/homelab/main/scripts/setup.sh | bash
```

Скрипт выполнит:
1. Установку git и клонирование репозитория в `/opt/homelab`
2. Обновление системы (apt update/upgrade)
3. Установку пакетов (zsh, micro, zellij, htop, mc, jq и др.)
4. Настройку Oh-My-Zsh с плагинами
5. Генерацию SSH-ключа для GitHub
6. Настройку git
7. Настройку Avahi (mDNS)
8. Применение dotfiles
9. Установку Docker

## Структура проекта

```
homelab/
├── scripts/
│   ├── setup.sh              # Entry point (curl | bash)
│   ├── bootstrap.sh          # Docker, директории, права
│   ├── lib/
│   │   ├── config.sh         # Общие переменные
│   │   └── tui.sh            # TUI библиотека
│   └── setup/
│       ├── --init.sh         # Оркестратор
│       ├── 00-update-system.sh
│       ├── 01-install-packages.sh
│       ├── 02-setup-zsh.sh
│       ├── 03-setup-ssh-key.sh
│       ├── 04-setup-git.sh
│       ├── 05-setup-avahi.sh
│       ├── 06-apply-dotfiles.sh
│       ├── 07-run-bootstrap.sh
│       └── 08-show-summary.sh
├── dotfiles/                  # Симлинкуются в ~
├── docker/                    # Docker compose файлы
└── tests/                     # Docker-тестирование
```

## Тестирование

Скрипты тестируются в Docker-контейнере с Ubuntu 22.04.

### Запуск тестов

```bash
# Сборка (с кешем — быстро, изменённые файлы пересобираются)
docker build -t homelab-test -f tests/Dockerfile .

# Сборка без кеша (полная пересборка)
docker build --no-cache -t homelab-test -f tests/Dockerfile .

# Запуск теста
docker run --rm homelab-test

# Тест одного скрипта
docker run --rm homelab-test /opt/homelab/scripts/setup/02-setup-zsh.sh

# Интерактивный режим
docker run -it --rm homelab-test bash
```

### Как работает TEST_MODE

В Docker устанавливается `TEST_MODE=1`, что:
- Пропускает интерактивные промпты (`press_enter`)
- Пропускает операции с GitHub (SSH test)
- Пропускает операции с Docker daemon (network create)
- Пропускает настройку firewall (UFW)

### Моки

В Docker нет systemd, поэтому используются заглушки:
- `tests/mocks/systemctl` — эмулирует systemctl
- `tests/mocks/hostnamectl` — эмулирует hostnamectl

### Верификация

Каждый скрипт проверяет результат своей работы:

| Скрипт | Что проверяется |
|--------|-----------------|
| 01-install-packages | `dpkg -s` для каждого пакета |
| 02-setup-zsh | `getent passwd` для проверки shell |
| 03-setup-ssh-key | Наличие файлов ключа |
| 05-setup-avahi | `hostname` после установки |
| 06-apply-dotfiles | `readlink` для symlink'ов |

## Перезапуск отдельных шагов

После установки можно перезапустить любой шаг:

```bash
cd ~/homelab
./scripts/setup/03-setup-ssh-key.sh
```

## Конфигурация

Основные переменные в `scripts/lib/config.sh`:

```bash
GITHUB_USER="seigiard"
GITHUB_EMAIL="seigiard@gmail.com"
INSTALL_PATH="/opt/homelab"
HOSTNAME="home"
```
