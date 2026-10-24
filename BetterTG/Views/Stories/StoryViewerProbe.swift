// StoryViewerProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// Drives the story viewer's state offline (no TDLib, no UI): the clock waiting for media, holding, auto-advance,
    /// tap navigation across posters, rewinding, lazily loaded posters, active-story updates and deletions, the
    /// header's time, the cube's neighbouring posters and its geometry, the story areas, the More menu's items and
    /// the reply panel's rules.
    /// Launch with `-ui-probe-story-viewer`; the result goes to the log and to Documents/story-viewer-probe.txt.
    @MainActor enum StoryViewerProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-story-viewer") else { return }
            let result: String
            do {
                try verifyClock()
                try verifyNavigation()
                try verifySingleStory()
                try verifyLazyPosters()
                try verifyUpdates()
                try verifyTimestamps()
                try verifyNeighbors()
                try verifyCube()
                try verifyAreas()
                try verifyMenuItems()
                try verifyOwnStory()
                try verifyViewList()
                try verifyChannelFooter()
                try verifyReplyPanel()
                result = "Story viewer probe passed: first-unseen-entry/clock-waits-for-media/hold-pause=true; "
                    + "auto-advance/next-poster/resume/rewind/dismiss=true; single-story=true; "
                    + "lazy-posters/empty-poster-dropped=true; active-update/delete/current-poster-removed=true; "
                    + "timestamps=true; cube-neighbors/resume/unloaded=true; "
                    + "cube-rest-flat/half-turn-edges-meet/whole-turn-gap-40/rubber-band/spring=true; "
                    + "area-placement/rotated-hit/side-inset/reaction-skipped/tooltip-source/temperature=true; "
                    + "menu-contact/muted-hidden/non-contact/service/bot/private/protected/own/panel-share/speed/"
                    + "translate=true; "
                    + "own-menu/expired/live/button/footer/no-views/view-label/count-text=true; "
                    + "view-list-title/tabs-at-20/private-no-tabs/sort-at-10/expired-no-header/empty-texts/"
                    + "subtitles/page-kinds/layout/drag-outcomes/row-menus=true; "
                    + "channel-footer/private-no-share/closed-group/writable-group-none=true; "
                    + "reply-user/private/closed/service/bot/self/group/read-only-group/channel/live/reaction-text=true"
            } catch {
                result = "Story viewer probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("story-viewer-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func make(
            _ posters: [StoryViewerState.Poster],
            initialChatID: Int64,
        ) throws -> StoryViewerState {
            guard let state = StoryViewerState(posters: posters, initialChatID: initialChatID) else {
                throw Failure(description: "state refused \(posters.map(\.chatID))")
            }
            return state
        }

        private static func verifyClock() throws {
            var state = try make([.init(chatID: 1, storyIDs: [10, 11, 12], maxReadStoryID: 10)], initialChatID: 1)
            try require(state.currentStoryID == 11, "didn't open at the first unseen story")
            try require(state.advance(by: 1) == .none && state.elapsed == 0, "clock ran before the media showed")
            state.mediaDidBecomeReady(duration: StoryViewerState.photoDuration)
            try require(state.advance(by: 2.5) == .none && abs(state.progress - 0.5) < 0.001, "photo progress")
            state.setPaused(true, for: .hold)
            try require(state.advance(by: 2) == .none && abs(state.progress - 0.5) < 0.001, "hold didn't pause")
            state.setPaused(false, for: .hold)
            try require(
                state.advance(by: 3) == .story && state.currentStoryID == 12 && state.progress == 0
                    && state.duration == nil,
                "photo didn't advance after five seconds",
            )
            state.mediaDidBecomeReady(duration: 8)
            state.setElapsed(4)
            try require(abs(state.progress - 0.5) < 0.001, "video progress didn't follow its player")
            try require(state.next() == .dismiss, "last story didn't close the viewer")
        }

        private static func verifyNavigation() throws {
            var state = try make(
                [.init(chatID: 1, storyIDs: [1, 2]), .init(chatID: 2, storyIDs: [5, 6, 7], maxReadStoryID: 6)],
                initialChatID: 1,
            )
            try require(state.next() == .story && state.currentStoryID == 2, "next story")
            try require(
                state.next() == .poster(forward: true) && state.currentChatID == 2 && state.currentStoryID == 7,
                "next poster didn't open at its first unseen story",
            )
            try require(state.previous() == .story && state.currentStoryID == 6, "previous story")
            try require(state.previous() == .story && state.currentStoryID == 5, "previous story again")
            try require(
                state.previous() == .poster(forward: false) && state.currentChatID == 1 && state.currentStoryID == 2,
                "previous poster didn't resume where it was left",
            )
            try require(state.previous() == .story && state.currentStoryID == 1, "back to the first story")
            state.mediaDidBecomeReady(duration: 5)
            _ = state.advance(by: 1)
            try require(state.previous() == .rewind && state.elapsed == 0, "first story didn't rewind")
            try require(state.movePoster(forward: false) == .none, "swipe before the first poster")
            try require(
                state.movePoster(forward: true) == .poster(forward: true) && state.currentStoryID == 5,
                "swipe didn't resume the next poster",
            )
            try require(state.movePoster(forward: true) == .none, "swipe past the last poster")
            try require(state.upcoming?.storyID == 6, "upcoming story")
        }

        private static func verifySingleStory() throws {
            var state = try make([.init(chatID: 5, storyIDs: [42])], initialChatID: 5)
            try require(state.currentChatID == 5 && state.currentStoryID == 42 && state.upcoming == nil, "single")
            try require(state.previous() == .rewind, "single story didn't rewind")
            try require(state.next() == .dismiss, "single story didn't close")
            try require(StoryViewerState(posters: [.init(chatID: 5, storyIDs: [])], initialChatID: 5) == nil, "empty")
        }

        private static func verifyLazyPosters() throws {
            var state = try make(
                [.init(chatID: 1, storyIDs: [1]), .init(chatID: 2), .init(chatID: 3)],
                initialChatID: 1,
            )
            try require(state.upcoming?.chatID == 2 && state.upcoming?.storyID == nil, "unloaded upcoming poster")
            state.mediaDidBecomeReady(duration: 5)
            try require(
                state.advance(by: 5) == .poster(forward: true) && state.currentChatID == 2
                    && state.currentStoryID == nil,
                "didn't enter the unloaded poster",
            )
            try require(
                state.updateStories(chatID: 2, storyIDs: [20, 21], maxReadStoryID: 20) == .story
                    && state.currentStoryID == 21,
                "loaded poster didn't open at its first unseen story",
            )
            try require(
                state.updateStories(chatID: 3, storyIDs: [], maxReadStoryID: 0) == .none && state.posters.count == 2,
                "a poster without stories wasn't dropped",
            )
            try require(state.next() == .dismiss, "dropped poster still followed")
        }

        private static func verifyUpdates() throws {
            var state = try make(
                [.init(chatID: 1, storyIDs: [1, 2, 3]), .init(chatID: 2, storyIDs: [9])],
                initialChatID: 1,
            )
            _ = state.next()
            try require(
                state.updateStories(chatID: 1, storyIDs: [2, 3, 4], maxReadStoryID: 2) == .none
                    && state.currentStoryID == 2 && state.storyIndex == 0,
                "an update moved the shown story",
            )
            try require(
                state.removeStory(chatID: 1, storyID: 2) == .story && state.currentStoryID == 3,
                "deleting the shown story didn't show the next",
            )
            try require(
                state.removeStory(chatID: 2, storyID: 9) == .none && state.posters.count == 1,
                "another poster's last deletion",
            )
            try require(state.removeStory(chatID: 1, storyID: 3) == .story && state.currentStoryID == 4, "delete")
            try require(state.removeStory(chatID: 1, storyID: 4) == .dismiss, "emptied viewer didn't close")

            var posters = try make([.init(chatID: 1, storyIDs: [1]), .init(chatID: 2, storyIDs: [2])], initialChatID: 1)
            try require(
                posters.updateStories(chatID: 1, storyIDs: [], maxReadStoryID: 0) == .poster(forward: true)
                    && posters.currentChatID == 2 && posters.currentStoryID == 2,
                "current poster's expiry didn't move on",
            )
            try require(
                posters.removeStory(chatID: 7, storyID: 1) == .none && posters.removeStory(chatID: 2, storyID: 99)
                    == .none,
                "unknown deletions changed the viewer",
            )
        }

        private static func verifyTimestamps() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Foundation.TimeZone(secondsFromGMT: 0) ?? .current
            let now = Date(timeIntervalSince1970: 1_792_152_000) // 12:00 UTC
            let seconds = Int(now.timeIntervalSince1970)
            try require(
                StoryTimestamp.string(date: seconds - 30, now: now, calendar: calendar)
                    == L10n.telegram("Time.JustNow"),
                "just now",
            )
            try require(
                StoryTimestamp.string(date: seconds - 5 * 60, now: now, calendar: calendar)
                    == L10n.telegramPlural("Time.MinutesAgo", count: 5),
                "minutes ago",
            )
            try require(
                StoryTimestamp.string(date: seconds - 3 * 3600, now: now, calendar: calendar)
                    == L10n.telegramPlural("Time.HoursAgo", count: 3),
                "hours ago",
            )
            let yesterday = StoryTimestamp.string(date: seconds - 16 * 3600, now: now, calendar: calendar)
            try require(
                yesterday.hasPrefix(L10n.telegram("Time.YesterdayAt", "").trimmingCharacters(in: .whitespaces)),
                "yesterday: \(yesterday)",
            )
        }

        private static func verifyNeighbors() throws {
            var state = try make(
                [
                    .init(chatID: 1, storyIDs: [1, 2]),
                    .init(chatID: 2, storyIDs: [5, 6, 7], maxReadStoryID: 5),
                    .init(chatID: 3),
                ],
                initialChatID: 1,
            )
            try require(state.neighbor(forward: false) == nil, "a neighbour before the first poster")
            try require(
                state.neighbor(forward: true) == .init(chatID: 2, storyID: 6, storyIndex: 1, storyCount: 3),
                "the next poster's face didn't show its first unseen story",
            )
            _ = state.movePoster(forward: true)
            _ = state.next()
            try require(
                state.neighbor(forward: true) == .init(chatID: 3, storyID: nil, storyIndex: 0, storyCount: 0),
                "an unloaded poster's face",
            )
            _ = state.movePoster(forward: false)
            try require(state.neighbor(forward: true)?.storyID == 7, "a poster's face didn't resume where it was left")
        }

        /// The cube's faces meet at the center half way through a turn, and a whole turn leaves a face just past
        /// the screen's edge with Telegram's 40 pt gap.
        private static func verifyCube() throws {
            let width = CGFloat(390)
            let sideAngle = StoryCubeGeometry.sideAngle(width: width, sideDistance: 40)
            func projectedX(_ x: CGFloat, rotation: CGFloat) -> CGFloat {
                let m = StoryCubeGeometry.transform(rotation: rotation, sideAngle: sideAngle, width: width)
                return (x * m.m11 + m.m41) / (x * m.m14 + m.m44)
            }
            try require(
                CATransform3DIsIdentity(StoryCubeGeometry.transform(rotation: 0, sideAngle: sideAngle, width: width)),
                "a face at rest isn't flat",
            )
            try require(
                abs(projectedX(-width / 2, rotation: 0.5)) < 0.5 && abs(projectedX(width / 2, rotation: -0.5)) < 0.5,
                "faces don't meet half way through a turn",
            )
            try require(
                abs(projectedX(-width / 2, rotation: 1) - width / 2) < 0.5
                    && abs(projectedX(width / 2, rotation: 1) - width / 2 - 40) < 0.5,
                "a whole turn doesn't leave the face past the edge with a 40 pt gap",
            )
            try require(abs(StoryCubeGeometry.rubberBand(300) - 100) < 0.01, "rubber band")
            try require(
                StoryCubeGeometry.springProgress(0) == 0 && StoryCubeGeometry.springProgress(1) == 1
                    && StoryCubeGeometry.springProgress(0.5) > 0.97,
                "spring curve",
            )
        }

        /// Story areas sit by their percentages, a tap hits a turned area a tenth larger than it, the story's sides
        /// and reactions take no area taps, the tooltip points at the area's center, and weather reads in the
        /// locale's unit.
        private static func verifyAreas() throws {
            let size = CGSize(width: 400, height: 800)
            let centered = AreaPosition(
                xPercentage: 50,
                yPercentage: 50,
                widthPercentage: 20,
                heightPercentage: 10,
                rotationAngle: 30,
                cornerRadiusPercentage: 10,
            )
            let placement = StoryAreaGeometry.placement(of: centered, in: size)
            try require(
                placement?.frame == CGRect(x: 160, y: 360, width: 80, height: 80)
                    && placement.map { abs($0.rotation - .pi / 6) < 0.0001 && $0.cornerRadius == 8 } == true,
                "an area's placement",
            )
            let tiny = AreaPosition(
                xPercentage: 50,
                yPercentage: 50,
                widthPercentage: 1,
                heightPercentage: 1,
                rotationAngle: 0,
                cornerRadiusPercentage: 0,
            )
            try require(StoryAreaGeometry.placement(of: tiny, in: size) == nil, "an area under 5 pt was drawn")

            let bar = AreaPosition(
                xPercentage: 50,
                yPercentage: 50,
                widthPercentage: 50,
                heightPercentage: 2.5,
                rotationAngle: 90,
                cornerRadiusPercentage: 0,
            )
            try require(
                StoryAreaGeometry.contains(CGPoint(x: 200, y: 505), position: bar, in: size)
                    && !StoryAreaGeometry.contains(CGPoint(x: 280, y: 400), position: bar, in: size),
                "a turned area's hit test",
            )

            let location = Location(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 0)
            let edge = AreaPosition(
                xPercentage: 5,
                yPercentage: 50,
                widthPercentage: 10,
                heightPercentage: 10,
                rotationAngle: 0,
                cornerRadiusPercentage: 0,
            )
            let reaction = TDNativeStoryAreaTypeSuggestedReaction(
                reactionType: .reactionTypeEmoji(TDNativeReactionTypeEmoji(emoji: "❤")),
                totalCount: 3,
                isDark: false,
                isFlipped: false,
            )
            let areas = [
                StoryArea(
                    position: centered,
                    type: .storyAreaTypeLocation(TDNativeStoryAreaTypeLocation(location: location, address: nil)),
                ),
                StoryArea(position: centered, type: .storyAreaTypeSuggestedReaction(reaction)),
                StoryArea(position: edge, type: .storyAreaTypeLink(TDNativeStoryAreaTypeLink(url: "telegram.org"))),
            ]
            try require(
                StoryAreaGeometry.area(at: CGPoint(x: 200, y: 400), in: size, areas: areas) == 0,
                "a reaction over a location took the tap",
            )
            try require(
                StoryAreaGeometry.area(at: CGPoint(x: 20, y: 400), in: size, areas: areas) == nil,
                "an area at the story's side took a navigation tap",
            )
            let source = StoryAreaGeometry.tooltipSource(of: centered, in: size)
            try require(
                source.midX == 200 && source.width == 16 && abs(source.height - 88) < 0.001,
                "the tooltip's source",
            )

            let celsius = StoryWeatherFormat.temperature(21.4, locale: Locale(identifier: "de_DE"))
            let fahrenheit = StoryWeatherFormat.temperature(21.4, locale: Locale(identifier: "en_US"))
            try require(celsius == "21°C" && fahrenheit == "71°F", "temperature: \(celsius), \(fahrenheit)")
        }

        /// performOtherMoreAction's items: notifications for contacts, Copy Link for a public story of a poster with
        /// a username, Share for a public forwardable story, Hide for stories in the main list and Unhide for
        /// hidden ones, Save for a forwardable story and Report for anyone but a service account; a bot's previews
        /// have no menu, and the account's own or editable stories have no button.
        private static func verifyMenuItems() throws {
            func poster(
                _ kind: StoryMoreMenu.Poster.Kind,
                isService: Bool = false,
                username: String? = "probe",
                isMuted: Bool = false,
                isHidden: Bool = false,
                canBeArchived: Bool = true,
            ) -> StoryMoreMenu.Poster {
                StoryMoreMenu.Poster(
                    chatID: 1,
                    title: "Probe",
                    compactTitle: "Probe",
                    kind: kind,
                    isService: isService,
                    username: username,
                    storiesMuted: isMuted,
                    storiesHidden: isHidden,
                    canBeArchived: canBeArchived,
                    accountIsPremium: false,
                )
            }
            func items(_ story: Story, _ poster: StoryMoreMenu.Poster) -> String {
                StoryMoreMenu.items(story: story, poster: poster)
.map(StoryMoreMenu.identifier(of:))
                    .joined(separator: ",")
            }
            let file = StoryViewerUIProbe.photoFile(id: 1, path: "", uniqueID: "menu")
            let open = StoryViewerUIProbe.makeStory(id: 1, chatID: 1, date: 0, file: file, areas: [])
            let contacts = TDNativeStoryPrivacySettings.storyPrivacySettingsContacts(
                TDNativeStoryPrivacySettingsContacts(exceptUserIds: []),
            )
            let contactsOnly = StoryViewerUIProbe.makeStory(
                id: 2,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                privacy: contacts,
            )
            let protected = StoryViewerUIProbe.makeStory(
                id: 3,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                canBeForwarded: false,
            )
            let own = StoryViewerUIProbe.makeStory(id: 4, chatID: 1, date: 0, file: file, areas: [], canBeEdited: true)
            let contact = StoryMoreMenu.Poster.Kind.user(isContact: true, isBot: false)
            let stranger = StoryMoreMenu.Poster.Kind.user(isContact: false, isBot: false)
            try require(
                items(open, poster(contact)) == "notify-off,copy-link,share,hide,save,report",
                "a contact's menu: \(items(open, poster(contact)))",
            )
            try require(
                items(open, poster(contact, isMuted: true, isHidden: true))
                    == "notify-on,copy-link,share,unhide,save,report",
                "a muted contact with hidden stories",
            )
            try require(
                items(open, poster(stranger, username: nil)) == "share,hide,save,report",
                "someone without a username who isn't a contact",
            )
            try require(items(open, poster(stranger, isService: true)) == "share,save", "a service account")
            try require(items(open, poster(.user(isContact: true, isBot: true))).isEmpty, "a bot's menu")
            try require(
                items(contactsOnly, poster(.supergroup, canBeArchived: false)) == "save,report",
                "a story for contacts in a channel that can't be hidden",
            )
            try require(items(protected, poster(.supergroup)) == "copy-link,hide,report", "a protected story")
            try require(
                StoryMoreMenu.items(story: open, poster: poster(contact), sharesFromPanel: true)
                    .map(StoryMoreMenu.identifier(of:)) == ["notify-off", "copy-link", "hide", "save", "report"],
                "Share stayed in the menu beside the reply panel's share button",
            )
            let size = PhotoSize(type: "y", photo: file, width: 720, height: 1280, progressiveSizes: [])
            let video = TDNativeStoryVideo(
                duration: 5,
                width: 720,
                height: 1280,
                hasStickers: false,
                isAnimation: false,
                minithumbnail: nil,
                thumbnail: nil,
                preloadPrefixSize: 0,
                coverFrameTimestamp: 0,
                video: size.photo,
            )
            let videoStory = StoryViewerUIProbe.makeStory(
                id: 5,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                content: .storyContentVideo(TDNativeStoryContentVideo(video: video, alternativeVideo: nil)),
            )
            let speedItems = StoryMoreMenu.items(story: videoStory, poster: poster(stranger), baseRate: 1.5)
            try require(
                speedItems.first == .speed(rate: 1.5) && StoryMoreMenu.speedTitle(1.5) == "1.5x"
                    && StoryMoreMenu.speedTitle(1) == L10n.telegram("PlaybackSpeed.Normal"),
                "a video story's speed: \(items(videoStory, poster(stranger)))",
            )
            let captioned = StoryViewerUIProbe.makeStory(
                id: 6,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                caption: "Hola, ¿cómo estás?",
            )
            let translated = StoryMoreMenu.items(story: captioned, poster: poster(contact)) { _ in "es" }
                .map(StoryMoreMenu.identifier(of:))
            let untranslated = StoryMoreMenu.items(story: captioned, poster: poster(contact)) { _ in nil }
                .map(StoryMoreMenu.identifier(of:))
            try require(
                translated.suffix(2) == ["translate", "report"] && !untranslated.contains("translate")
                    && !items(open, poster(contact)).contains("translate"),
                "a caption to translate: \(translated)",
            )
            try require(
                StoryMoreMenu.showsButton(for: open, accountUserID: 2) && !StoryMoreMenu.showsButton(
                    for: own,
                    accountUserID: 2,
                )
                    && !StoryMoreMenu.showsButton(for: nil, accountUserID: 2),
                "the More button on an editable story someone else posted",
            )
        }

        /// performMyMoreAction's items and StoryFooterPanelComponent's counts on the account's own story: Save to or
        /// Remove from Profile and Save to Gallery, then Copy Link and Share for a public story that's active or on the
        /// profile; a live stream keeps only the links and has no footer; the footer reads the reactions and reposts
        /// only once the story has views.
        /// StoryItemSetViewListComponent's header and empty-state rules, the rows' subtitles and the mapping of
        /// TDLib's interactions.
        private static func verifyViewList() throws {
            let file = StoryViewerUIProbe.photoFile(id: 1, path: "", uniqueID: "view-list")
            func story(
                views: Int,
                reactions: Int,
                privacy: TDNativeStoryPrivacySettings = .storyPrivacySettingsEveryone(
                    TDNativeStoryPrivacySettingsEveryone(exceptUserIds: []),
                ),
                expired: Bool = false,
            ) -> Story {
                StoryViewerUIProbe.makeStory(
                    id: 1,
                    chatID: 7,
                    date: 0,
                    file: file,
                    areas: [],
                    privacy: privacy,
                    own: (
                        isPosted: false,
                        interactions: views == 0
                            ? nil
                            : TDNativeStoryInteractionInfo(
                                viewCount: views,
                                forwardCount: 0,
                                reactionCount: reactions,
                                recentViewerUserIds: [],
                            ),
                    ),
                    hasExpiredViewers: expired,
                )
            }
            typealias Header = StoryViewList.Header
            let few = StoryViewList.header(story: story(views: 5, reactions: 2), totalCount: nil)
            try require(
                few == Header(
                    title: L10n.telegramPlural("Story.ViewList.ViewerCount", count: 5),
                    showsTabs: false,
                    showsSearch: false,
                    showsSort: false,
                ),
                "five viewers: \(few)",
            )
            let allReacted = StoryViewList.header(story: story(views: 3, reactions: 3), totalCount: 3)
            try require(allReacted.title == L10n.telegram("Story.ViewList.TitleViewers"), "all reacted: Viewers")
            let none = StoryViewList.header(story: story(views: 0, reactions: 0), totalCount: nil)
            try require(none.title == L10n.telegram("Story.ViewList.TitleEmpty"), "no views: \(none.title)")
            let many = StoryViewList.header(story: story(views: 20, reactions: 9), totalCount: nil)
            try require(many.showsTabs && many.showsSearch && !many.showsSort, "20 viewers: tabs and search")
            let sorted = StoryViewList.header(story: story(views: 30, reactions: 10), totalCount: 30)
            try require(sorted.showsSort, "10 reactions among 30 viewers: sort")
            let contactsOnly = StoryViewList.header(
                story: story(views: 30, reactions: 10, privacy: .storyPrivacySettingsCloseFriends),
                totalCount: 30,
            )
            try require(
                !contactsOnly.showsTabs && contactsOnly.showsSearch && contactsOnly.showsSort,
                "a close friends story: search and sort, no tabs",
            )
            let expired = StoryViewList.header(story: story(views: 30, reactions: 10, expired: true), totalCount: nil)
            try require(
                !expired.showsTabs && !expired.showsSearch && !expired.showsSort,
                "expired viewers: no tabs, search or sort",
            )

            var query = StoryViewList.Query()
            try require(
                StoryViewList.emptyText(query: query, story: story(views: 0, reactions: 0))
                    == L10n.telegram("Story.Views.NoViews"),
                "empty: no views yet",
            )
            try require(
                StoryViewList.emptyText(query: query, story: story(views: 4, reactions: 0, expired: true))
                    == L10n.telegram("Story.Views.ViewsExpired"),
                "empty: viewers expired",
            )
            query.listMode = .contacts
            try require(
                StoryViewList.emptyText(query: query, story: story(views: 4, reactions: 0))
                    == L10n.telegram("Story.ViewList.EmptyTextContacts"),
                "empty: no contacts",
            )
            query.text = "zz"
            try require(
                StoryViewList.emptyText(query: query, story: story(views: 4, reactions: 0))
                    == L10n.telegram("Story.ViewList.EmptyTextSearch"),
                "empty: search",
            )

            let now = Date()
            let time = now.formatted(date: .omitted, time: .shortened)
            let viewed = StoryViewList.Item(
                actor: .messageSenderUser(MessageSenderUser(userId: 11)),
                date: Int(now.timeIntervalSince1970),
                kind: .view(reaction: nil),
            )
            try require(
                StoryViewList.subtitle(for: viewed, now: now) == L10n.telegram(
                    "Chat.MessageSeenTimestamp.TodayAt",
                    time,
                ),
                "today's view: \(StoryViewList.subtitle(for: viewed, now: now))",
            )
            let yesterday = StoryViewList.Item(
                actor: viewed.actor,
                date: Int(now.timeIntervalSince1970) - 86400,
                kind: .repost(posterChatID: 11, storyID: 5, hasCaption: true),
            )
            try require(
                StoryViewList.subtitle(for: yesterday, now: now)
                    == L10n.telegram("Chat.MessageSeenTimestamp.YesterdayAt", time)
                    + L10n.telegram("Story.Views.Commented"),
                "yesterday's commented repost: \(StoryViewList.subtitle(for: yesterday, now: now))",
            )

            let page = StoryViewList.page(StoryInteractions(
                totalCount: 2,
                totalForwardCount: 0,
                totalReactionCount: 1,
                interactions: [
                    StoryInteraction(
                        actorId: .messageSenderUser(MessageSenderUser(userId: 11)),
                        interactionDate: 100,
                        blockList: nil,
                        type: .storyInteractionTypeView(TDNativeStoryInteractionTypeView(
                            chosenReactionType: .reactionTypeEmoji(ReactionTypeEmoji(emoji: "❤")),
                        )),
                    ),
                    StoryInteraction(
                        actorId: .messageSenderChat(MessageSenderChat(chatId: -100)),
                        interactionDate: 90,
                        blockList: nil,
                        type: .storyInteractionTypeView(TDNativeStoryInteractionTypeView(chosenReactionType: nil)),
                    ),
                ],
                nextOffset: "x",
            ))
            try require(
                page.items.map(\.actorID) == [11, -100] && page.nextOffset == "x" && page.totalReactionCount == 1,
                "page mapping: \(page.items.map(\.actorID))",
            )
            if case .view(.reactionTypeEmoji(let emoji)?) = page.items[0].kind {
                try require(emoji.emoji == "❤", "the chosen reaction")
            } else {
                throw Failure(description: "the first item lost its reaction")
            }

            // StoryItemSetContainerComponent's geometry on a 402 by 874 screen with the story at rest under the
            // status bar, and the drags' outcomes.
            typealias Layout = StoryViewListLayout
            let screen = CGSize(width: 402, height: 874)
            let resting = CGRect(x: 0, y: 62, width: 402, height: 715)
            try require(
                Layout.halfHeight(screenHeight: 874) == 537 && Layout.fullHeight(screenHeight: 874) == 814,
                "half and full heights",
            )
            let rest = Layout.layout(
                bounds: screen,
                safeBottom: 34,
                contentFrame: resting,
                listHeight: 0,
                footerSpacing: 10,
            )
            try require(
                rest.contentTransform == .identity && rest.expandFraction == 0 && rest.footerY == resting.maxY + 10
                    && rest.footerAlpha == 1,
                "the list hidden leaves the story alone: \(rest)",
            )
            let half = Layout.layout(
                bounds: screen,
                safeBottom: 34,
                contentFrame: resting,
                listHeight: 537,
                footerSpacing: 10,
            )
            try require(
                abs(half.contentScale - 275 / 715) < 0.001 && half.expandFraction == 1
                    && abs(half.footerY - (62 + 275 - 41)) < 0.5 && half.listFrame.minY == 337,
                "half: the story fits above the list: \(half)",
            )
            let full = Layout.layout(
                bounds: screen,
                safeBottom: 34,
                contentFrame: resting,
                listHeight: 814,
                footerSpacing: 10,
            )
            try require(full.footerAlpha < 0.01 && full.listFrame.minY == 60, "full: the footer fades: \(full)")
            func outcome(
                _ current: Layout.Display,
                _ height: CGFloat,
                _ translation: CGFloat,
                _ velocity: CGFloat,
                list: Bool = false,
            ) -> Layout.Display {
                Layout.display(
                    after: current,
                    listHeight: height,
                    translation: translation,
                    velocity: velocity,
                    screenHeight: 874,
                    fromList: list,
                )
            }
            try require(outcome(.hidden, 250, -250, 0) == .half, "a long swipe up opens half")
            try require(outcome(.hidden, 150, -150, -50) == .hidden, "a short slow swipe up doesn't open")
            try require(outcome(.hidden, 600, -600, 0) == .full, "past half the swipe opens it fully")
            try require(outcome(.half, 270, 267, 0) == .hidden, "30% down closes")
            try require(outcome(.half, 480, 57, 200) == .hidden, "a flick down closes")
            try require(outcome(.half, 600, -63, -20, list: true) == .full, "pulled up from the list opens fully")
            try require(outcome(.full, 700, 114, 0) == .half, "pulled down from full settles at half")

            typealias Menu = StoryViewList.MenuItem
            try require(
                StoryViewList.menuItems(isContact: true, blockList: nil) == [Menu.hideStories, .deleteContact],
                "a contact's menu",
            )
            try require(StoryViewList.menuItems(isContact: false, blockList: nil) == [Menu.block], "a stranger's menu")
            try require(
                StoryViewList.menuItems(isContact: false, blockList: .blockListMain).isEmpty,
                "a blocked stranger has no menu",
            )
            try require(
                StoryViewList.menuItems(isContact: false, blockList: .blockListStories) == [Menu.showStories, .block],
                "a stranger kept from the stories",
            )
        }

        /// StoryFooterPanelComponent's channel footer: a channel's or a closed group's story, at least one view, the
        /// account's reaction counted, Share for a public channel's forwardable story, none for a live stream.
        private static func verifyChannelFooter() throws {
            let file = StoryViewerUIProbe.photoFile(id: 1, path: "", uniqueID: "channel-footer")
            let story = StoryViewerUIProbe.makeStory(id: 1, chatID: -1001, date: 0, file: file, areas: [])
            let channel = StoryFooterPanel.channelConfiguration(story: story, poster: .channel(isPublic: true))
            try require(
                channel?.isChannel == true && channel?.viewCount == 1 && channel?.canShare == true
                    && channel?.canDelete == false && channel?.recentViewerIDs == [],
                "a public channel's footer: \(String(describing: channel))",
            )
            try require(
                StoryFooterPanel.channelConfiguration(story: story, poster: .channel(isPublic: false))?
                    .canShare == false,
                "a private channel's story isn't shared",
            )
            try require(
                StoryFooterPanel.channelConfiguration(story: story, poster: .group(canWrite: false, isPublic: true))?
                    .isChannel == true,
                "a group the account can't write to",
            )
            try require(
                StoryFooterPanel.channelConfiguration(story: story, poster: .group(canWrite: true, isPublic: true))
                    == nil
                    && StoryFooterPanel.channelConfiguration(
                        story: story,
                        poster: .user(isBot: false, isService: false, isSelf: false),
                    ) == nil,
                "a writable group and a user have the reply panel instead",
            )
        }

        private static func verifyOwnStory() throws {
            let me = Int64(7)
            func poster(username: String? = "me", active: Set<Int> = [1, 2]) -> StoryMoreMenu.Poster {
                StoryMoreMenu.Poster(
                    chatID: me,
                    title: "Me",
                    compactTitle: "Me",
                    kind: .user(isContact: false, isBot: false),
                    isService: false,
                    isSelf: true,
                    username: username,
                    storiesMuted: false,
                    storiesHidden: false,
                    canBeArchived: false,
                    accountIsPremium: false,
                    activeStoryIDs: active,
                )
            }
            func items(_ story: Story, _ poster: StoryMoreMenu.Poster) -> String {
                StoryMoreMenu.items(story: story, poster: poster)
.map(StoryMoreMenu.identifier(of:))
                    .joined(separator: ",")
            }
            let file = StoryViewerUIProbe.photoFile(id: 1, path: "", uniqueID: "own")
            let views = TDNativeStoryInteractionInfo(
                viewCount: 5,
                forwardCount: 1,
                reactionCount: 2,
                recentViewerUserIds: [11, 12, 13, 14],
            )
            let active = StoryViewerUIProbe.makeStory(
                id: 1,
                chatID: me,
                date: 0,
                file: file,
                areas: [],
                own: (isPosted: false, interactions: views),
            )
            let pinned = StoryViewerUIProbe.makeStory(
                id: 2,
                chatID: me,
                date: 0,
                file: file,
                areas: [],
                own: (isPosted: true, interactions: nil),
            )
            try require(
                items(active, poster()) == "save-to-profile,save,copy-link,share",
                "the own story's menu: \(items(active, poster()))",
            )
            try require(
                items(pinned, poster(active: [])) == "remove-from-profile,save,copy-link,share",
                "an expired story on the profile",
            )
            try require(
                items(active, poster(active: [])) == "save-to-profile,save",
                "an expired story not on the profile has no link",
            )
            try require(items(active, poster(username: nil)) == "save-to-profile,save", "no username, no link")
            let live = StoryViewerUIProbe.makeStory(
                id: 3,
                chatID: me,
                date: 0,
                file: file,
                areas: [],
                content: .storyContentLive(TDNativeStoryContentLive(groupCallId: 1, isRtmpStream: false)),
                own: (isPosted: false, interactions: nil),
            )
            try require(items(live, poster(active: [3])) == "copy-link,share", "an own live stream")
            try require(
                StoryMoreMenu.showsButton(for: active, accountUserID: me)
                    && StoryMoreMenu.isOwn(active, accountUserID: me)
                    && !StoryMoreMenu.isOwn(active, accountUserID: nil),
                "the More button on the account's own story",
            )
            let footer = StoryFooterPanel.configuration(story: active, isOwn: true)
            try require(
                footer == StoryFooterPanel.Configuration(
                    viewCount: 5,
                    reactionCount: 2,
                    forwardCount: 1,
                    recentViewerIDs: [11, 12, 13],
                    canDelete: true,
                ),
                "the footer's counts: \(String(describing: footer))",
            )
            let unseen = TDNativeStoryInteractionInfo(
                viewCount: 0,
                forwardCount: 1,
                reactionCount: 1,
                recentViewerUserIds: [],
            )
            let noViews = StoryViewerUIProbe.makeStory(
                id: 4,
                chatID: me,
                date: 0,
                file: file,
                areas: [],
                own: (isPosted: false, interactions: unseen),
            )
            let empty = StoryFooterPanel.configuration(story: noViews, isOwn: true)
            try require(
                empty?.viewCount == 0 && empty?.reactionCount == 0 && empty?.forwardCount == 0
                    && StoryFooterPanel.configuration(story: active, isOwn: false) == nil
                    && StoryFooterPanel.configuration(story: live, isOwn: true) == nil,
                "a story without views, someone else's story and a live stream",
            )
            // The language pack's "|%d| Views": the count between the bars goes, the words after them stay.
            let label = StoryFooterPanel.viewsLabel(count: 3)
            let plural = L10n.telegramPlural("Story.Footer.ViewCount", count: 3)
            try require(
                StoryFooterPanel.viewsLabel(count: 0) == L10n.telegram("Story.Footer.NoViews")
                    && !label.contains("|") && !label.contains("3") && !label.isEmpty && plural.hasSuffix(label),
                "the views label: \(label) from \(plural)",
            )
            try require(
                StoryFooterPanel.countText(999) == "999" && StoryFooterPanel.countText(1250) == "1.2K"
                    && StoryFooterPanel.countText(2000) == "2K" && StoryFooterPanel.countText(3_400_000) == "3.4M",
                "countString: \(StoryFooterPanel.countText(1250))",
            )
        }

        /// StoryItemSetContainerComponent's input panel: a private reply under a user's story and a comment under a
        /// group's where the account may write, Telegram's disabled placeholder for a service account's story and one
        /// that takes no reply, and none under the account's own, a bot's or a channel's story.
        private static func verifyReplyPanel() throws {
            let file = StoryViewerUIProbe.photoFile(id: 1, path: "", uniqueID: "reply")
            let open = StoryViewerUIProbe.makeStory(id: 1, chatID: 1, date: 0, file: file, areas: [])
            let contactsOnly = StoryViewerUIProbe.makeStory(
                id: 2,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                privacy: .storyPrivacySettingsContacts(TDNativeStoryPrivacySettingsContacts(exceptUserIds: [])),
            )
            let closed = StoryViewerUIProbe.makeStory(
                id: 3,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                canBeReplied: false,
            )
            let live = StoryViewerUIProbe.makeStory(
                id: 4,
                chatID: 1,
                date: 0,
                file: file,
                areas: [],
                content: .storyContentLive(TDNativeStoryContentLive(groupCallId: 1, isRtmpStream: false)),
            )
            func panel(_ story: Story, _ poster: StoryReplyPanel.Poster) -> StoryReplyPanel.Configuration? {
                StoryReplyPanel.configuration(story: story, poster: poster)
            }
            let user = StoryReplyPanel.Poster.user(isBot: false, isService: false, isSelf: false)
            let privately = StoryReplyPanel.Configuration.Field
                .input(placeholder: L10n.telegram("Story.InputPlaceholderReplyPrivately"))
            let unavailable = StoryReplyPanel.Configuration.Field
                .disabled(L10n.telegram("Story.FooterReplyUnavailable"))
            let userPanel = panel(open, user)
            try require(
                userPanel?.field == privately && userPanel?.showsLike == true && userPanel?.offersLikeOptions == true
                    && userPanel?.showsForward == true && userPanel?.isGroup == false,
                "a user's public story: \(String(describing: userPanel))",
            )
            try require(panel(contactsOnly, user)?.showsForward == false, "a story for contacts offered sharing")
            try require(panel(closed, user)?.field == unavailable, "a story that takes no reply took one")
            let service = panel(open, .user(isBot: false, isService: true, isSelf: false))
            try require(
                service?.field == unavailable && service?.showsLike == false && service?.offersLikeOptions == false,
                "a service account's story",
            )
            try require(panel(open, .user(isBot: true, isService: false, isSelf: false)) == nil, "a bot's story")
            try require(panel(open, .user(isBot: false, isService: false, isSelf: true)) == nil, "the account's story")
            let group = panel(open, .group(canWrite: true, isPublic: false))
            try require(
                group?.field == .input(placeholder: L10n.telegram("Story.InputPlaceholderReplyInGroup"))
                    && group?.isGroup == true && group?.showsLike == true && group?.offersLikeOptions == false,
                "a group's story: \(String(describing: group))",
            )
            try require(
                panel(open, .group(canWrite: false, isPublic: false)) == nil,
                "a group the account can't write to",
            )
            try require(panel(open, .channel(isPublic: true)) == nil, "a channel's story")
            let livePanel = panel(live, user)
            try require(
                livePanel?.field == unavailable && livePanel?.showsLike == false && livePanel?.showsForward == false,
                "a live stream",
            )
            let heart = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: "❤"))
            let custom = ReactionType.reactionTypeCustomEmoji(TDNativeReactionTypeCustomEmoji(customEmojiId: 5))
            try require(
                StoryReplyPanel.messageText(for: heart, sticker: nil) == FormattedText(entities: [], text: "❤")
                    && StoryReplyPanel.messageText(for: custom, sticker: nil) == nil,
                "a reaction's message text",
            )
        }
    }
#endif
