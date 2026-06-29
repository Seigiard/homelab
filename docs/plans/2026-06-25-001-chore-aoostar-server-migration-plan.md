# chore: Миграция сервера HP ProDesk → AOOSTAR WTR Pro

**Created:** 2026-06-25
**Origin:** `docs/brainstorms/2026-06-25-aoostar-migration.md`
**Type:** chore (hardware migration + infra hardening)
**Depth:** Standard

---

home 18:60:24:f6:fa:f9 192.168.1.41

## Summary

Перенос домашнего сервера на новое железо методом **lift-and-shift**: системный NVMe Kingston 240 ГБ физически переставляется из HP ProDesk 600 G3 (Intel i5-6400) в AOOSTAR WTR Pro (AMD Ryzen 7, 4-bay NAS). На диске и система, и данные — HDD 6 ТБ сейчас отключён, мигрирует один диск.

Главный риск перехода — смена имени сетевого интерфейса (`eno1` → другое), которая ломает статику в netplan и оставляет сервер без сети и DNS. План устраняет этот риск **заранее, на старом сервере**, сделав сетевую конфигурацию в setup-скриптах независимой от имени железа (netplan wildcard-match + авто-детект интерфейса для ethtool). После этого физический перенос становится почти headless.

---

## Problem Frame

- **Что меняется:** платформа Intel→AMD, корпус SFF→4-bay NAS. Мигрирует только системный NVMe.
- **Что НЕ затрагивается:** Docker + volume, appdata, `/opt/homelab`, Cloudflare Tunnel, Traefik, NUT, hostname. GPU-транскодинг и USB-проброс нигде не используются → переход Intel→AMD для сервисов прозрачен.
- **Ядро:** Ubuntu 24.04.3, kernel 6.8.0-106 — `amdgpu` из коробки, HWE-ядро не нужно.
- **Корневая проблема:** конфигурация сети в `scripts/lib/config.sh` и `scripts/bootstrap.sh` жёстко привязана к имени `eno1`. На новом железе имя другое → статика не применяется → нет сети → AdGuard DNS недоступен → ломается split-horizon и все сервисы.

---

## Requirements

- **R1.** Сетевая конфигурация setup-скриптов не должна зависеть от имени физического интерфейса.
- **R2.** Статика сохраняется: сервер на `192.168.1.41/24`, `nameservers` строго `127.0.0.1` (DHCP запрещён — сломает split-horizon AdGuard).
- **R3.** `accept-ra: false` сохраняется (без IPv6 RA-DNS роутера в обход AdGuard).
- **R4.** Изменения скриптов валидируются на текущем (рабочем) сервере до переноса — сеть не должна упасть.
- **R5.** После переноса все сервисы поднимаются без ручной правки конфигов (кроме того, что покрыто R1).
- **R6.** Документация (`ENVIRONMENT.md`, при необходимости `CLAUDE.md`) отражает новое железо и hardware-agnostic сеть.
- **R7.** CPU-микрокод соответствует платформе: на AMD установлен `amd64-microcode`; неиспользуемый `intel-microcode` не мешает.

---

## Key Technical Decisions

- **Netplan: wildcard `match: name: "en*"` вместо имени устройства.** Ubuntu 24.04 даёт предсказуемые `enpXsY`, до `eth*` дело не дойдёт. Логический ключ устройства — фиксированный `lan`. Глоб в `match.name` netplan поддерживает штатно.
- **Статика, не DHCP.** Сервер обязан быть на фиксированном `.41` (AdGuard rewrites, Samba-домены, split-horizon), DNS — только локальный AdGuard. DHCP навязал бы DNS роутера. _(см. origin: `docs/brainstorms/2026-06-25-aoostar-migration.md`)_
- **ethtool/EEE: авто-детект интерфейса в рантайме, не хардкод.** Сам `ethtool` авто-детект не умеет (требует имя аргументом), но скрипт/сервис вокруг него может вычислить активный интерфейс по дефолтному маршруту (`ip route show default`). Это снимает вторую привязку к `eno1` и делает `nic-tuning.service` устойчивым к смене железа на каждой загрузке. EEE-off — nice-to-have, при пустом результате безопасно деградирует в `log_warn`.
- **Двойной NIC WTR Pro.** При `en*` адрес `.41` пропишется на оба порта 2.5GbE; пока кабель в одном — конфликта нет. Принимается как осознанный компромисс (用户: «100% один LAN»).
- **lift-and-shift, не переустановка.** Тот же диск = тот же UUID, Ubuntu грузится на новом железе как есть.

---

## Implementation Units

### U1. Сделать сетевую конфигурацию скриптов hardware-agnostic

**Goal:** убрать привязку к имени `eno1` в setup-скриптах — и в netplan-генерации, и в nic-tuning. Выполняется на старом сервере **до** переноса.
**Requirements:** R1, R2, R3.
**Dependencies:** нет.
**Files:**

- `scripts/lib/config.sh` — заменить `export NET_INTERFACE="eno1"` на паттерн-переменную (напр. `NET_INTERFACE_MATCH="en*"`); обновить комментарий.
- `scripts/bootstrap.sh` — netplan-блок (≈205-219): ключ устройства → логический `lan` с `match: name: ${NET_INTERFACE_MATCH}`, остальное (`addresses`, `routes`, `accept-ra`, `nameservers`) без изменений.
- `scripts/bootstrap.sh` — nic-tuning (≈236-253): `nic-tuning.service` и немедленный вызов `ethtool` резолвят активный интерфейс в рантайме (`ip route show default`), а не подставляют имя; сохранить мягкую деградацию `|| log_warn`.

**Approach:**

- Netplan переходит со схемы «ключ = имя устройства» на «ключ = логическое имя `lan` + `match`». Это единственное структурное изменение шаблона.
- Для systemd-сервиса резолвинг интерфейса вынести так, чтобы избежать раскрытия `$(...)`/`$5` на этапе heredoc (например, через обёртку-вызов или экранирование) — конкретику оставить на реализацию.
- Не трогать `NET_IP`, `NET_GATEWAY`, `NET_DNS_PRIMARY`, `NET_DNS_FALLBACK`.

**Patterns to follow:** существующий heredoc-стиль генерации в `bootstrap.sh`; `2>/dev/null || log_warn` уже применён для ethtool (строка 253) — сохранить.

**Test scenarios:**

- Сгенерированный `/etc/netplan/01-netcfg.yaml` проходит `netplan generate` без ошибок и содержит блок `lan: { match: { name: "en*" }, addresses: [192.168.1.41/24], accept-ra: false, nameservers: [127.0.0.1] }`.
- На текущем сервере (интерфейс `eno1`) `match: "en*"` по-прежнему совпадает → IP `.41` остаётся, `resolvectl status` показывает DNS `127.0.0.1`.
- Авто-детект `ip route show default` на работающем сервере возвращает непустое имя интерфейса; `ethtool --set-eee <iface> eee off` отрабатывает (или `log_warn` при неподдержке).
- При пустом результате авто-детекта nic-tuning не падает (мягкая деградация).

_Тест-фреймворка в репозитории нет — валидация через `netplan generate` (dry-run, не apply) и проверки на живом сервере в U2._

**Verification:** оба файла больше не содержат литерала `eno1`; `rg 'eno1' scripts/` пусто.

---

### U2. Применить и проверить новую netplan-конфигурацию на текущем сервере

**Goal:** убедиться, что новый шаблон не роняет сеть на известно-рабочем железе, до того как полагаться на него после переноса.
**Requirements:** R4.
**Dependencies:** U1.
**Files:** нет (операционный шаг на сервере).

**Approach:** перегенерировать `/etc/netplan/01-netcfg.yaml` новым шаблоном → `sudo netplan generate` → `sudo netplan apply` → `sudo systemctl restart systemd-resolved`. Окно с консольным доступом на случай отката (есть бэкап старого файла).

**Verification:**

- `ip -br addr` → `.41` на `eno1`, state UP.
- `resolvectl status` → на Link DNS `127.0.0.1`; Global Fallback `1.1.1.1 1.0.0.1`.
- `resolvectl query dns.1218217.xyz` → `192.168.1.41` (split-horizon жив).
- Внешний сервис (`*.1218217.xyz`) и локальный (`*.home.local`) открываются.

---

### U3. Пред-перенос: бэкап, graceful stop, выключение

**Goal:** безопасно остановить сервер перед физическим вмешательством.
**Requirements:** R5.
**Dependencies:** U2.
**Files:** нет.

**Approach:** бэкап appdata (на всякий случай), затем `./scripts/docker/stop.sh` (все сервисы), затем штатное выключение хоста. NUT/UPS не трогаем — переедет с диском.

**Verification:** все контейнеры остановлены (`docker ps` пуст на сервере); хост выключен корректно (graceful shutdown — см. project memory).

---

### U4. Физический перенос + BIOS AOOSTAR

**Goal:** переставить NVMe и настроить загрузку нового хоста.
**Requirements:** R5.
**Dependencies:** U3.
**Files:** нет.

**Approach:**

- NVMe Kingston → слот M.2 на WTR Pro.
- BIOS: UEFI boot **ON**, Secure Boot **OFF** (как было на HP), boot order → NVMe Kingston первым.

**Verification:** машина стартует с NVMe, доходит до загрузчика Ubuntu.

---

### U5. Первая загрузка на AOOSTAR и проверки

**Goal:** подтвердить, что система и сервисы поднялись на новом железе.
**Requirements:** R5.
**Dependencies:** U4.
**Files:** нет.

**Approach:** благодаря U1 загрузка headless-совместима (монитор — только как страховка). После старта пройти проверки.

**Verification:**

- **Сеть/DNS:** `ip -br addr` → `.41` UP на новом интерфейсе; `resolvectl status` → DNS `127.0.0.1`; `resolvectl query dns.1218217.xyz` → `.41`.
- **UPS:** `sudo upsc eaton@localhost ups.status` → `OL`.
- **GPU:** `lspci -k | grep -A3 -i vga` → драйвер `amdgpu` загружен.
- **smartd:** ругань на отсутствующий `/dev/sda` — безвредна (HDD отключён); при желании временно закомментировать строку в `/etc/smartd.conf`.
- **Сервисы:** контейнеры поднялись сами; `./scripts/healthcheck.sh` зелёный; внешний и локальный домены открываются.

---

### U6. Обновить документацию под новое железо

**Goal:** привести `ENVIRONMENT.md` (и `CLAUDE.md` при необходимости) в соответствие реальности.
**Requirements:** R6.
**Dependencies:** U5.
**Files:**

- `ENVIRONMENT.md` — секция «Железо» (AOOSTAR WTR Pro, Ryzen 7, 4-bay), секция «Сеть» (wildcard-match вместо `eno1`, авто-детект для nic-tuning).
- `CLAUDE.md` — только если что-то из изменённого упоминается там (проверить).

**Approach:** заменить таблицу железа, обновить netplan-пример в секции «DNS хоста» на `match: "en*"`, отметить нюанс двойного NIC.

**Test scenarios:** `Test expectation: none` — документация.
**Verification:** `ENVIRONMENT.md` описывает AOOSTAR и hardware-agnostic сеть; устаревших упоминаний `eno1`/HP ProDesk в актуальных разделах нет.

---

### U7. Доустановка AMD-микрокода (дома, при интернете)

**Goal:** привести CPU-микрокод в соответствие с платформой AMD после lift-and-shift с Intel.
**Requirements:** R7.
**Dependencies:** U5 (система загрузилась и есть сеть/интернет на хосте).
**Files:** нет (операционный шаг на сервере; пакеты в `config.sh` не трогаем — это не часть bootstrap).

**Approach:**

- Требует интернета → выполняется дома, после подключения к LAN (вне дома сервер без сети).
- Не критично для загрузки: Ubuntu грузится на AMD и без `amd64-microcode`. Шаг даёт фиксы стабильности/безопасности CPU.

```bash
sudo apt update
sudo apt install amd64-microcode
sudo apt purge intel-microcode      # опционально; на AMD не используется
sudo update-initramfs -u
sudo reboot                         # микрокод применяется на раннем бутe
```

**Verification:**

- `journalctl -k | grep -i microcode` → строка о загрузке AMD microcode (`microcode updated early` / `Reload` без ошибок).
- `dmesg | grep -i microcode` не содержит упоминаний Intel.
- После `reboot` сервисы и сеть поднимаются как в U5 (микрокод не должен ничего сломать).

> Заодно дома: заполнить ⚠️-поля в `ENVIRONMENT.md` (CPU-модель, RAM, имена интерфейсов) выводом `lscpu` / `free -h` / `ip -br link`.

---

## Scope Boundaries

**В плане:**

- Перенос одного системного NVMe lift-and-shift.
- Hardware-agnostic сеть в setup-скриптах (netplan wildcard + авто-детект ethtool).
- Валидация на старом сервере, перенос, пост-проверки, обновление docs.
- Доустановка `amd64-microcode` под платформу AMD (дома, при интернете).

**Deferred to Follow-Up Work:**

- Подключение HDD 6 ТБ в bay нового NAS и поднятие `/mnt/data` по UUID (восстановление схемы appdata-on-SSD / data-on-HDD из `ENVIRONMENT.md`). Удачный момент — корпус вскрыт, — но это отдельная задача.
- Второй диск под mirror/parity или локальный бэкап `/mnt/data` (сейчас единичный HDD = нет избыточности).
- Перепрогон полного `bootstrap.sh` на новом железе (не требуется при lift-and-shift; нужен только если решим переустанавливать).

**Out of scope:**

- GPU-транскодинг под AMD (нигде не используется; при будущем Jellyfin/Immich — VAAPI/radeonsi, не QSV).

---

## Risks & Dependencies

- **Сеть не поднимется после переноса** → mitigation: U1 убирает привязку к имени, U2 валидирует шаблон на рабочем железе заранее; монитор+клавиатура как страховка на первую загрузку.
- **Двойной NIC, оба кабеля** → конфликт `.41`. Mitigation: держать кабель в одном порту (принято как компромисс).
- **UEFI/Secure Boot mismatch в BIOS AOOSTAR** → чёрный экран. Mitigation: явный пункт U4 (UEFI ON, Secure Boot OFF).
- **Точная модель Ryzen 7** не подтверждена — для amdgpu на 6.8 не критично (покрывает и Vega, и RDNA-iGPU), но стоит свериться при U5.

---

## Sources & Research

- Origin: `docs/brainstorms/2026-06-25-aoostar-migration.md`
- Текущее окружение: `ENVIRONMENT.md` (железо, UPS, сеть, netplan/DNS).
- Точки привязки в коде: `scripts/lib/config.sh:35`, `scripts/bootstrap.sh:205-219` (netplan), `scripts/bootstrap.sh:236-253` (nic-tuning/ethtool).
