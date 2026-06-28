# Authelia tailnet/LAN bypass — Requirements

**Date:** 2026-06-28
**Topic:** authelia-tailnet-bypass
**Scope:** Standard (security-sensitive)

## Summary

Сервисы на `*.1218217.xyz` сейчас требуют Authelia-логин на любом пути, включая прямой доступ по Tailscale. Сделать так, чтобы доступ из доверенных сетей — домашний LAN (`192.168.1.0/24`) и tailnet (`100.64.0.0/10`) — шёл без логина, а публичный путь через Cloudflare Tunnel сохранял SSO. Граница доверия определяется по source IP, который Traefik видит у клиента; три пути дают различимые IP.

## Problem Frame

У всех HTTPS-роутеров висит middleware `authelia@docker`, поэтому SSO применяется на каждом запросе независимо от пути. При заходе по tailnet (членство в mesh — уже сильная аутентификация) и из домашней LAN пользователь всё равно вводит логин-пароль. Трение ежедневное и не несёт защиты, которой ещё не дала сама сеть. Публичный вход через интернет — другой случай: там SSO нужен.

## Key Decisions

- **Граница доверия = сеть-источник.** Bypass для `192.168.1.0/24` и `100.64.0.0/10`; всё остальное (в первую очередь Cloudflare-путь) сохраняет Authelia.
- **Bypass единообразный на все сервисы** — без пер-сервисных исключений в v1.
- **Docker-подсеть `172.16.0.0/12` НИКОГДА не в bypass.** Трафик Cloudflare приходит в Traefik от контейнера `cloudflared` (`172.x`); включить её в bypass = открыть публичный путь.
- **Не доверять клиентскому `X-Forwarded-For`.** `forwardedHeaders.trustedIPs` у Traefik остаётся пустым, чтобы решение опиралось на реальный TCP-пир, а не на подделываемый заголовок.

## Requirements

R1. Запрос с доверенным client IP из `100.64.0.0/10` или `192.168.1.0/24` достаёт любой сервис `*.1218217.xyz` без Authelia-челленджа.
R2. Запрос через публичный Cloudflare Tunnel по-прежнему требует Authelia SSO.
R3. Bypass опирается на source IP, который Traefik реально наблюдает (TCP-пир), а не на клиентский заголовок.
R4. Docker-bridge подсеть (`172.16.0.0/12`) никогда не входит в bypass-набор.
R5. Существующая маршрутизация Home Assistant без Authelia (`services/traefik/config/dynamic/homeassistant.yml`) не затрагивается.
R6. Новый сервис наследует bypass без пер-сервисной настройки Authelia (или с задокументированным однострочником), в духе текущих label-конвенций.

## Approaches

Технический выбор — предмет brainstorm'а. Все три зависят от того, видит ли Traefik реальный source IP (см. «Критический неизвестный»).

**A. Authelia `access_control` networks bypass.** Добавить `100.64.0.0/10` и `192.168.1.0/24` правилами с policy `bypass` в конфиге Authelia; Authelia принимает решение по client IP, который Traefik передаёт через forwardAuth. Плюсы: одно место, сразу все сервисы, идиоматичный для Authelia путь, ноль изменений в Traefik-роутерах. Минусы: зависит от того, что Authelia получает реальный `100.x`/`192.168.x` (Traefik→forwardAuth XFF). Конфиг в appdata, не в гите. **Рекомендация.**

**B. Traefik пер-роутер `ipAllowList` + вариант без authelia.** По образцу HA-прецедента, но для каждого сервиса: второй роутер, матчащий source ∈ доверенным сетям и пропускающий middleware authelia. Плюсы: решение живёт в Traefik (он видит TCP-пир), не зависит от прокидывания заголовка в Authelia; конфиг в гите. Минусы: два роутера на сервис, больше движущихся частей, дублирование лейблов.

**C. Отдельный tailnet-only entrypoint / `tailscale serve`.** Traefik слушает на tailnet-IP (`100.78.130.93`) отдельным entrypoint'ом, его роутеры без Authelia. Сетевой пруф источника (этот IP недостижим публично) — полностью защищён от спуфинга, без доверия к заголовкам. Минусы: ломает текущую модель (split-DNS отдаёт `192.168.1.41`, не `100.x`); самое большое изменение. Покрывает только tailnet, не домашний LAN.

## Критический неизвестный (verify before planning)

Видит ли Traefik реальный client source IP сквозь Docker port-publishing, или маскированный gateway-IP? Это **гейт всей фичи**. Проверка на сервере: `accessLog` включён (`accessLog: {}`) — зайти на сервис по tailnet и из LAN, посмотреть поле `ClientHost`/`ClientAddr` в логе Traefik. Если IP маскируется (видно `172.x` для всех), подходы A/B в текущем виде не различают пути — тогда нужен `proxyProtocol`, host-networking для Traefik, или подход C.

## Security / Spoofing

- Пустой `trustedIPs` у Traefik → клиентский XFF не доверяется → публичный пользователь не подделает себя под `100.x` заголовком.
- TCP-пир Cloudflare-трафика на Traefik = контейнер `cloudflared` (`172.x`), вне bypass-набора.
- Остаточный риск: если позже выставить `forwardedHeaders.trustedIPs`, доверяющий `cloudflared`, публичный XFF начнёт проходить и сможет нести подделанный `100.x`. Guardrail: не доверять XFF от cloudflared (R3/R4).
- Нужно подтвердить, **из какого источника Authelia берёт client IP** (XFF vs прямой пир) — от этого зависит, сработает ли подход A.

## Dependencies / Assumptions

- Конфиг Authelia лежит в appdata на сервере (предположительно `/opt/homelab/appdata/authelia/`), **не в гите**. Правки там не версионируются этим репо, пока конфиг не внесём в git. (Допущение: в текущем `access_control` нет network-bypass — не проверено, конфиг вне репо.)
- Docker сохраняет source IP для published-портов — **не проверено**, см. «Критический неизвестный».
- Tailnet CGNAT-диапазон = `100.64.0.0/10`.

## Scope Boundaries

- **v1:** единообразный bypass для обеих доверенных сетей, все сервисы.
- **Отложено:** пер-сервисные SSO-исключения; внесение конфига Authelia в git; логирование реального client IP для Cloudflare-пути.

## Outstanding Questions

**Resolve before planning:**
- Результат теста видимости source IP (гейт).
- Откуда Authelia берёт client IP (XFF vs прямой) — сверить с её конфигом.

**Deferred to planning:**
- Выбор механизма A vs B после результата IP-теста.
- Версионировать ли конфиг Authelia (внести в репо vs оставить в appdata).

## Sources / Research

- `services/traefik/config/traefik.yml` — `api.insecure`, нет `forwardedHeaders.trustedIPs`, `accessLog` включён.
- `services/traefik/docker-compose.yml` — `authelia@docker` на `*-secure` роутерах + определение middleware authelia.
- `services/traefik/config/dynamic/homeassistant.yml` — прецедент роутера без Authelia.
- `services/cloudflared/docker-compose.yml` — `cloudflared` на `traefik-net` (для Traefik выглядит как `172.x`).
- Конфиг Authelia — appdata на сервере, не в репо.
