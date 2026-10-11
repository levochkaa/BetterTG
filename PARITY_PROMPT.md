# Промпт parity-goal (объединённый)

Максимизируй функциональный parity BetterTG с Telegram iOS на UIKit+Combine+TDLibKit и сохрани визуальную идентичность BetterTG. Сначала сведи все parity-линии в одну ветку и проверь результат, только потом закрывай новые gaps. Лимит не completion: оставь проверенный checkpoint и продолжи после resume. Явный запрос пользователя остановиться важнее: закончи текущий безопасный срез, сохрани checkpoint и остановись. Редактирование этого промпта само по себе goal не запускает.

## Контекст и источники

Прочитай AGENTS.md/CLAUDE.md, project.yml, build.sh, оба PARITY.md и PARITY_PROMPT.md из astra. Сохраняй чужие изменения. Telegram reference — ../Telegram-iOS: telegram-upstream/master (сейчас f1dd7a2dbd, release-13.0.0) для поведения, TDLib-логики и новых механик, pre-Liquid history для классического chrome. Фиксируй SHA/path каждого reference. Swiftgram upstream — только toggles. Не переноси Texture/SignalKit/Postbox/Display/ComponentFlow.

- `main` (локальный, не запушен; при написании 24d5b2f) — главный источник по toolchain, зависимостям и текущему UI: TDLibKit из levochkaa/TDLibKit с пином из project.yml main (сейчас `2.0.0-tdlib-1.8.68-c15d3f5a`, нативные модели), Xcode 27 по умолчанию, build.sh, пикер папок с liquid lens, кастомное контекстное меню.
- `codex/parity-continuation` (eb4e199, 5–6 сентября) — parity-код, уже переведённый на TDLibKit 2, и UI-решения, которые пользователь задал явно (раздел «Идентичность BetterTG»).
- `codex/a21e-previous-worker` (0f0b479, astra, 2–3 октября) — независимая ревизия parity: исправления ownership/lifecycle, изоляция client/account epochs, MediaCore, probes. Стоит на старом TDLibKit 1.5.2 через Packages/TDLibKitDynamic и ушла от UI main (в ней нет UIGlassEffect).
- Общий предок двух parity-веток — 7b0699d (31 августа). parity-continuation уже содержит main до 6dd705c.

## Этап 0 — свести всё в одну ветку

1. Создай отдельный worktree и ветку `codex/parity` от текущего локального main. Не трогай checkout main, сам main и исходные ветки, не удаляй их. Запиши SHA всех трёх источников.
2. Сведи parity-continuation и a21e в `codex/parity` через merge, чтобы история всех трёх источников осталась достижимой. Порядок промежуточных merge выбери сам (например, сначала перенеси astra на main/TDLibKit 2 в отдельной ветке), но каждый merge-коммит должен собираться без warnings. Стратегию запиши в PARITY.md.
3. Код astra переведи на TDLibKit 2 API из main. Удали Packages/TDLibKitDynamic и все использования моделей 1.x.
4. Конфликты решай по смыслу, по трёхсторонней разнице от 7b0699d. Дифф astra — ревизия качества и найденные дефекты. Дифф parity-continuation — правки пользователя, адаптация к TDLibKit 2 и слияние с main. Сохраняй намерения обеих сторон, ни одна ветка не выигрывает целиком:
   - Toolchain, зависимости, build, TDLib API — main. Конфликты с октябрьскими коммитами main (Xcode 27, TDLibKit 1.8.68, liquid lens, контекстное меню, бейджи папок) решай в пользу main, сохраняя parity-функциональность.
   - UI и визуальная идентичность — main плюс решения пользователя из parity-continuation. Если astra поменяла внешний вид, верни идентичность и оставь её логику под ним.
   - Логика, ownership, lifecycle, изоляция аккаунтов, медиа — по умолчанию astra как более поздняя ревизия того же flow, если она исправляет конкретный дефект или упрощает ownership и не ломает правки пользователя. Проверяй это по текущему коду, а не по отчётам astra. Flows, которых astra не касалась, бери из parity-continuation/main.
   - MobileVLCKit удали: обе parity-ветки уже перешли на MediaCore/FFmpeg. SwiftMath и прочие зависимости оставь, если их использует production-код.
   - Debug probes astra оставь только за launch-аргументами/DEBUG: при обычном запуске они не срабатывают и в production-пути не попадают.
5. Объедини PARITY.md в один: flows, implementation/audit status, исторические proofs с датами и ограничениями, ledger решений слияния (область → какой источник взят и почему, что перенесено с другой стороны). Замени PARITY_PROMPT.md этим промптом.
6. Этап 0 закрыт, когда есть одна ветка, ./build.sh build проходит без warnings на Xcode 27, приложение запускается, smoke ключевых flows в Simulator пройден (список чатов и папки, открытие чата, отправка текста и медиа в Saved Messages, галерея, голосовые и кружки, профиль, Forward to, контекстное меню) и PARITY.md сведён. Только после этого переходи к ревизии и новым gaps.

## Идентичность BetterTG

Telegram — эталон поведения, жестов, логики раскладки и edge cases. Внешний вид — как в BetterTG main, не Telegram 1:1. Новые экраны делай в том же стиле.

- Навбары и таб-бары: во всю ширину, blur, с safe area, контент скроллится под ними. Единый классический Telegram-навбар на всех экранах (TelegramClassicNavigationChrome из parity-continuation): размеры и кнопка Back как в списке чатов и в чате, без Liquid Glass-островков и системного glass-фона кнопок, без glass-вспышек во время push/pop.
- Пикер папок: снизу, Liquid Glass с liquid lens и interactive glass (main 24657e8), blur за ним, счётчики непрочитанных (75184a2). В Forward to тот же пикер.
- Контекстные меню: кастомное Telegram-меню с glass из main (TelegramContextMenu, 24d5b2f), жесты из CustomContextMenu (раздел ниже).
- Composer (решение пользователя, d27e495): без клавиатуры квадратный, во всю ширину, вместе с safe area; с клавиатурой анимированно скругляются все углы и появляются боковые отступы 8 pt. Неинтерактивный Liquid Glass. Отступ от плюсика до поля равен отступу до края, справа так же. При открытой клавиатуре за композером линейный градиент по кривой Telegram EdgeEffect: это имитация, потому что у перевёрнутого списка системный edge effect не работает. Обводка glass не просвечивает по углам и под home indicator.
- Quote берётся из выделения текста в открытом меню сообщения, отдельного пункта нет. Полоса реакций не выезжает сбоку.
- Поиск по топикам изначально скрыт и схлопывается раньше скролла списка, как в главном списке. В Forward to так же.
- Forward to: пикер папок снизу как на главной, компактные строки без last message, поиск в навбаре, без Add a comment и отдельной панели отправки. Тап по чату открывает этот чат с блоком «Forward message / user: text» в композере.
- Иконки обычные, не glass-варианты с убранным фоном.

## Жесты контекстного меню из CustomContextMenu

/Users/lev/Developer/CustomContextMenu — реконструкция жестов системного контекстного меню по дизассемблированному UIKitCore iOS 27.0 (24A434). Перенеси её модель касаний и движения в наше меню для всех его источников (сообщения, чаты, аватарки, папки), сохранив Telegram/BetterTG-вид самого меню.

- Читай README.md, Research/Interaction/README.md, App/MenuMotion.swift, App/MenuTouchRecognizer.swift, App/CustomMenu.swift, App/MenuRow.swift, App/MenuGeometry.swift, App/NativeUIKit.swift, Tests/InteractionChecks.swift.
- Перенеси: нажатие до открытия (0.15 с, допуск 20 pt, gravity-well progress/scale/тень, пружина), pan preview с rubber band, dismissal tap, handoff пальца снаружи в scrubbing, задержку выбора, общую подсветку строк с переходом между ними, исходы отпускания, Escape и accessibility escape. Константы бери из источника, не подбирай на глаз.
- Приватные вызовы делай только как в NativeUIKit.swift: с проверкой селектора и public fallback. Deployment target 26.0, поэтому fallback должен работать на iOS 26.
- Проверки из InteractionChecks перенеси как детерминированные проверки там, где они ложатся на наш код.

## Морф кнопки в меню из Telegram

Telegram добавил liquid morph кнопки в кастомное меню: telegram-upstream 58ce7d6688, f44a25a649, 11a469d1f8, 7c2cfd6a1f. Описание — docs/context-menu-liquid-morph.md; код — submodules/TelegramUI/Components/LensTransition (Bridge/LensTransitionRuntime.m, Identifiers.inc, LiquidMorphTransition.swift) и Display/Source/ContextMenuSourceLease.swift; prototype и тесты — prototypes/ContextMenuMorph.

- Перенеси механизм в BetterTG поверх нашего меню. Небольшой Objective-C runtime adapter допустим.
- Морф включается на источнике и только для отдельных кнопок и контролов, которые открывают меню: превью фото/видео, галерея и плеер (например moreButton в ChatViewAlbum, скорость или качество видео, кнопки превью медиа перед отправкой). Не применяй его к папкам, сообщениям и строкам списков.
- Поведение по Telegram: меню открывается на месте источника; закрытие перехватывает ещё открывающееся меню; морф идёт на 120 Hz с ограничением по времени; закрытие не мигает открытым меню. При Reduce Motion, отсутствии runtime или если источник ушёл из окна — текущий fallback.
- Системный UIMenu на UIButton UIKit морфит сам. Для перечисленных контролов используй наше меню с морфом, если так меню остаются единообразными. Решение по каждому контролу запиши в PARITY.md.

## Затем — ревизия и parity

После этапа 0 перепроверь сведённый код, начиная с мест конфликтов и кода astra, перенесённого на TDLibKit 2. Проследи полный путь: действие пользователя → состояние/ownership → TDLib → update → UI/cleanup. Особое внимание: изоляция account/client/chat/topic, provenance событий до асинхронной доставки, ownership и teardown Combine/tasks, отмена и устаревшие callbacks, время жизни C/Swift памяти, ограниченные очереди decode/cache/range, ownership audio/PiP/файлов, drafts/send/retry/relaunch, свежие permissions, timeline IDs/anchors, переходы и жесты галереи, тяжёлая работа вне main thread. Проверяй отрицательные и конкурентные сценарии. Исторический CLEAN автоматически не переносится.

Rewrite допустим только при конкретном дефекте, parity-gap, проблеме ownership/lifecycle, измеренной проблеме производительности или доказуемой лишней сложности. Перед rewrite зафиксируй причину, границы, сохраняемые контракты и проверки регрессий. Рабочее решение без причины не трогай.

Scope:
1. MediaCore вместо MobileVLCKit: gzip+rlottie/Lottie для TGS, WebP, FFmpeg для WebM/VP9 и плеера, Apple APIs. Стикеры и custom/animated emoji: loop/sync, пауза offscreen, ограниченный кэш, prefetch/cancel/fallback.
2. Voice: Ogg Opus+waveform, hold/cancel/lock, pause/resume, preview/seek/trim/send. Video notes: AVFoundation/AVAssetWriter H264/AAC, круглые preview и playback, камеры, hold/cancel/lock, limit, trim. Interruptions, durable ownership, retry, relaunch, cleanup.
3. VOD: воспроизведение до полной загрузки, seek/refetch ranges через downloadFile(offset/limit), getFileDownloadedPrefixSize, updateFile/cancel; буферизация, retry, offline, cache, lookahead; inline/fullscreen/PiP; A/V sync, EOF, ограниченная память.
4. Все MessageContent закреплённой версии TDLibKit: rendering и actions каждого поддерживаемого вида, unknown — fallback. Reply/quote/forward/edit/delete/select, reactions/pins/topics, captions/spoilers, unread/delivery.
5. Composer: formatted text, emoji/sticker/GIF, attachments/camera/files, reply/edit/forward, состояния voice/video, send/cancel/retry, keyboard. Send-flight из composer в bubble; delete через collapse/fade/slide без частиц; temporary→final IDs, смена account/topic.
6. Профили и галерея: все типы пиров, header, presence/bio/usernames/phone/actions, edit/member/admin, shared media с пагинацией. Переход thumbnail↔fullscreen без вспышки, paging/prefetch, zoom, dismiss-жесты, controls, captions/index, seek/rate/mute/PiP, share/save/forward/delete/open-in-chat.
7. Shell и навигация; multiple accounts с отдельными TDLib clients/storage/subscriptions, add/auth/switch/remove/logout; chats/folders/archive/search/edit/reorder/include/exclude, pin/mute/read/delete/clear/drafts.
8. Timeline: stable IDs, якорь messageId+pixelOffset, пагинация без прыжков при prepend/edit/media resize/keyboard, albums и date/topic headers, prefetch/cancel, всё account-scoped.

Не делай Gifts/Stars/collectibles/boosts/Premium/ads.

## Правила выполнения

- Production UI только на UIKit, без SwiftUI/hosting/representable.
- Запрещены browser/computer use и XcodeBuildMCP. Build и run только через ./build.sh. Smoke — ./build.sh run + device-interaction/idb; физическое устройство — ./build.sh run --device, когда нужны камера, PiP или 120 Hz. Не закрывай Simulator и не переводи на него фокус.
- Без push/PR. Не сбрасывай пользовательские базы, аккаунты и drafts. Тестовые отправки и удаления — только в Saved Messages или в созданных тобой приватных test-группах и форумах. Никогда не отправляй другим людям и не удаляй чужой или пользовательский контент.
- После каждого среза: один вызов swiftformat на все изменённые .swift, ./build.sh build без warnings (не подавляй их), review изменённого пути и его consumers, обновление PARITY.md, focused commit по AGENTS.md (`<feature|fix|tech>(<scope>): <summary>` и `Co-authored-by: Codex <noreply@openai.com>`) без чужих hunks.
- Работай малыми срезами с учётом бюджета. Не начинай срез, если не хватит ресурса на review, проверку и commit. При риске доведи или откати только своё, добейся чистого build и запиши checkpoint: последний проверенный commit, audit cursor, findings, blockers, следующий шаг.
- Не больше 2 subagents одновременно. Read-only аудит возвращает findings с доказательствами. Fix/feature делай в отдельном worktree с форматированием, warning-free build и commit; primary проверяет diff и берёт только проверенное. У сессии Simulator/device один владелец.
- Различай виды proof: source review, build, детерминированный probe, Simulator smoke, физическое устройство. Simulator не доказывает аппаратную камеру, системный PiP и 120 Hz. Probe, после которого приложение упало, не считается app-flow smoke.
- Не завершай goal из-за пройденного аудита, успешного build или лимита, пока есть выполнимый полезный gap и пользователь не просил остановиться. Не объявляй parity достигнутым целиком.

Перед handoff: ./build.sh build без warnings; в production нет MobileVLCKit, TDLibKitDynamic и SwiftUI-маркеров; нет незакоммиченных изменений агента. В отчёте: commits, что сведено и как решены конфликты, что перепроверено и исправлено, proofs, blockers, состояние goal и следующий срез.