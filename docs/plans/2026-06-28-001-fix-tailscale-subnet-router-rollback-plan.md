---
title: "fix: откат Tailscale subnet-router + матрица верификации"
date: 2026-06-28
type: fix
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# fix: откат Tailscale subnet-router и возврат в рабочее состояние

## Summary

Убрать из репозитория, с сервера и из админки Tailscale subnet-router, анонсировавший
**собственный IP сервера** `192.168.1.41/32`, плюс связанный admin split-DNS. Вернуть
Tailscale к роли SSH+mesh (нет subnet-routing, нет persistent Tailscale-sysctl; runtime
`ip_forward` остаётся = 1 для Docker). Привести доки в соответствие и прогнать обязательную
матрицу верификации доступа и SSH. Authelia-bypass — отдельным отложенным шагом.

Решения оператора (зафиксированы): доступ к **другим** LAN-устройствам по tailnet не нужен →
откат полный, capability выпиливается. tailnet **single-user** (только свои устройства) →
доверенная зона.

---

## Problem Frame

Шаг `scripts/setup/10-setup-tailscale.sh` анонсировал `--advertise-routes=192.168.1.41/32` —
собственный IP сервера. **Два независимых корня поломки, не путать:**

1. **Server-side self-route (этот откат его реверсит).** Самореферентный subnet-route:
   Tailscale на хосте перехватывает трафик к этому IP и ломает локальный доступ LAN-клиентов
   к сервисам (TCP-коннект есть, ответы сервера не доходят).
2. **macOS network-extension residue (этот откат его НЕ реверсит).** После `tailscale down`
   на маке остаётся сетевое расширение, глотавшее входящий TLS к LAN-серверу. Лечится только
   Quit приложения + перезагрузка мака. Только документируется.

Вывод по сути: удалённый доступ к сервисам уже обеспечен Cloudflare Tunnel + Authelia
(`*.1218217.xyz` из любого интернета). Tailnet-роутинг поверх был лишним. Tailscale ценен за
SSH-откуда-угодно и mesh — эти функции LAN не трогают.

---

## Requirements

- **R1.** Репозиторий не анонсирует subnet-routes (`TS_ADVERTISE_ROUTES` пуст); повторный
  прогон шага снимает анонс и удаляет persistent IP-forwarding.
- **R2.** Tailscale остаётся в роли SSH (`--ssh`) + mesh, `accept-dns=false`, без exit-node,
  без advertise-routes.
- **R3.** LAN-маршруты и LAN-DNS (AdGuard → `192.168.1.41`) не изменяются.
- **R4.** Документация описывает только Tailscale SSH; разделы про subnet-router / Tailscale
  split-DNS / доступ к сервисам по tailnet удалены; добавлен раздел «Грабли» и явная
  граница доверия.
- **R5.** Матрица верификации пройдена. Server-side фикс изолированно подтверждён **с чистого
  устройства** (не с проблемного мака); критичные ячейки «Извне/Cloudflare» зелёные.
- **R6.** Граница доверия зафиксирована: tailnet single-user; SSH к `home` гарантируется
  членством в tailnet (не зависит от UFW :22 key-auth); прямой tailnet-IP путь к Traefik —
  diagnostic/admin, не основной удалённый путь (основной — Cloudflare).

---

## Key Technical Decisions

- **Доктрина узкая.** Запрет — только на маршрут, **содержащий собственный IP анонсирующей
  ноды** (самореферентный хайрпин), НЕ на subnet-routing вообще. (Стандартный паттерн —
  анонс LAN-подсети с **не-destination** ноды — остаётся легитимным, но в этом homelab не
  нужен: оператор подтвердил, что доступ к другим LAN-устройствам не требуется.)
- **Доступ к серверу по tailnet — через его tailnet-IP `100.78.130.93`** (нативный WireGuard,
  Traefik уже слушает `:443` на всех интерфейсах). Это diagnostic/admin путь, не основной.
- **tailnet = доверенная зона** (single-user). Поэтому SSH-по-членству и прямой tailnet-IP
  доступ к Traefik (включая `:80` без Authelia) приемлемы и фиксируются явно, без доп. ACL.
- **`ip_forward` в рантайме не сбрасываем** — нужен Docker. Снимаем только persistent-файл
  `/etc/sysctl.d/99-tailscale.conf`.
- **Admin split-DNS обязателен к удалению.** Без снятия записи `1218217.xyz → 100.78.130.93`
  tailnet-устройства с «Use Tailscale DNS» резолвят домен через AdGuard в `192.168.1.41` и
  упираются в отсутствие subnet-route → удалённый доступ для них ломается.
- **Runtime-откат — команды пользователю.** Claude правит только репозиторий.

---

## Implementation Units

### U1. Убрать subnet-router из конфигурации Tailscale-шага

- **Goal:** репо не зашивает анонс собственного `/32`; повторный прогон снимает анонс и
  persistent IP-forwarding даже при раннем выходе login.
- **Requirements:** R1, R2.
- **Files:** `scripts/lib/config.sh`, `scripts/setup/10-setup-tailscale.sh`
- **Approach:**
  - `config.sh`: `TS_ADVERTISE_ROUTES` → `""`; переписать комментарий блока «Subnet router» —
    не используем, доступ по tailnet через tailnet-IP напрямую (diagnostic). `TS_ADVERTISE_EXIT_NODE`
    остаётся `false`.
  - `10-setup-tailscale.sh`: удалить весь блок «Manual follow-up» под `if [[ -n "$TS_ADVERTISE_ROUTES" ]]`
    **и** stale-заголовок `print_header "Tailscale: ручные шаги..."` (строка ~99) — оставить
    только SSH-инфо без мислейбла. Перенести очистку `/etc/sysctl.d/99-tailscale.conf` (else-ветка)
    **до** блока `tailscale up`/login, чтобы ранний выход login не оставил persistent sysctl.
- **Patterns to follow:** существующая структура шага; новых механизмов не вводить.
- **Test scenarios:**
  - `bash -n` обоих файлов проходит.
  - `source scripts/lib/config.sh; echo "$TS_ADVERTISE_ROUTES"` → пусто.
  - Вывод скрипта не содержит admin-approval / split-DNS / accept-routes; заголовок «ручные
    шаги» не висит над одиночным SSH-эхо.
- **Verification:** `grep -nE 'advertise-routes=["'\'']?[0-9]' scripts/setup/10-setup-tailscale.sh`
  → пусто (нет хардкоднутого CIDR; пустой `--advertise-routes="$TS_ADVERTISE_ROUTES"` остаётся).

### U2. Привести документацию в соответствие

- **Goal:** доки про Tailscale SSH; subnet-router/split-DNS/«доступ к сервисам по tailnet»
  удалены; добавлены «Грабли» и граница доверия.
- **Requirements:** R4, R6.
- **Files:** `ENVIRONMENT.md`, `README.md`
- **Approach:**
  - `ENVIRONMENT.md`: убрать строку `Внешний + Tailscale` из доменной таблицы и `Subnet router`
    из таблицы Tailscale; удалить подраздел «Доступ к сервисам по tailnet». Оставить Tailscale
    SSH + `accept-dns=false`. Добавить «Грабли»: (1) НЕ анонсировать маршрут со **своим** IP
    (самореферентный хайрпин ломает LAN-доступ); (2) macOS `tailscale down` оставляет network
    extension — для сброса Quit приложения + ребут мака. Добавить строку **границы доверия**
    (tailnet single-user; SSH по членству; прямой tailnet-IP путь — diagnostic). В терминологии
    различать «Tailscale split-DNS» и «AdGuard split-horizon LAN DNS».
  - `README.md`: переписать раздел «Remote Access (Tailscale)» — только Tailscale SSH; убрать
    admin-console/split-DNS/клиентскую настройку **и блок «Verify from outside»** с
    `remote_ip → 192.168.1.41` (станет ложным).
- **Test expectation:** none (документация). Контроль:
  `grep -niE 'subnet|advertise-routes|split-dns|192\.168\.1\.41|100\.78\.130\.93' ENVIRONMENT.md README.md`
  не возвращает удалённых механизмов как актуальных (адреса допустимы только в «Грабли»/примере).

---

## Operational Rollback (выполняет пользователь, не Claude)

**Админка Tailscale** (https://login.tailscale.com/admin):
- DNS → Nameservers → удалить запись split-DNS `1218217.xyz → 100.78.130.93`.
- Machines → `home` → Edit route settings → убрать/не-одобрять `192.168.1.41/32`.

**Сервер `home`:**
```bash
sudo tailscale set --advertise-routes= --advertise-exit-node=false --ssh --accept-dns=false
sudo rm -f /etc/sysctl.d/99-tailscale.conf      # runtime ip_forward НЕ трогаем — нужен Docker
sudo tailscale debug prefs | grep -E '"RunSSH"|"CorpDNS"|"AdvertiseRoutes"|"AdvertiseExitNode"'
#   ожидаем: RunSSH=true, CorpDNS=false, AdvertiseRoutes=null, AdvertiseExitNode=false
```

**Мак:**
```bash
sudo tailscale set --accept-routes=false --exit-node=
sudo tailscale debug prefs | grep -E '"RouteAll"|"ExitNodeID"'   # оба пустые/false
# DNS уже чист после снятия admin split-DNS; accept-dns можно оставить (MagicDNS для имён нод)
```

---

## Verification Contract (обязательная — первичный критерий приёмки)

`TS` = Tailscale на клиенте. **Сначала доказать путь, потом результат** — иначе зелёная
ячейка не доказывает ничего.

**Перед LAN-ячейками** (доказать, что трафик идёт по LAN, а не utun/Tailscale):
```bash
route -n get 192.168.1.41 | grep interface     # должно быть en0/en1, НЕ utun*
```
**Перед Cloudflare-ячейками** (доказать публичный путь, а не локальный split-horizon):
```bash
dig +short dns.1218217.xyz @1.1.1.1            # должен вернуть публичный Cloudflare IP, НЕ 192.168.1.41
```
Во всех curl: `--connect-timeout 3 --max-time 10`. Минимум один строгий HTTPS-чек без `-k`
извне (доверие к публичному cert).

### Доступ к сервисам

| Откуда | TS | Метод | Что доказывает / команда | Ожидаем |
|---|---|---|---|---|
| Дома | OFF | home.local | baseline — `curl --max-time 10 -sI http://dns.home.local` | 200/302 |
| Дома | OFF | 1218217.xyz | baseline — `curl --max-time 10 -skI https://dns.1218217.xyz` | 302 → auth |
| **Дома** | **ON** | home.local | route=en0, затем curl | 200/302 — **КРИТ. (анти-хайрпин, server-side)** |
| **Дома** | **ON** | 1218217.xyz | route=en0, затем curl | 200/302/auth — **КРИТ.** |
| **Чистое устройство (телефон, дом. Wi-Fi)** | **ON** | 1218217.xyz | изолирует server-fix от мака | 200/302/auth — **КРИТ. (главный пруф отката)** |
| Мак | ON | 1218217.xyz | завязано на **ребут мака** (macOS residue, корень #2) | при висе → Quit Tailscale + ребут мака |
| **Извне** | **OFF** | 1218217.xyz | `dig @1.1.1.1`=публичный, затем строгий `curl --max-time 10 -sI https://dns.1218217.xyz` | **302 → auth — КРИТ. (Cloudflare-путь)** |
| **Извне** | **ON** | 1218217.xyz | через Cloudflare (admin split-DNS снят) | **302 → auth — КРИТ.** |
| Извне | ON | tailnet IP | diagnostic: `curl --resolve dns.1218217.xyz:443:100.78.130.93 ...` — только raw `:443` reachability (нативный WireGuard, не зависел от router) | 302 |

### SSH

| Откуда | TS | Метод | Команда | Ожидаем |
|---|---|---|---|---|
| Дома | OFF | IP | `ssh seigiard@192.168.1.41` | вход |
| Дома | OFF | home.local | `ssh seigiard@home.local` | вход |
| Дома | OFF | 1218217.xyz | `ssh seigiard@dns.1218217.xyz` | вход (резолв→192.168.1.41) |
| Дома | ON | IP / home.local / 1218217.xyz | те же | вход (TS не ломает) |
| Дома/Извне | ON | tailnet IP | `ssh seigiard@100.78.130.93` | вход |
| Любое | ON | tailscale ssh | `tailscale ssh seigiard@home` | вход (browser-check) |
| Извне | OFF | 1218217.xyz | `ssh seigiard@dns.1218217.xyz` | **fail** (Cloudflare не форвардит :22) |

Доп. (опц., подтвердить, что :22 не торчит наружу): с WAN — `nc -vz <public-ip> 22` → закрыт;
на сервере — `sudo ufw status verbose` / `sudo ss -tlnp | grep :22`.

---

## Scope Boundaries

**В плане:** откат subnet-router (репо + runtime + admin), доки, верификация.

### Deferred to Follow-Up Work

- **Доступ к не-серверным LAN-устройствам по tailnet** — оператор подтвердил, что не нужен;
  выпиливается. Если когда-нибудь понадобится — анонсировать `192.168.1.0/24` (НЕ свой IP),
  и не принимать этот маршрут на домашних устройствах. На одном сервере нетривиально.
- **Authelia-bypass для домашней сети** — пропускать логин на `*.1218217.xyz` из `192.168.1.0/24`
  (Cloudflare остаётся под Authelia). **Precondition (зафиксировать до реализации):** bypass
  только по **неподделываемому реальному source-IP**, исключая tailnet-клиентов (`100.x`), не
  доверяя чужому `X-Forwarded-For`; иначе расширяется unauth-поверхность. Гейт «видит ли
  Authelia реальный `192.168.1.x` сквозь Docker». Brainstorm:
  `docs/brainstorms/2026-06-28-authelia-tailnet-bypass-requirements.md`. Делать отдельно.

---

## Risks & Dependencies

- **Мак не восстановит `:443` после `tailscale up`** (macOS residue, корень #2) → Quit
  Tailscale-app + ребут мака. Поэтому server-fix валидируем **с чистого устройства** (R5).
- **Admin split-DNS не снят** → tailnet-устройства ломаются на резолве `1218217.xyz`. Снятие —
  обязательный шаг Operational Rollback.
- **`ip_forward=1` в рантайме держится Docker'ом**, persistent-файл снят — на следующем ребуте
  его восстановит dockerd (соответствует pre-subnet-router known-good состоянию).
- Конфиг AdGuard/Authelia в appdata, не в гите — этот план их не трогает.
- Репо-правки без Operational Rollback не возвращают сервер в рабочее состояние.

---

## Definition of Done

1. U1, U2 выполнены; `bash -n` чист; доки без subnet-router/split-DNS как актуальных; grep-контроль чист.
2. Operational Rollback выполнен (admin split-DNS снят, маршрут снят, сервер/мак prefs верны,
   `/etc/sysctl.d/99-tailscale.conf` отсутствует).
3. Матрица пройдена; server-fix подтверждён **с чистого устройства**; критичные «Извне/Cloudflare»
   и «Дома+TS» зелёные.
4. Граница доверия записана в `ENVIRONMENT.md`.
5. Изменения закоммичены (по запросу пользователя).
