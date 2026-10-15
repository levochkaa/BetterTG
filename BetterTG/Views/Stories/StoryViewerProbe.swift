// StoryViewerProbe.swift

import Foundation

#if DEBUG
    /// Drives the story viewer's state offline (no TDLib, no UI): the clock waiting for media, holding, auto-advance,
    /// tap navigation across posters, rewinding, lazily loaded posters, active-story updates and deletions, and the
    /// header's time. Launch with `-ui-probe-story-viewer`; the result goes to the log and to
    /// Documents/story-viewer-probe.txt.
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
                result = "Story viewer probe passed: first-unseen-entry/clock-waits-for-media/hold-pause=true; "
                    + "auto-advance/next-poster/resume/rewind/dismiss=true; single-story=true; "
                    + "lazy-posters/empty-poster-dropped=true; active-update/delete/current-poster-removed=true; "
                    + "timestamps=true"
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
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
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
    }
#endif
