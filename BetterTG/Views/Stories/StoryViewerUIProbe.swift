// StoryViewerUIProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    /// Opens the story viewer on generated stories, so Telegram's cube, the story areas and the More menu can be
    /// checked on screen without the network. Launch with `-ui-probe-story-viewer-ui MODE [VALUE]`; once an
    /// account is active the viewer opens at Bob, between Alice and Carol:
    /// - `cube [fraction]` holds the cube part of a turn towards Carol (0.5 by default; a negative fraction
    ///   turns towards Alice), with the neighbour's face beside Bob's;
    /// - `cube-commit [fraction]` holds it for 1.5 s, then lets go as a drag that stops: past 0.3 the cube
    ///   turns on to the neighbour, short of it it springs back to Bob;
    /// - `areas [location|venue|message|link|weather|reaction]` taps that area on Bob's story (location by
    ///   default) and opens its tooltip; weather takes the tap without one, and the reaction becomes the story's;
    /// - `menu` opens the More menu as one of Bob's contacts sees it, and `menu-video` on a video story, where it
    ///   starts with Playback Speed;
    /// - `reply [edit|like-options|send]` checks the reply panel under Bob's story and likes it and takes the like
    ///   back, then edits the empty field with the reactions over it (edit, by default), holds the like button for
    ///   the other reactions (like-options), or sends a reply (send);
    /// - `own [footer|menu|delete]` opens the account's own stories instead, before Alice's: the footer with three
    ///   views from Alice, Bob and Carol, two reactions and a repost (footer, by default), the own More menu (menu),
    ///   or Delete's sheet, then the deletion, after which the second story, without views, shows (delete).
    /// The viewer reads only the seeded stories and chats and nothing reaches TDLib: a menu choice, the chat picked
    /// to share to, a like and a reply are only recorded. The story stays still until the viewer closes. Results go to
    /// the log and to
    /// Documents/story-viewer-ui-probe.txt.
    @MainActor enum StoryViewerUIProbe {
        private enum Mode {
            case cube(fraction: CGFloat, commits: Bool)
            case areas(kind: String)
            case menu(video: Bool)
            case reply(step: String)
            case own(step: String)
        }

        /// One of the areas on Bob's story, with the sticker its picture shows where the overlay draws nothing, and
        /// the tooltip a tap on it opens.
        private struct AreaSpec {
            let kind: String
            let area: StoryArea
            let label: String?
            let tooltip: String?
        }

        private struct Fixture {
            var stories = [Story]()
            var chats = [Chat]()
            var lists = [ChatActiveStories]()
        }

        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private static let flag = "-ui-probe-story-viewer-ui"
        private static let alice = Int64(9_100_000_001)
        private static let bob = Int64(9_100_000_002)
        private static let carol = Int64(9_100_000_003)
        /// The account in `own` mode: its stories get the footer and the own menu.
        private static let me = Int64(9_100_000_000)
        private static let ownStoryIDs = [1001, 1002]
        /// Bob's first unseen story, where the viewer opens, carries the areas.
        private static let areaStoryID = 202
        private static let fileIDBase = 1_910_000_000
        private static let menuPoster = StoryMoreMenu.Poster(
            chatID: bob,
            title: "Bob",
            compactTitle: "Bob",
            kind: .user(isContact: true, isBot: false),
            isService: false,
            username: "bettertg_probe",
            storiesMuted: false,
            storiesHidden: false,
            canBeArchived: true,
            accountIsPremium: true,
        )
        private static let ownMenuPoster = StoryMoreMenu.Poster(
            chatID: me,
            title: "Me",
            compactTitle: "Me",
            kind: .user(isContact: false, isBot: false),
            isService: false,
            isSelf: true,
            username: "bettertg_probe_me",
            storiesMuted: false,
            storiesHidden: false,
            canBeArchived: false,
            accountIsPremium: false,
            activeStoryIDs: Set(ownStoryIDs),
        )
        private static var lines = [String]()

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag) else { return }
            guard let mode = mode(from: arguments, flagIndex: index) else {
                record("Story viewer UI probe failed: unknown mode \(arguments[safe: index + 1] ?? "")")
                return
            }
            Task { @MainActor in
                do {
                    try await ProbeFixtures.waitForActiveAccount()
                } catch {
                    record("Story viewer UI probe failed: \(error)")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                let fixture: Fixture
                do {
                    var videoURL: URL?
                    if case .menu(video: true) = mode {
                        videoURL = try await ProbeVideo.make(
                            seconds: 4,
                            frameRate: 10,
                            named: "bettertg-story-probe.mov",
                        )
                    }
                    var includesOwn = false
                    if case .own = mode { includesOwn = true }
                    fixture = try makeFixture(videoURL: videoURL, includesOwn: includesOwn)
                } catch {
                    record("Story viewer UI probe failed: \(error)")
                    return
                }
                var isOwn = false
                if case .own = mode { isOwn = true }
                guard let presenter,
                      let viewer = StoryViewerController.presentProbe(
                          stories: fixture.stories,
                          chats: fixture.chats,
                          activeStories: fixture.lists,
                          initialChatID: isOwn ? me : bob,
                          menuPoster: isOwn ? ownMenuPoster : menuPoster,
                          replyPoster: .user(isBot: false, isService: false, isSelf: isOwn),
                          accountUserID: isOwn ? me : nil,
                          onMenuItem: { record("Story viewer UI probe menu chose \($0)") },
                          client: TDLib.shared.activeClient,
                          from: presenter,
                      )
                else {
                    record("Story viewer UI probe failed: the viewer didn't open")
                    return
                }
                // The viewer's entrance and the story's picture.
                try? await Task.sleep(for: .milliseconds(800))
                switch mode {
                case .cube(let fraction, let commits):
                    await runCube(viewer, fraction: fraction, commits: commits)
                case .areas(let kind):
                    await runAreas(viewer, kind: kind)
                case .menu(let video):
                    await runMenu(viewer, video: video)
                case .reply(let step):
                    await runReply(viewer, step: step)
                case .own(let step):
                    await runOwn(viewer, step: step)
                }
            }
        }

        /// Someone else's photo story everyone may see, as TDLib describes one; the menu probe varies its privacy,
        /// forwarding and editing.
        static func makeStory(
            id: Int,
            chatID: Int64,
            date: Int,
            file: File,
            areas: [StoryArea],
            privacy: TDNativeStoryPrivacySettings = .storyPrivacySettingsEveryone(
                TDNativeStoryPrivacySettingsEveryone(exceptUserIds: []),
            ),
            canBeForwarded: Bool = true,
            canBeEdited: Bool = false,
            canBeReplied: Bool = true,
            content: TDNativeStoryContent? = nil,
            caption: String = "",
            own: (isPosted: Bool, interactions: TDNativeStoryInteractionInfo?)? = nil,
            hasExpiredViewers: Bool = false,
        ) -> Story {
            let size = PhotoSize(type: "y", photo: file, width: 720, height: 1280, progressiveSizes: [])
            let photo = Photo(hasStickers: false, minithumbnail: nil, sizes: [size])
            let content = content ?? TDNativeStoryContent.storyContentPhoto(TDNativeStoryContentPhoto(photo: photo))
            let caption = FormattedText(text: caption, entities: [])
            return Story(
                id: id,
                posterChatId: chatID,
                posterId: nil,
                date: date,
                isBeingPosted: false,
                isBeingEdited: false,
                isEdited: false,
                isPostedToChatPage: own?.isPosted ?? false,
                isVisibleOnlyForSelf: false,
                canBeAddedToAlbum: false,
                canBeDeleted: own != nil,
                canBeEdited: canBeEdited || own != nil,
                canBeForwarded: canBeForwarded,
                canBeReplied: canBeReplied && own == nil,
                canSetPrivacySettings: own != nil,
                canToggleIsPostedToChatPage: own != nil,
                canGetStatistics: false,
                canGetInteractions: own != nil,
                hasExpiredViewers: hasExpiredViewers,
                repostInfo: nil,
                interactionInfo: own?.interactions,
                chosenReactionType: nil,
                privacySettings: privacy,
                content: content,
                areas: areas,
                caption: caption,
                albumIds: [],
            )
        }

        /// A downloaded photo file at `path`, which the viewer decodes without asking TDLib for it.
        static func photoFile(id: Int, path: String, uniqueID: String) -> File {
            let size = Int64((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0)
            let local = LocalFile(
                path: path,
                canBeDownloaded: false,
                canBeDeleted: false,
                isDownloadingActive: false,
                isDownloadingCompleted: !path.isEmpty,
                downloadOffset: 0,
                downloadedPrefixSize: size,
                downloadedSize: size,
            )
            let remote = RemoteFile(
                id: "",
                uniqueId: "bettertg-story-ui-probe-\(uniqueID)",
                isUploadingActive: false,
                isUploadingCompleted: true,
                uploadedSize: size,
            )
            return File(id: id, size: size, expectedSize: size, local: local, remote: remote)
        }

        // MARK: Modes

        private static func mode(from arguments: [String], flagIndex: Int) -> Mode? {
            let name = arguments[safe: flagIndex + 1].flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "cube"
            let value = arguments[safe: flagIndex + 2].flatMap { $0.hasPrefix("-") && Double($0) == nil ? nil : $0 }
            switch name {
            case "cube",
                 "cube-commit":
                let fraction = value.flatMap(Double.init).map { CGFloat($0) } ?? 0.5
                guard abs(fraction) > 0.01 else { return nil }
                return .cube(fraction: min(0.95, max(-0.95, fraction)), commits: name == "cube-commit")
            case "areas":
                return .areas(kind: value ?? "location")
            case "menu",
                 "menu-video":
                return .menu(video: name == "menu-video")
            case "reply":
                let step = value ?? "edit"
                return ["edit", "like-options", "send"].contains(step) ? .reply(step: step) : nil
            case "own":
                let step = value ?? "footer"
                return ["footer", "menu", "delete"].contains(step) ? .own(step: step) : nil
            default:
                return nil
            }
        }

        /// The held cube shows the neighbour it turns towards and turns Bob's face; a released one turns on past
        /// Telegram's 0.3 or springs back, and comes to rest flat with the side faces gone.
        private static func runCube(_ viewer: StoryViewerController, fraction: CGFloat, commits: Bool) async {
            let name = commits ? "cube-commit" : "cube"
            viewer.probeHoldCube(at: fraction)
            try? await Task.sleep(for: .milliseconds(300))
            let held = viewer.probeCube
            let towardsNext = fraction > 0
            let showsNeighbor = towardsNext
                ? held.showsNext && !held.showsPrevious
                : held.showsPrevious && !held.showsNext
            let holds = abs(held.fraction - fraction) < 0.01 && showsNeighbor && held.turnsFocused
            let heldText = String(format: "fraction=%.2f", Double(held.fraction))
                + " previous-face=\(held.showsPrevious) next-face=\(held.showsNext)"
                + " focused-turned=\(held.turnsFocused) reduce-motion=\(UIAccessibility.isReduceMotionEnabled)"
            guard commits else {
                record("Story viewer UI probe \(name) \(holds ? "passed" : "failed"): \(heldText)")
                return
            }
            try? await Task.sleep(for: .milliseconds(1500))
            viewer.probeReleaseCube()
            // Telegram's 0.4 s spring, and the faces' refresh after it.
            try? await Task.sleep(for: .milliseconds(800))
            let rest = viewer.probeCube
            let turnsOn = abs(fraction) >= StoryCubeGeometry.commitFraction
            let expected = turnsOn ? (towardsNext ? carol : alice) : bob
            let shown = viewer.probeShownChatID
            let rests = rest.fraction == 0 && !rest.showsPrevious && !rest.showsNext && !rest.turnsFocused
            let passes = holds && rests && shown == expected
            record(
                "Story viewer UI probe \(name) \(passes ? "passed" : "failed"): held \(heldText); "
                    + "released shown=\(title(of: shown)) expected=\(title(of: expected)) rest=\(rests)",
            )
        }

        /// A tap on the area's center opens Telegram's tooltip for it, over Bob's story with its reaction and
        /// weather drawn.
        private static func runAreas(_ viewer: StoryViewerController, kind: String) async {
            guard let spec = areaSpecs().first(where: { $0.kind == kind }) else {
                record("Story viewer UI probe areas failed: no \(kind) area (location, venue, message, link, weather)")
                return
            }
            let size = viewer.probeStorySize
            let position = spec.area.position
            let point = CGPoint(
                x: CGFloat(position.xPercentage) / 100 * size.width,
                y: CGFloat(position.yPercentage) / 100 * size.height,
            )
            viewer.probeTap(at: point)
            try? await Task.sleep(for: .milliseconds(400))
            let tooltip = viewer.probeTooltipText
            let storyID = viewer.probeShownStory?.id
            let drawn = viewer.probeDrawnAreaCount
            // The suggested reaction becomes the story's, as activateInlineReaction sets it.
            let reaction = viewer.probeLikeReaction?.standardEmoji ?? "none"
            let reacts = kind != "reaction" || reaction.unicodeScalars.first?.value == 0x2764
            let passes = storyID == areaStoryID && drawn == 2 && tooltip == spec.tooltip && reacts
            record(
                "Story viewer UI probe areas \(kind) \(passes ? "passed" : "failed"): story=\(storyID ?? 0) "
                    + "drawn=\(drawn) tooltip=\(tooltip ?? "none") expected=\(spec.tooltip ?? "none") "
                    + "reaction=\(reaction)",
            )
        }

        /// The More button opens Telegram's menu with a contact's items in performOtherMoreAction's order, Share left
        /// to the reply panel's button.
        private static func runMenu(_ viewer: StoryViewerController, video: Bool) async {
            viewer.probeOpenMoreMenu()
            try? await Task.sleep(for: .milliseconds(800))
            let sharesFromPanel = viewer.probeReplyConfiguration?.showsForward == true
            let items = viewer.probeShownStory.map {
                StoryMoreMenu.items(story: $0, poster: menuPoster, sharesFromPanel: sharesFromPanel)
            } ?? []
            let identifiers = items.map(StoryMoreMenu.identifier(of:))
            let expected = (video ? ["speed"] : []) + ["notify-off", "copy-link", "hide", "save", "report"]
            let shows = viewer.probeShowsMoreMenu
            let passes = shows && identifiers == expected
            record(
                "Story viewer UI probe \(video ? "menu-video" : "menu") \(passes ? "passed" : "failed"): "
                    + "shown=\(shows) items=\(identifiers.joined(separator: ","))",
            )
        }

        /// Bob's story takes a private reply beside the like and share buttons; a tap likes it with Telegram's heart
        /// and a second one takes the like back. Then the step's state is left on screen.
        private static func runReply(_ viewer: StoryViewerController, step: String) async {
            let expectedPlaceholder = L10n.telegram("Story.InputPlaceholderReplyPrivately")
            let configuration = viewer.probeReplyConfiguration
            let panel = viewer.probeReplyPanelFrame
            let story = viewer.probeStorySize
            let laidOut = panel.height == StoryReplyPanelView.height && panel.width > 0
            let shows = configuration?.field == .input(placeholder: expectedPlaceholder)
                && configuration?.showsLike == true && configuration?.showsForward == true
                && configuration?.offersLikeOptions == true
            viewer.probeLike()
            let liked = viewer.probeLikeReaction?.standardEmoji?.unicodeScalars.first?.value == 0x2764
            viewer.probeLike()
            let unliked = viewer.probeLikeReaction == nil
            var stepPasses = true
            var stepText = ""
            switch step {
            case "like-options":
                viewer.probeHoldLike()
                try? await Task.sleep(for: .milliseconds(500))
                let reactions = viewer.probeReplyReactions
                stepPasses = reactions?.mode == "like" && reactions?.title == nil && reactions?.count == 8
                    && viewer.probeIsPausedForReply
                stepText = "reactions=\(reactions?.mode ?? "none") title=\(reactions?.title ?? "none") "
                    + "count=\(reactions?.count ?? 0) paused=\(viewer.probeIsPausedForReply)"
            case "send":
                viewer.probeSendReply("Nice story")
                try? await Task.sleep(for: .milliseconds(500))
                stepPasses = !viewer.probeReplyIsEditing && !viewer.probeIsPausedForReply
                stepText = "editing=\(viewer.probeReplyIsEditing) paused=\(viewer.probeIsPausedForReply)"
            default:
                viewer.probeBeginReply()
                try? await Task.sleep(for: .milliseconds(1200))
                let reactions = viewer.probeReplyReactions
                let title = L10n.telegram("Story.SendReactionAsMessage")
                stepPasses = viewer.probeReplyIsEditing && reactions?.mode == "message" && reactions?.title == title
                    && viewer.probeIsPausedForReply
                stepText = "editing=\(viewer.probeReplyIsEditing) reactions=\(reactions?.mode ?? "none") "
                    + "title=\(reactions?.title ?? "none") paused=\(viewer.probeIsPausedForReply)"
            }
            let passes = laidOut && shows && liked && unliked && stepPasses
            record(
                "Story viewer UI probe reply \(step) \(passes ? "passed" : "failed"): "
                    + "panel=\(Int(panel.minY))+\(Int(panel.height)) story-height=\(Int(story.height)) "
                    + "input=\(shows) liked=\(liked) unliked=\(unliked) \(stepText)",
            )
        }

        /// The account's first story has the footer with its views, reactions and repost and the More button, and no
        /// reply panel. Then the step's state is left on screen.
        private static func runOwn(_ viewer: StoryViewerController, step: String) async {
            let footer = viewer.probeFooterConfiguration
            let frame = viewer.probeFooterFrame
            let story = viewer.probeStorySize
            let expected = StoryFooterPanel.Configuration(
                viewCount: 3,
                reactionCount: 2,
                forwardCount: 1,
                recentViewerIDs: [alice, bob, carol],
                canDelete: true,
            )
            let shows = footer == expected && viewer.probeReplyConfiguration == nil && viewer.probeShowsMoreButton
                && viewer.probeShownStory?.id == ownStoryIDs[0]
            let footerText = "footer=\(Int(frame.minY))+\(Int(frame.height)) story-height=\(Int(story.height)) "
                + "views=\(footer?.viewCount ?? -1) reactions=\(footer?.reactionCount ?? -1) "
                + "forwards=\(footer?.forwardCount ?? -1) viewers=\(footer?.recentViewerIDs.count ?? -1) "
                + "label=\(StoryFooterPanel.viewsLabel(count: footer?.viewCount ?? 0)) "
                + "reply-panel=\(viewer.probeReplyConfiguration != nil) more=\(viewer.probeShowsMoreButton)"
            var stepPasses = true
            var stepText = ""
            switch step {
            case "menu":
                viewer.probeOpenMoreMenu()
                try? await Task.sleep(for: .milliseconds(800))
                let identifiers = viewer.probeShownStory.map {
                    StoryMoreMenu.items(story: $0, poster: ownMenuPoster).map(StoryMoreMenu.identifier(of:))
                } ?? []
                stepPasses = viewer.probeShowsMoreMenu
                    && identifiers == ["save-to-profile", "save", "copy-link", "share"]
                stepText = "shown=\(viewer.probeShowsMoreMenu) items=\(identifiers.joined(separator: ","))"
            case "delete":
                viewer.probePressDelete()
                try? await Task.sleep(for: .milliseconds(1200))
                let actions = viewer.probeDeleteSheetActions ?? []
                viewer.probeConfirmDelete()
                try? await Task.sleep(for: .milliseconds(800))
                let next = viewer.probeShownStory?.id
                let nextFooter = viewer.probeFooterConfiguration
                stepPasses = actions == [L10n.telegram("Story.ContextDeleteStory"), L10n.telegram("Common.Cancel")]
                    && next == ownStoryIDs[1] && nextFooter?.viewCount == 0 && nextFooter?.recentViewerIDs == []
                stepText = "sheet=\(actions.joined(separator: "/")) next=\(next ?? 0) "
                    + "next-label=\(StoryFooterPanel.viewsLabel(count: nextFooter?.viewCount ?? 0))"
            default:
                break
            }
            let passes = shows && stepPasses
            record("Story viewer UI probe own \(step) \(passes ? "passed" : "failed"): \(footerText) \(stepText)")
        }

        private static func title(of chatID: Int64) -> String {
            switch chatID {
            case alice: "Alice"
            case bob: "Bob"
            case carol: "Carol"
            case me: "Me"
            default: String(chatID)
            }
        }

        private static func record(_ line: String) {
            lines.append(line)
            log(line)
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            else { return }
            try? Data(lines.joined(separator: "\n").utf8).write(
                to: directory.appendingPathComponent("story-viewer-ui-probe.txt"),
                options: .atomic,
            )
        }

        // MARK: Fixtures

        /// Alice's two stories, Bob's three with the second, his first unseen, carrying the areas, and Carol's one,
        /// each a generated picture named after its poster and place; with `includesOwn`, the account's two stories
        /// first, the first one viewed by the others and the second saved to the profile.
        private static func makeFixture(videoURL: URL? = nil, includesOwn: Bool = false) throws -> Fixture {
            let now = Int(Foundation.Date().timeIntervalSince1970)
            let run = UUID().uuidString
            var posters: [(chatID: Int64, title: String, colors: [UIColor], storyIDs: [Int], maxRead: Int, age: Int)] =
                [
                    (alice, "Alice", [.systemPink, .systemOrange], [101, 102], 0, 120),
                    (bob, "Bob", [.systemIndigo, .systemTeal], [201, 202, 203], 201, 40),
                    (carol, "Carol", [.systemGreen, .systemYellow], [301], 0, 5),
                ]
            if includesOwn {
                posters.insert((me, "Me", [.systemPurple, .systemBlue], ownStoryIDs, 0, 60), at: 0)
            }
            let views = TDNativeStoryInteractionInfo(
                viewCount: 3,
                forwardCount: 1,
                reactionCount: 2,
                recentViewerUserIds: [alice, bob, carol],
            )
            let areas = areaSpecs()
            var fixture = Fixture()
            for poster in posters {
                var infos = [TDNativeStoryInfo]()
                for (offset, storyID) in poster.storyIDs.enumerated() {
                    let storyAreas = storyID == areaStoryID ? areas : []
                    let date = now - (poster.age - offset * 5) * 60
                    let url = try writeImage(
                        storyID: storyID,
                        title: "\(poster.title) \(offset + 1)/\(poster.storyIDs.count)",
                        colors: poster.colors,
                        areas: storyAreas,
                    )
                    let file = photoFile(id: fileIDBase + storyID, path: url.path, uniqueID: "\(run)-\(storyID)")
                    // menu-video's story plays the movie from its local file, as a downloaded story video does.
                    let content = videoURL.flatMap { videoURL -> TDNativeStoryContent? in
                        guard storyID == areaStoryID else { return nil }
                        let movie = photoFile(
                            id: fileIDBase + 900 + storyID,
                            path: videoURL.path,
                            uniqueID: "\(run)-video-\(storyID)",
                        )
                        let video = TDNativeStoryVideo(
                            duration: 4,
                            width: Int(ProbeVideo.size.width),
                            height: Int(ProbeVideo.size.height),
                            hasStickers: false,
                            isAnimation: false,
                            minithumbnail: nil,
                            thumbnail: nil,
                            preloadPrefixSize: 0,
                            coverFrameTimestamp: 0,
                            video: movie,
                        )
                        return .storyContentVideo(TDNativeStoryContentVideo(video: video, alternativeVideo: nil))
                    }
                    let own = poster.chatID == me
                        ? (isPosted: offset == 1, interactions: offset == 0 ? views : nil)
                        : nil
                    fixture.stories.append(makeStory(
                        id: storyID,
                        chatID: poster.chatID,
                        date: date,
                        file: file,
                        areas: storyAreas.map(\.area),
                        content: content,
                        own: own,
                    ))
                    infos.append(TDNativeStoryInfo(
                        storyId: storyID,
                        date: date,
                        isForCloseFriends: false,
                        isLive: false,
                    ))
                }
                let position = ChatPosition(list: .chatListMain, order: 0, isPinned: false, source: nil)
                fixture.chats.append(ProbeFixtures.chat(position, title: poster.title, id: poster.chatID).chat)
                fixture.lists.append(ChatActiveStories(
                    chatId: poster.chatID,
                    list: .storyListMain,
                    order: 0,
                    canBeArchived: true,
                    maxReadStoryId: poster.maxRead,
                    stories: infos,
                ))
            }
            return fixture
        }

        /// Every area kind the viewer shows: location, venue, message and link stickers baked into the picture as
        /// Telegram's are, then the weather and a reaction with three reactions, which the overlay draws.
        private static func areaSpecs() -> [AreaSpec] {
            let bigBen = Location(latitude: 51.5007, longitude: -0.1246, horizontalAccuracy: 0)
            let venue = TDNativeVenue(
                location: bigBen,
                title: "Big Ben",
                address: "London SW1A 0AA",
                provider: "",
                id: "",
                type: "",
            )
            let location = TDNativeStoryAreaTypeLocation(location: bigBen, address: nil)
            let message = TDNativeStoryAreaTypeMessage(chatId: carol, messageId: 1 << 20)
            let link = TDNativeStoryAreaTypeLink(url: "telegram.org")
            // TDLib's ARGB is a signed int32: opaque white is -1.
            let white = Int(Int32(bitPattern: 0xFFFF_FFFF))
            let weather = TDNativeStoryAreaTypeWeather(temperature: 21.4, emoji: "☀️", backgroundColor: white)
            let heart = TDNativeReactionTypeEmoji(emoji: "❤")
            let reaction = TDNativeStoryAreaTypeSuggestedReaction(
                reactionType: .reactionTypeEmoji(heart),
                totalCount: 3,
                isDark: false,
                isFlipped: false,
            )
            let viewLocation = L10n.telegram("Story.ViewLocation")
            return [
                AreaSpec(
                    kind: "location",
                    area: StoryArea(
                        position: position(50, 26, 64, 6.5, -6, 12),
                        type: .storyAreaTypeLocation(location),
                    ),
                    label: "📍 Westminster",
                    tooltip: viewLocation,
                ),
                AreaSpec(
                    kind: "venue",
                    area: StoryArea(
                        position: position(50, 37, 64, 6.5, 0, 12),
                        type: .storyAreaTypeVenue(TDNativeStoryAreaTypeVenue(venue: venue)),
                    ),
                    label: "📍 Big Ben",
                    tooltip: viewLocation,
                ),
                AreaSpec(
                    kind: "message",
                    area: StoryArea(position: position(50, 48, 64, 6.5, 5, 12), type: .storyAreaTypeMessage(message)),
                    label: "💬 Carol's message",
                    tooltip: L10n.telegram("Story.ViewMessage"),
                ),
                AreaSpec(
                    kind: "link",
                    area: StoryArea(position: position(50, 59, 64, 6.5, 0, 6), type: .storyAreaTypeLink(link)),
                    label: "🔗 telegram.org",
                    tooltip: L10n.telegram("Story.ViewLink") + ", telegram.org",
                ),
                AreaSpec(
                    kind: "weather",
                    area: StoryArea(position: position(32, 72, 34, 6, 0, 20), type: .storyAreaTypeWeather(weather)),
                    label: nil,
                    tooltip: nil,
                ),
                AreaSpec(
                    kind: "reaction",
                    area: StoryArea(
                        position: position(70, 73, 24, 13.5, -10, 0),
                        type: .storyAreaTypeSuggestedReaction(reaction),
                    ),
                    label: nil,
                    tooltip: nil,
                ),
            ]
        }

        private static func position(
            _ x: Double,
            _ y: Double,
            _ width: Double,
            _ height: Double,
            _ rotation: Double,
            _ cornerRadius: Double,
        ) -> AreaPosition {
            AreaPosition(
                xPercentage: x,
                yPercentage: y,
                widthPercentage: width,
                heightPercentage: height,
                rotationAngle: rotation,
                cornerRadiusPercentage: cornerRadius,
            )
        }

        /// A 9:16 picture filling the story exactly, so the areas' percentages land on their stickers.
        private static func writeImage(storyID: Int, title: String, colors: [UIColor], areas: [AreaSpec]) throws
            -> URL
        {
            let size = CGSize(width: 720, height: 1280)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                drawStory(in: context.cgContext, size: size, title: title, colors: colors, areas: areas)
            }
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                throw Failure(description: "story \(storyID)'s picture didn't encode")
            }
            let url = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-story-ui-probe-\(storyID).jpg")
            try data.write(to: url, options: .atomic)
            return url
        }

        private static func drawStory(
            in context: CGContext,
            size: CGSize,
            title: String,
            colors: [UIColor],
            areas: [AreaSpec],
        ) {
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: nil,
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: [],
                )
            }
            let titleText = NSAttributedString(string: title, attributes: [
                .font: UIFont.systemFont(ofSize: 72, weight: .heavy),
                .foregroundColor: UIColor.white,
            ])
            let titleSize = titleText.size()
            titleText.draw(at: CGPoint(
                x: (size.width - titleSize.width) / 2,
                y: size.height * 0.88 - titleSize.height / 2,
            ))
            for spec in areas {
                guard let label = spec.label else { continue }
                let position = spec.area.position
                let width = CGFloat(position.widthPercentage) / 100 * size.width
                let height = CGFloat(position.heightPercentage) / 100 * size.height
                context.saveGState()
                context.translateBy(
                    x: CGFloat(position.xPercentage) / 100 * size.width,
                    y: CGFloat(position.yPercentage) / 100 * size.height,
                )
                context.rotate(by: CGFloat(position.rotationAngle) * .pi / 180)
                let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                UIColor.white.withAlphaComponent(0.92).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: CGFloat(position.cornerRadiusPercentage) / 100 * width)
                    .fill()
                let text = NSAttributedString(string: label, attributes: [
                    .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                    .foregroundColor: UIColor.black,
                ])
                let textSize = text.size()
                text.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
                context.restoreGState()
            }
        }
    }
#endif
