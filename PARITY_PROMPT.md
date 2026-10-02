# Промпт parity-goal

Максимизируй parity BetterTG с Telegram iOS на UIKit+Combine+TDLibKit. Сначала независимо перепроверь накопленную реализацию, затем продолжай закрывать gaps. Лимит не completion: оставь проверенный checkpoint и продолжи после resume. Явный запрос пользователя остановиться имеет приоритет: закончи текущий безопасный срез, сохрани checkpoint и остановись, не начиная следующий gap. Редактирование этого промпта само по себе не запускает и не возобновляет goal.

## Контекст и ограничения

Прочитай AGENTS.md/CLAUDE.md/project.yml/PARITY.md и GOAL.md, если есть. Проверь HEAD, рабочий и staged diff, историю parity-коммитов и текущий код. Сохрани чужие изменения. База — официальный Telegram iOS в ../Telegram-iOS или основном checkout: telegram-upstream/master и pre-Liquid history. Фиксируй SHA/path использованного reference. Swiftgram upstream — лишь toggles. Не переноси Texture/SignalKit/Postbox/Display/ComponentFlow.

Production UI только UIKit; без SwiftUI/hosting/representable. Классический UI: полноширинные blur nav/tab bars с safe area, без floating islands/glassEffect. Исключение — composer: один цельный floating blur island со всеми функциями Telegram в заданном scope. Не делай Gifts/Stars/collectibles/boosts/Premium/ads. Запрещены browser/computer use/XcodeBuildMCP; smoke — device-interaction/idb. Не выключай Simulator; no push/PR/mock UI. Не сбрасывай пользовательские базы, аккаунты или drafts ради прохождения smoke.

## Первый этап — независимая ревизия на gpt-6-astra

Предыдущие изменения выполнялись на 5.6-sol. Перепроверь всю накопленную реализацию, включая закоммиченный код и flows, отмеченные done/implemented/CLEAN. Проверь и новые audit-fixes: смена модели не делает их автоматически корректными. Чистый git diff не означает отсутствие работы. Старые отчёты и proofs используй как исходные свидетельства с указанными ограничениями.

1. Установи baseline по Git-истории, составь карту реализованных flows, production entry points и общих зависимостей. Сопоставь PARITY.md с кодом и последующими коммитами: устаревший backlog не должен приводить к повторной реализации.
2. Проверь реальные production paths, TDLibKit API/models закреплённой версии, поведение и edge cases Telegram. Наличие switch-case, класса, API-вызова или probe само по себе не доказывает интеграцию. Проследи полный путь: пользовательское действие → состояние/ownership → TDLib → update → UI/cleanup.
3. Особое внимание: account/client/chat/topic isolation; provenance события до асинхронной доставки; ownership и teardown Combine/tasks; cancellation и stale callbacks; C/Swift memory lifetime; bounded decode/cache/range queues; audio/PiP/file ownership; durable drafts/send/retry/relaunch; свежие permissions; timeline IDs/anchors; gallery transitions/gestures; отсутствие тяжёлой работы на main.
4. Проверяй отрицательные и конкурентные сценарии: update до регистрации ожидания; отменённый callback после reuse; одинаковые числовые IDs разных аккаунтов; all-messages route против фактического sendTopic; Back/reopen во время preview/encoding/send; retry/discard при ещё живом owner; EOF и существенно разные длительности A/V. Добавляй проверки по найденным production-инвариантам, не подгоняй fixtures под happy path.
5. Для каждой области запиши дату, проверенный SHA/files, Telegram reference, TDLib version/API, findings P0/P1/P2, fix commits, proof и blockers. Отдельно веди implementation status и audit status: pending/reviewed/needs-fix/fixed/runtime-blocked. Различай source review, build, deterministic probe, Simulator smoke и physical-device/server proof. Указывай инвариант и границы каждого proof.
6. Исправляй подтверждённые P0/P1 по мере аудита малыми срезами. Допускается переписать неудачное решение при конкретном дефекте, parity-gap, проблеме ownership/lifecycle, измеренной проблеме производительности или доказуемой лишней сложности. Перед rewrite зафиксируй причину, границы, сохраняемые behavior/data contracts, миграцию при её необходимости и проверки регрессий. Смена модели, вкусовое предпочтение или старый код сами по себе не основание для rewrite. Сохраняй рабочее решение, если ревизия не нашла причины его менять.
7. Пройди все области scope хотя бы один раз и закрой доступные P0/P1 findings перед новым feature breadth. Недоступные проверки явно оставь blocked/unverified с причиной и next action; продолжай независимую работу. После ревизии бери следующий приоритетный gap. При resume продолжай с audit cursor, перепроверяя изменившиеся зависимости и потребителей исправлений, без бесконечного повторного аудита неизменённого кода.

## Scope — проверить существующее, исправить найденное, затем достроить

1. Полностью удали MobileVLCKit и переведи все его consumers на MediaCore, сохранив их функциональность. MediaCore: gzip+rlottie/Lottie для TGS, WebP binding, FFmpeg для WebM/VP9/player, Apple APIs. TGS, animated WebP, WebM alpha, stickers/custom/animated emoji: loop/sync, offscreen pause, bounded cache, prefetch/cancel/fallback.

2. Voice: Ogg Opus+waveform; hold/cancel/lock, pause/resume, preview/seek/trim/send. Video notes: AVFoundation+AVAssetWriter H264/AAC MP4, круглый preview/playback, cameras, hold/cancel/lock, limit, trim, InputMessageVideoNote. Проверь interruptions, durable ownership, retry, relaunch и cleanup.

3. VOD: play до полной загрузки, seek/refetch ranges через TDLib downloadFile(offset/limit), getFileDownloadedPrefixSize, updateFile/cancel; buffering/retry/offline/cache/lookahead/reuse. Ориентир — Telegram Player V2 directFetch+FFmpeg lookahead; TDLibKit-native, inline/fullscreen/PiP. Проверь A/V sync, EOF, ограниченность памяти, отмену и непрерывность owner/playhead при переходах.

4. Exhaustive MessageContent: text/entities/web, photo/video/album/GIF/sticker/emoji, voice/audio/document/video note, contact/location, poll/quiz/dice/service; unknown — fallback. Reply/quote/forward/edit/delete/select, reactions/pins/topics, captions/spoilers, unread/delivery. Сверяй полноту с generated models закреплённой версии, проверяй rendering и actions каждого поддерживаемого вида.

5. Composer: formatted text, emoji/sticker/GIF, attachments/camera/files, reply/edit/forward, voice/video states, send/cancel/retry, keyboard. Send transition: snapshots текста/reply/media/mic/video летят из composer в bubble с insertion и viewport anchor. Delete — collapse/fade/slide, без dust/particles. Проверь temporary→final IDs, ошибку/отмену отправки и смену account/topic.

6. Profiles/gallery: user/bot/group/channel/self, avatar/video header, presence/bio/usernames/phone/actions, edit/member/admin controls, shared-media tabs+pagination. Photo/video: thumbnail↔fullscreen transition без flash, paging+prefetch, pinch/double-tap zoom, pan/swipe dismiss, controls toggle, rotation/current item. Captions/index, buffering/error, seek/rate/mute/PiP, share/save/forward/delete/open-in-chat; жесты не конфликтуют. Проверяй свежие permissions, выбранный item и ownership при dismiss/delete/account switch.

Затем дострой UIKit shell/navigation; multiple accounts с отдельными TDLib clients/storage/subscriptions и add/auth/switch/remove/logout; chats/folders archive/search/edit/reorder/include/exclude, pin/mute/read/delete/clear/drafts. Уже существующие части этих областей входят в первоначальный аудит.

Timeline: stable IDs и anchor messageId+pixelOffset; pagination без прыжков при prepend/edit/media resize/keyboard; корректное объединение albums и date/topic headers; prefetch/cancel, ничего тяжёлого на main, всё account-scoped.

## Выполнение, proof и checkpoint

Веди PARITY.md: flow, Telegram reference, TDLib API, P0/P1/P2, implementation status, audit status, proof и blockers. Сохраняй исторические proofs с датами и ограничениями, новые привязывай к SHA, сценарию и окружению. При изменении контрактов, ownership или общих зависимостей узко перепроверяй затронутые flows; исторический CLEAN автоматически не переносится. Pending/reviewed/fixed указывай для конкретного scope; исправление одного дефекта не закрывает аудит всей области.

Работай limit-safe малыми срезами. После каждого implementation-среза одним swiftformat-вызовом форматируй все изменённые .swift, затем ./build.sh build; исправь errors/warnings без подавления. Выполни review изменённого пути и затронутых consumers. Обнови PARITY.md и закоммить свои изменения focused commit-ами по AGENTS.md, без чужих hunks.

Перед rewrite проверь доступный budget, если виден. Не начинай срез, если не остаётся ресурса на review, verification и commit. При риске закончи либо откати только свои незавершённые изменения, добей чистый build и запиши checkpoint: последний проверенный commit, audit coverage/cursor, findings, blockers и точный next step. Не оставляй незавершённый rewrite с расчётом на следующий turn.

До 2 subagents одновременно. Read-only аудит возвращает findings с доказательствами, без бессмысленных build/commit. Feature/fix — в отдельном worktree; каждый implementation-agent форматирует, делает warning-free build и focused commit. Primary проверяет diff, cherry-pick только проверенного результата и проверяет интеграцию. Один владелец simulator/device-сессии. Не spawn при недостаточном budget; перед остановкой заверши либо безопасно зафиксируй/откати начатую работу агентов.

Сначала correctness/breadth/logic, затем polish. Smoke через ./build.sh run+device-interaction/idb; проверяй production flows, а probes используй для конкретных инвариантов. Simulator не доказывает hardware camera или активный system PiP. Успешный probe с последующим crash приложения не равен успешному app-flow smoke. Blockers обходи независимой работой, сохраняя честные ограничения proof и пользовательские данные.

Не завершай goal только из-за завершённого аудита, успешного build или лимита, пока есть полезный выполнимый gap и пользователь не попросил остановиться. При запросе остановки сохрани незавершённый scope и выставь доступный статус паузы; не объявляй всю parity достигнутой.

Перед handoff: ./build.sh build без warnings; MobileVLCKit и запрещённые UI markers отсутствуют в production source/dependencies; нет незакоммиченных agent-authored изменений. Отчёт содержит commits, что перепроверено/исправлено, proofs, blockers, состояние goal и следующий срез. Если требуемый proof недоступен, явно укажи это вместо утверждения о полном завершении.
