# BetterTG backend: rich push relay

## Результат

Первой backend-фичей будет relay для rich push notifications:

```text
TDLib на iPhone
  └─ регистрирует deviceTokenWebPush с endpoint нашего сервера
       ↓
Telegram
  └─ отправляет зашифрованный Web Push
       ↓
Caddy → NestJS ingress → BullMQ worker
                         ├─ расшифровывает Web Push
                         ├─ отделяет видимые сообщения от service events
                         └─ собирает APNs payload
                              ↓
                             APNs
                              ↓
                         BetterTG на iPhone
```

Сервер не авторизуется в Telegram, не запускает TDLib, не хранит auth key или историю сообщений и не может делать запросы от имени пользователя. Он знает только installation, APNs token и Web Push key material. При этом relay неизбежно видит в памяти расшифрованный push-preview: имя отправителя, название чата, текст уведомления и routing identifiers. Это нужно явно отразить в privacy policy до публичного запуска.

Проект сразу строится как маленький модульный backend, а не одноразовый webhook. Push relay будет первой фичей; будущие возможности, не покрытые TDLib, смогут добавляться отдельными NestJS-модулями.

## Подтвержденные предпосылки

- Telegram публично поддерживает Web Push как `token_type = 10`. TDLibKit уже предоставляет `DeviceTokenWebPush`, содержащий `endpoint`, `p256dhBase64url` и `authBase64url`.
- Web Push шифруется стандартным P-256 ECDH + `aes128gcm` механизмом. Сервер должен владеть соответствующим private key, иначе расшифровать rich payload перед отправкой в APNs невозможно.
- После расшифровки Telegram payload содержит `loc_key`, `loc_args`, `user_id`, `custom.msg_id` и peer identifiers. Service events вроде `READ_HISTORY`, `MESSAGE_DELETED`, `MESSAGE_MUTED` и `DC_UPDATE` приходят тем же путем, но не должны становиться видимыми alert-уведомлениями.
- APNs принимает provider requests по HTTP/2. Обычный alert payload ограничен 4096 байтами, поэтому Telegram payload нельзя безусловно копировать целиком.
- Filtering entitlement для этой схемы не нужен: relay вообще не отправляет нежелательный alert в APNs. Silent/background notifications остаются best-effort и не дают полной консистентности.

## Scope первой версии

### Входит

- регистрация анонимной app installation без Telegram-аккаунта на сервере;
- прием и ротация APNs device token для sandbox и production;
- создание Web Push subscription и выдача данных для `DeviceTokenWebPush`;
- прием зашифрованного Telegram Web Push;
- расшифровка, строгая валидация и классификация payload;
- видимые APNs alerts для новых сообщений;
- routing data для открытия нужного аккаунта и чата;
- корректная обработка APNs retryable и terminal errors;
- отзыв installation/subscription;
- health checks, metrics, tracing и безопасные логи;
- локальное окружение и production deployment через Docker Compose + Caddy.

### Не входит

- Telegram authorization или TDLib session на сервере;
- чтение истории, отправка сообщений или серверная синхронизация чатов;
- собственная пользовательская учетная запись;
- VoIP/calls и PushKit;
- аватары и media attachments в notification;
- гарантированное удаление уже показанных notifications после `READ_HISTORY`/`MESSAGE_DELETED`;
- web dashboard, campaigns, массовые рассылки и admin panel;
- полный backend официального Telegram.

## Технологический фундамент

Backend строится как отдельное небольшое приложение с поддерживаемыми версиями runtime и зависимостей.

- TypeScript на Bun;
- NestJS с feature modules, DTO validation и URI versioning;
- Bun package manager и test runner;
- PostgreSQL + TypeORM migrations;
- Redis + BullMQ для короткой durable очереди;
- прямой APNs provider client поверх HTTP/2 и token-based `.p8` authentication;
- Caddy для публичного HTTPS endpoint, body limits и reverse proxy;
- Docker multi-stage image и Docker Compose;
- OpenTelemetry для traces, metrics и structured logs;
- Swagger только для management API, не для capability Web Push endpoint.

Архитектура разделяет producer/worker, lifecycle HTTP/2 APNs connections, graceful shutdown, health checks и правила redaction.

Предлагаемая структура:

```text
Backend/
  package.json
  bun.lock
  nest-cli.json
  tsconfig.json
  Dockerfile
  compose.yaml
  Caddyfile
  .env.example
  src/
    main.ts
    app.module.ts
    config/
    database/
    migrations/
    health/
    installations/
    telegram-web-push/
      crypto/
      ingress/
      classification/
    notifications/
      apns/
      jobs/
    observability/
    common/
  test/
    fixtures/
    e2e/
```

API process принимает HTTP-запросы и кладет ciphertext в очередь. Worker расшифровывает payload и общается с APNs. Оба процесса собираются из одного image, но запускаются разными commands, чтобы позднее масштабироваться независимо.

## Модель данных

### `installations`

- `id: uuid` — внутренний непредсказуемый identifier;
- `management_secret_hash` — hash bearer secret, сам secret показывается клиенту один раз;
- `apns_token_encrypted` — APNs token, зашифрованный application-level key;
- `apns_environment: sandbox | production`;
- `bundle_id` — только из server allowlist;
- `app_version`, `os_version` — опциональные compatibility fields;
- `status: active | disabled | revoked`;
- `last_seen_at`, `created_at`, `updated_at`.

### `telegram_push_subscriptions`

- `id: uuid`;
- `installation_id`;
- `endpoint_token_hash` — hash случайного capability token из публичного URL;
- `p256dh_public_key`;
- `p256dh_private_key_encrypted`;
- `auth_secret_encrypted`;
- `status: active | revoked`;
- `last_received_at`, `created_at`, `updated_at`.

В таблицах не должно быть Telegram user ID, phone number, username, chat ID, message ID или текста push. Эти значения разрешены только в памяти worker'а и в минимальном APNs payload с коротким TTL.

Отдельная delivery-history таблица для MVP не нужна. Delivery outcome хранится в метриках; если позднее потребуется аудит, записываются только opaque delivery ID, `loc_key`, timestamps, APNs status/reason и subscription ID без preview text и Telegram identifiers, с коротким retention.

## HTTP-контракты

Все management endpoints живут под `/api/v1` и после создания installation требуют `Authorization: Bearer <installation-secret>`. Это не пользовательская и не Telegram-авторизация: token лишь доказывает владение конкретной установкой приложения и хранится в iOS Keychain.

| Метод | Endpoint | Назначение |
| --- | --- | --- |
| `POST` | `/api/v1/installations` | Создать installation, привязать текущий APNs token, вернуть `installationId` и одноразово `managementSecret` |
| `PUT` | `/api/v1/installations/{id}/apns-token` | Обновить APNs token/environment после очередной регистрации приложения в APNs |
| `POST` | `/api/v1/installations/{id}/telegram-subscriptions` | Создать/ротировать Web Push key pair, вернуть endpoint, `p256dh` и `auth` |
| `DELETE` | `/api/v1/installations/{id}/telegram-subscriptions/{subscriptionId}` | Отозвать endpoint после TDLib unregister/logout |
| `DELETE` | `/api/v1/installations/{id}` | Полностью отозвать installation и стереть secrets |
| `POST` | `/webpush/v1/{capabilityToken}` | Публичный Web Push ingress для Telegram; принимает raw encrypted body |
| `GET` | `/health/live` | Liveness процесса |
| `GET` | `/health/ready` | Readiness с проверкой PostgreSQL, Redis и валидности config/keys |

`POST /installations` поддерживает client-generated idempotency key, чтобы сетевой retry не создавал дубликаты. Публичный Web Push endpoint не принимает JSON parser: ему нужны исходные headers и raw bytes без преобразований.

До public launch создание installation должно быть защищено App Attest assertion. Это не Telegram login и не требует собственного аккаунта, но не дает произвольному скрипту бесконечно создавать subscriptions и использовать сервер как push infrastructure. Для локального development используется отдельный явно включаемый bypass, который никогда не разрешен в production.

## Полный protocol flow

### 1. Bootstrap installation

1. iOS запрашивает разрешение на notifications и на каждом launch вызывает APNs registration.
2. После получения актуального device token клиент создает или обновляет installation.
3. Сервер возвращает management secret только при создании; приложение сохраняет его в Keychain.
4. Сервер генерирует Web Push P-256 key pair и auth secret. Private key остается на сервере в зашифрованном виде.
5. Клиент получает:

```json
{
  "subscriptionId": "uuid",
  "endpoint": "https://push.example.com/webpush/v1/<256-bit-random-token>",
  "p256dhBase64url": "...",
  "authBase64url": "..."
}
```

6. Авторизованный локальный TDLib регистрирует эти данные как `DeviceTokenWebPush`.
7. Для нескольких Telegram-аккаунтов один device coordinator использует корректный `otherUserIds`, чтобы не создавать дублирующиеся notifications. `data.user_id` из push передается обратно в приложение для выбора локального TDLib account.

`PushReceiverId`, возвращенный TDLib, остается client-side state: relay не может и не должен выполнять Telegram unregister самостоятельно.

При изменении набора локальных Telegram-аккаунтов клиент сначала делает доступные TDLib unregister-вызовы, затем ротирует общий Web Push endpoint и повторно регистрирует оставшиеся аккаунты. Это гарантирует, что вышедший аккаунт не продолжит слать pushes на старый capability URL, даже если его unregister не дошел до Telegram.

### 2. Telegram Web Push ingress

1. Telegram делает Web Push request на capability endpoint.
2. Caddy принимает только HTTPS, ограничивает request body и проксирует запрос в NestJS.
3. Ingress:
   - hash'ирует capability token и находит активную subscription;
   - проверяет method, `Content-Encoding`, content type, TTL и body size;
   - вычисляет digest ciphertext для idempotency;
   - кладет только ciphertext и разрешенные crypto headers в BullMQ;
   - отвечает успешным Web Push status только после durable enqueue.
4. Если Redis недоступен, endpoint отвечает `503`, а не подтверждает потерянный push.
5. Для неизвестного/revoked capability возвращается `404`/`410` без различимых деталей.

Начальный hard limit body — 8 KiB; увеличить его можно только после подтвержденного production fixture. Официальный Web Push profile рассчитан на payload примерно до 4 KiB.

### 3. Decryption и validation

Worker загружает subscription secrets, расшифровывает body по RFC 8291/RFC 8188 и сразу валидирует:

- поддерживается только наблюденный и покрытый тестами content encoding;
- ECDH point принадлежит P-256 и имеет корректный формат;
- AES-GCM authentication tag и padding delimiter валидны;
- decrypted payload — JSON object ожидаемой формы;
- `data.loc_key` соответствует `/^[A-Z0-9_]+$/`;
- `loc_args` имеет ограниченное число строк и длину;
- identifiers имеют ожидаемые numeric/string bounds;
- после mapping итоговый APNs JSON не превышает 4096 байт.

Не следует писать криптографию сразу внутри controller. Нужен изолированный `WebPushDecryptor` interface. Реализация выбирается после spike среди поддерживаемых библиотек; она обязана проходить официальные RFC 8291 test vectors и сохраненные encrypted fixtures. Если подходящей библиотеки нет, минимальная реализация на Node `crypto` допускается только в отдельном модуле с теми же vectors, negative tests и дополнительным security review.

Raw payload и decrypted preview нельзя логировать, сохранять в PostgreSQL, оставлять в failed BullMQ jobs или отправлять в telemetry.

### 4. Classification policy

Классификатор — отдельная pure function с версионируемой таблицей правил и exhaustive tests. Runtime использует exact allowlist известных видимых keys и exact service-event rules; prefix сам по себе никогда не разрешает показать alert.

| Класс | Примеры | Действие v1 |
| --- | --- | --- |
| Видимое сообщение | `MESSAGE_*`, `CHAT_MESSAGE_*`, `CHANNEL_MESSAGE_*`, агрегированные message keys | Отправить APNs `alert` |
| Удаление/прочтение | `MESSAGE_DELETED`, `READ_HISTORY`, `READ_REACTION` | В v1 не показывать; подготовить mapping для best-effort background push |
| Фоновое обслуживание | `MESSAGE_MUTED`, `DC_UPDATE`, `GEO_LIVE_PENDING` | Drop + metric, синхронизация при следующем запуске приложения |
| Calls | `PHONE_CALL_REQUEST` | Не обрабатывать в v1; отдельная VoIP/CallKit архитектура |
| Неизвестный key | Любой новый Telegram key | Fail closed: не показывать, записать metric/alert без payload |

Prefix применяется только в generator/tooling как подсказка при обновлении каталога. Новый `MESSAGE_*` key до human review остается unknown и не показывается; иначе, например, `MESSAGE_MUTED` легко ошибочно превратить в alert.

Machine-readable catalog Telegram `/api/config.json` используется как источник типов, аргументов и шаблонов. Его обновление делается явной командой, результат коммитится, а CI показывает diff новых/удаленных keys. Production server не должен молча менять classification по удаленному runtime config.

### 5. APNs mapping

Для message notification relay строит минимальный payload:

```json
{
  "aps": {
    "alert": {
      "loc-key": "CHAT_MESSAGE_TEXT",
      "loc-args": ["Alice", "Family", "Hello"]
    },
    "sound": "default",
    "thread-id": "opaque-peer-key"
  },
  "tg": {
    "account": "...",
    "peer": "...",
    "message": "..."
  }
}
```

Реальные field names и преобразование peer identifiers фиксируются client/server contract tests. Routing identifiers не должны попадать в logs или metrics.

Для v1 рекомендуется использовать `loc-key`/`loc-args` и соответствующий generated strings catalog в iOS app: тогда локализацией занимается устройство, а backend не хранит server-side копии текста на всех языках. Каждый key из server allowlist обязан существовать в app catalog и иметь Base/English fallback; это проверяется client/server contract test. Notification Service Extension можно добавить позже для avatar/media enrichment, но она не должна быть нужна для подавления пустых alerts.

APNs request:

- persistent HTTP/2 connection отдельно для sandbox и production;
- token authentication по `.p8`, `Key ID` и `Team ID`;
- `apns-topic` берется только из server config;
- `apns-push-type: alert`, priority `10` для новых сообщений;
- короткий `apns-expiration`, чтобы старые сообщения не всплывали через много часов;
- детерминированный `apns-id`/delivery ID для трассировки retry;
- `apns-collapse-id` применяется только для действительно заменяемых state events, не для разных сообщений;
- `sound` отсутствует для `custom.silent = true`.

Обработка ответов:

- `200` — success;
- `429`, `500`, `503`, timeout и broken connection — bounded retry с exponential backoff + jitter;
- `410 Unregistered`/`ExpiredToken`, `BadDeviceToken`, `DeviceTokenNotForTopic` — без retry, installation отключается до следующего APNs token update;
- auth/topic errors — alert для владельца сервера, а не бесконечный retry;
- payload/config errors — dead-letter metric с opaque delivery ID, без сохранения preview.

Provider JWT кэшируется на соединении и обновляется в допустимом Apple окне; APNs HTTP/2 `GOAWAY`, close и reconnect являются частью нормального lifecycle и покрываются тестами.

## Security и privacy

- Capability endpoint содержит минимум 256 бит случайности и никогда не включает installation ID.
- Management secret и endpoint token хранятся только как hashes; сравнение constant-time.
- APNs token, Web Push private key и auth secret шифруются envelope key, переданным через Docker secret/environment. В репозитории нет production secrets.
- Encryption key имеет version, чтобы поддерживать rotation и поэтапное re-encryption.
- App Attest защищает создание/обновление installation перед публичным релизом.
- Caddy ограничивает методы, body size, timeouts и TLS; per-installation/global rate limits реализуются в приложении/Redis, а не зависят от стороннего Caddy plugin.
- Контроллеры используют strict DTO validation, но Web Push ingress разбирает только raw body.
- Logs автоматически redacted; запрет на `loc_args`, APNs token, bearer tokens, endpoint token, raw/decrypted payload и Telegram identifiers проверяется тестами.
- BullMQ хранит только ciphertext. Completed jobs удаляются сразу; failed jobs имеют малый bounded retention.
- Redis работает с persistence и `noeviction`; PostgreSQL backup должен быть зашифрован, потому что в нем есть encrypted secrets.
- Все revoke/delete операции физически стирают encrypted token/key material, а не только ставят флаг.
- Server-side preview processing и retention policy описываются пользователю до включения relay.

## Observability и эксплуатация

Безопасные метрики:

- ingress requests по status;
- accepted/rejected/decryption-failed;
- classification по `loc_key` и action (`alert`, `background`, `drop`, `unknown`);
- queue depth и oldest-job age;
- server processing latency до APNs response;
- APNs success/error reason/retry count;
- active/revoked/disabled installations;
- HTTP/2 connect/close/error/GOAWAY.

Нужны alerts на рост decrypt failures, unknown `loc_key`, очередь старше нескольких секунд, APNs auth errors, массовый `BadDeviceToken` и отсутствие успешных deliveries при ненулевом ingress.

Target для собственного участка relay: p95 от accepted ingress до первого APNs response меньше 1 секунды при нормальной работе зависимостей. Это не обещание времени доставки на устройство: Telegram и APNs находятся вне нашего контроля.

Graceful shutdown перестает принимать ingress, дает активным jobs закончиться, закрывает BullMQ worker и HTTP/2 sessions, затем flush'ит telemetry.

## Проверка

### Protocol spike — обязательный нулевой этап

До scaffold production backend нужен маленький disposable receiver и проверка на физическом iPhone:

1. TDLib принимает выданный `DeviceTokenWebPush` и возвращает `PushReceiverId`.
2. Фиксируются фактические method, headers, `Content-Encoding`, body bounds и успешный response status, которые использует Telegram.
3. Реальный payload расшифровывается и совпадает с документированной JSON shape.
4. Проверяются private message, group, channel, photo, silent message, muted chat, read on another device и deleted message.
5. Проверяется multi-account routing и отсутствие duplicate notifications.
6. Проверяется, вызывает ли переданный через APNs payload `TDLib.processPushNotification` ожидаемым образом; если нет, клиент полагается на обычную синхронизацию после запуска.
7. Проверяется поведение Telegram при `5xx`, timeout и `410`.

Private fixture с реальным текстом не коммитится. Для regression suite создается синтетический payload той же структуры и отдельный RFC vector.

Spike считается пройденным только после rich alert на физическом устройстве без filtering entitlement и без Telegram-сессии на сервере. Если Telegram Web Push фактически отличается от стандарта или нестабилен, это фиксируется до разработки остального backend.

### Автоматические тесты

- RFC 8291 known-answer vectors и negative crypto vectors;
- classification table для каждого известного Telegram `loc_key`;
- payload shaping/localization arguments и 4096-byte trimming;
- endpoint capability lookup, revoke, replay/idempotency и rate limits;
- installation secret auth, APNs token rotation и App Attest verifier;
- TypeORM migration up/down и schema drift;
- BullMQ retry/permanent-error behavior;
- fake APNs transport: success, timeout, `GOAWAY`, `429`, `500`, `503`, `410`, invalid token/topic/auth;
- e2e: encrypted synthetic Web Push → queue → decrypt → expected APNs request;
- secret-leak test для logs, traces, metrics и failed jobs;
- Caddy config validation и container health/readiness.

### Ручная acceptance matrix

- Debug/sandbox и TestFlight/production APNs;
- app foreground/background/terminated;
- notification permission allowed/denied/re-enabled;
- APNs token rotation, reinstall и restore;
- direct/group/channel message, media message и silent message;
- muted chat не показывает alert;
- read/delete service events не показывают пустой alert;
- tap открывает правильный local account/chat/message;
- Redis/PostgreSQL restart, temporary APNs failure и backend rolling restart;
- logout/revoke прекращает доставку на старый endpoint.

## Этапы реализации

### Этап 0 — protocol spike

- disposable Web Push receiver;
- генерация subscription keys;
- TDLib registration на устройстве;
- расшифровка реальных fixtures;
- минимальная отправка в APNs sandbox;
- документированный compatibility report и решение go/no-go.

### Этап 1 — scaffold и infrastructure

- отдельный NestJS project в `Backend/`;
- config schema с fail-fast validation;
- PostgreSQL, Redis, TypeORM migrations, BullMQ;
- API/worker commands, Dockerfile, Compose, Caddy;
- health endpoints, structured redacted logger, OpenTelemetry;
- lint, unit, integration и e2e commands в CI.

### Этап 2 — installation lifecycle

- schema и migrations;
- create/update/revoke contracts;
- Keychain-compatible management secret flow;
- APNs token/environment rotation;
- Web Push key generation/encryption/rotation;
- App Attest production guard.

### Этап 3 — Web Push ingress

- opaque capability routes;
- raw-body handling и size/method/header validation;
- ciphertext-only BullMQ job;
- idempotency/replay guard;
- RFC-tested decryptor;
- strict Telegram payload parser.

### Этап 4 — classification и APNs delivery

- generated Telegram push catalog;
- visible/service/unknown policy;
- APNs mapper с payload budget;
- persistent sandbox/production HTTP/2 clients;
- retries, dead-token invalidation, connection lifecycle;
- privacy-safe metrics и alerts.

### Этап 5 — BetterTG integration

- APNs registration coordinator;
- installation client + Keychain state;
- TDLib `registerDevice`/unregister/24-hour refresh lifecycle;
- multi-account coordination;
- generated push localization strings;
- deep-link routing и optional `processPushNotification`;
- physical-device acceptance matrix.

### Этап 6 — production hardening

- production domain/DNS/TLS и Docker secrets;
- encrypted backups и restore drill;
- resource limits, Redis persistence/noeviction, deploy/rollback procedure;
- dashboards/alerts и runbook;
- privacy disclosure, deletion behavior и retention review;
- small closed beta before general availability.

Каждый этап завершается отдельным coherent commit, проверкой и коротким report. Следующий этап не маскирует непройденные acceptance criteria предыдущего.

## Definition of Done v1

- На физическом iPhone приходит rich notification с корректным sender/chat/message text.
- Tap открывает правильный локальный аккаунт и чат.
- Muted/service/unknown pushes не создают видимого пустого alert.
- На сервере нет Telegram authorization, TDLib database и Telegram account records.
- Preview text и identifiers отсутствуют в PostgreSQL, Redis job history, logs, traces и metrics.
- APNs token rotation и terminal token errors проверены.
- Transient APNs/Redis failures имеют bounded retry и наблюдаемы.
- Revoke installation прекращает прием и доставку.
- Sandbox и production разделены config и тестами.
- Deployment, backup/restore и incident runbook воспроизводимы с чистого сервера.

## Как оставить пространство для будущего backend

- `installations` — первый-party identity уровня устройства, а не суррогат Telegram user.
- Если позже появятся собственные accounts, добавляется отдельный `users`/`sessions` module и nullable ownership relation; push relay не переписывается.
- Telegram-specific parsing остается внутри `telegram-web-push`, а APNs delivery — generic `notifications` module, пригодный для будущих backend-generated notifications.
- Внешние capabilities добавляются feature modules с собственными migrations и contracts.
- Не вводятся общие event bus, microservices, Kubernetes или control panel до появления реальной второй фичи/нагрузки.
- API versioning, migrations, observability и secrets lifecycle закладываются сразу, потому что позже добавлять их к уже публичному relay существенно дороже.

## Решения по умолчанию перед стартом

Если нет отдельного решения, реализация исходит из следующих defaults:

- Telegram Web Push — единственный push ingress;
- одна активная Telegram Web Push subscription на installation;
- PostgreSQL + Redis/BullMQ с первого production deploy;
- localization на устройстве через `loc-key`/`loc-args`;
- service events в v1 не показываются; best-effort background handling добавляется отдельным этапом;
- App Attest обязателен до открытия registration endpoint публичному интернету;
- deployment — один небольшой Linux VPS с Docker Compose и Caddy, но API/worker уже разделены логически;
- имя домена, bundle ID, Apple Team/Key ID и production retention задаются перед этапом 1 как deployment config, а не зашиваются в код.

## Источники

- [Telegram: Handling PUSH-notifications](https://core.telegram.org/api/push-updates)
- [TDLib: `registerDevice`](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1register_device.html)
- [RFC 8291: Message Encryption for Web Push](https://www.rfc-editor.org/rfc/rfc8291)
- [RFC 8188: Encrypted Content-Encoding for HTTP](https://www.rfc-editor.org/rfc/rfc8188)
- [RFC 8030: Generic Event Delivery Using HTTP Push](https://www.rfc-editor.org/rfc/rfc8030)
- [Apple: Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
- [Apple: Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- [Apple: Handling notification responses from APNs](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns)
- [Caddy: `reverse_proxy`](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
