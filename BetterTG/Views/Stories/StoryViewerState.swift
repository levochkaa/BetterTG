// StoryViewerState.swift

import Foundation

// MARK: - StoryViewerState

/// The story viewer's position and timing, without UIKit or TDLib, so a debug probe can drive it offline. It follows
/// StoryContainerScreen.navigate: a tap past the last story opens the next poster or closes the viewer, a tap back from
/// the first story opens the previous poster or rewinds (rewindCurrentItem), and a poster reopens where it was left
/// (StoryContentContextImpl's focused item). A photo plays for five seconds (StoryItemContentComponent's
/// currentProgressTimerLimit) and a video for its own duration; the clock waits until the media shows.
struct StoryViewerState: Equatable {
    struct Poster: Equatable {
        let chatID: Int64
        /// The poster's stories in chronological order; nil until its active stories load.
        var storyIDs: [Int]?
        /// Where the set opens: the first story after the last read one, or the first once all were read.
        var entryIndex = 0

        init(chatID: Int64, storyIDs: [Int]? = nil, maxReadStoryID: Int = 0) {
            self.chatID = chatID
            self.storyIDs = storyIDs
            self.entryIndex = storyIDs.map { Self.entryIndex(in: $0, maxReadStoryID: maxReadStoryID) } ?? 0
        }

        static func entryIndex(in storyIDs: [Int], maxReadStoryID: Int) -> Int {
            storyIDs.firstIndex { $0 > maxReadStoryID } ?? 0
        }
    }

    enum PauseReason: Hashable {
        /// A press held on the story (Telegram's long press pauses and hides the interface).
        case hold
        /// The dismissal or poster drag is in progress.
        case drag
        /// The caption is expanded.
        case caption
        /// The app or the viewer is inactive.
        case inactive
        /// A video waits for data.
        case buffering
        /// A story area's tooltip is open (activateMediaArea's menu controller).
        case menu
        /// The More menu is open (performOtherMoreAction's context controller).
        case moreMenu
        /// A screen is presented over the viewer, such as a story area's location.
        case presentation
        /// The reply field edits, or reactions show over the story (updateIsProgressPaused's input and reaction
        /// context).
        case reply
        #if DEBUG
            /// The UI probe holds the story still for its screenshots.
            case probe
        #endif
    }

    enum Transition: Equatable {
        case none
        /// Another story of the same poster.
        case story
        /// Another poster; `forward` is the direction of the move.
        case poster(forward: Bool)
        /// The shown story starts over.
        case rewind
        case dismiss
    }

    /// A poster beside the current one and the story it would open at, which the cube's side face shows.
    struct Neighbor: Equatable {
        let chatID: Int64
        /// Nil while the poster's stories load.
        let storyID: Int?
        let storyIndex: Int
        let storyCount: Int
    }

    static let photoDuration: TimeInterval = 5

    private(set) var posters: [Poster]
    private(set) var posterIndex: Int
    private(set) var storyIndex: Int
    /// The shown story's played time.
    private(set) var elapsed: TimeInterval = 0
    /// Nil until the shown story's media is ready.
    private(set) var duration: TimeInterval?
    private(set) var pauseReasons = Set<PauseReason>()

    /// Where each visited poster was left, so returning to it resumes there.
    private var resumeIndices = [Int64: Int]()

    var currentChatID: Int64 {
        posters[posterIndex].chatID
    }

    /// Nil while the current poster's stories load.
    var currentStoryID: Int? {
        guard let storyIDs = posters[posterIndex].storyIDs, storyIDs.indices.contains(storyIndex) else { return nil }
        return storyIDs[storyIndex]
    }

    var storyCount: Int {
        posters[posterIndex].storyIDs?.count ?? 0
    }

    /// The next story the viewer may show, for preloading.
    var upcoming: (chatID: Int64, storyID: Int?)? {
        if let storyIDs = posters[posterIndex].storyIDs, storyIndex + 1 < storyIDs.count {
            return (currentChatID, storyIDs[storyIndex + 1])
        }
        guard posterIndex + 1 < posters.count else { return nil }
        let poster = posters[posterIndex + 1]
        let index = resumeIndices[poster.chatID] ?? poster.entryIndex
        return (poster.chatID, poster.storyIDs.flatMap { $0.indices.contains(index) ? $0[index] : nil })
    }

    var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    var isRunning: Bool {
        duration != nil && pauseReasons.isEmpty
    }

    init?(posters: [Poster], initialChatID: Int64) {
        let posters = posters.filter { $0.storyIDs?.isEmpty != true }
        guard !posters.isEmpty else { return nil }
        let index = posters.firstIndex { $0.chatID == initialChatID } ?? 0
        self.posters = posters
        self.posterIndex = index
        self.storyIndex = posters[index].entryIndex
    }

    func neighbor(forward: Bool) -> Neighbor? {
        let index = posterIndex + (forward ? 1 : -1)
        guard posters.indices.contains(index) else { return nil }
        let poster = posters[index]
        guard let storyIDs = poster.storyIDs else {
            return Neighbor(chatID: poster.chatID, storyID: nil, storyIndex: 0, storyCount: 0)
        }
        // enterPoster's choice: where the poster was left, or its first unseen story.
        let resume = resumeIndices[poster.chatID].flatMap { storyIDs.indices.contains($0) ? $0 : nil }
        let storyIndex = resume ?? poster.entryIndex
        return Neighbor(
            chatID: poster.chatID,
            storyID: storyIDs.indices.contains(storyIndex) ? storyIDs[storyIndex] : nil,
            storyIndex: storyIndex,
            storyCount: storyIDs.count,
        )
    }

    mutating func setPaused(_ isPaused: Bool, for reason: PauseReason) {
        if isPaused {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
    }

    /// The shown story's media appeared; a video passes its duration.
    mutating func mediaDidBecomeReady(duration: TimeInterval) {
        self.duration = max(0.1, duration)
    }

    /// A photo's clock: advances while the viewer runs and moves on when the story ends.
    mutating func advance(by interval: TimeInterval) -> Transition {
        guard isRunning, let duration, interval > 0 else { return .none }
        elapsed = min(duration, elapsed + interval)
        return elapsed >= duration ? next() : .none
    }

    /// A video's clock follows its player.
    mutating func setElapsed(_ time: TimeInterval) {
        guard let duration else { return }
        elapsed = min(duration, max(0, time))
    }

    mutating func next() -> Transition {
        if storyIndex + 1 < storyCount {
            show(storyAt: storyIndex + 1)
            return .story
        }
        guard posterIndex + 1 < posters.count else { return .dismiss }
        enterPoster(at: posterIndex + 1)
        return .poster(forward: true)
    }

    mutating func previous() -> Transition {
        if storyIndex > 0, storyCount > 0 {
            show(storyAt: storyIndex - 1)
            return .story
        }
        guard posterIndex > 0 else {
            elapsed = 0
            return .rewind
        }
        enterPoster(at: posterIndex - 1)
        return .poster(forward: false)
    }

    /// A horizontal swipe: the neighbouring poster, or nothing past either end.
    mutating func movePoster(forward: Bool) -> Transition {
        let target = posterIndex + (forward ? 1 : -1)
        guard posters.indices.contains(target) else { return .none }
        enterPoster(at: target)
        return .poster(forward: forward)
    }

    /// A poster's active stories loaded or changed (getChatActiveStories, updateChatActiveStories). The shown story
    /// stays shown while it's still active; a removed one gives way to the story now at its place.
    mutating func updateStories(chatID: Int64, storyIDs: [Int], maxReadStoryID: Int) -> Transition {
        guard let index = posters.firstIndex(where: { $0.chatID == chatID }) else { return .none }
        guard !storyIDs.isEmpty else { return removePoster(at: index) }
        let previous = posters[index]
        posters[index].storyIDs = storyIDs
        posters[index].entryIndex = Poster.entryIndex(in: storyIDs, maxReadStoryID: maxReadStoryID)
        if let resume = resumeIndices[chatID], let previousIDs = previous.storyIDs,
           previousIDs.indices.contains(resume)
        {
            resumeIndices[chatID] = storyIDs.firstIndex(of: previousIDs[resume]) ?? min(resume, storyIDs.count - 1)
        }
        guard index == posterIndex else { return .none }
        guard let previousIDs = previous.storyIDs, previousIDs.indices.contains(storyIndex) else {
            // The poster's stories just loaded: open at the first unseen one.
            show(storyAt: min(resumeIndices[chatID] ?? posters[index].entryIndex, storyIDs.count - 1))
            return .story
        }
        let shownID = previousIDs[storyIndex]
        if let newIndex = storyIDs.firstIndex(of: shownID) {
            storyIndex = newIndex
            resumeIndices[chatID] = newIndex
            return .none
        }
        show(storyAt: min(storyIndex, storyIDs.count - 1))
        return .story
    }

    /// A story was deleted or can't be loaded (updateStoryDeleted, a failed getStory).
    mutating func removeStory(chatID: Int64, storyID: Int) -> Transition {
        guard let poster = posters.first(where: { $0.chatID == chatID }), let storyIDs = poster.storyIDs,
              storyIDs.contains(storyID) else { return .none }
        let readID = poster.entryIndex > 0 ? storyIDs[poster.entryIndex - 1] : 0
        return updateStories(chatID: chatID, storyIDs: storyIDs.filter { $0 != storyID }, maxReadStoryID: readID)
    }

    private mutating func removePoster(at index: Int) -> Transition {
        let chatID = posters[index].chatID
        resumeIndices[chatID] = nil
        guard posters.count > 1 else {
            posters[index].storyIDs = []
            return .dismiss
        }
        posters.remove(at: index)
        if index < posterIndex {
            posterIndex -= 1
            return .none
        }
        guard index == posterIndex else { return .none }
        guard index < posters.count else {
            posterIndex = posters.count - 1
            return .dismiss
        }
        enterPoster(at: index, recordingLeft: false)
        return .poster(forward: true)
    }

    private mutating func show(storyAt index: Int) {
        storyIndex = max(0, index)
        elapsed = 0
        duration = nil
        pauseReasons.remove(.buffering)
        resumeIndices[currentChatID] = storyIndex
    }

    private mutating func enterPoster(at index: Int, recordingLeft: Bool = true) {
        if recordingLeft { resumeIndices[currentChatID] = storyIndex }
        posterIndex = index
        let poster = posters[index]
        let resume = resumeIndices[poster.chatID].flatMap { resume in
            poster.storyIDs.map { $0.indices.contains(resume) ? resume : poster.entryIndex }
        }
        storyIndex = resume ?? poster.entryIndex
        elapsed = 0
        duration = nil
        pauseReasons.remove(.buffering)
    }
}

// MARK: - StoryTimestamp

/// Telegram's stringForStoryActivityTimestamp: just now, minutes or hours ago, yesterday at a time, or the date.
enum StoryTimestamp {
    static func string(date: Int, now: Date = .now, calendar: Calendar = .current) -> String {
        let storyDate = Date(timeIntervalSince1970: TimeInterval(date))
        let difference = Int(now.timeIntervalSince(storyDate))
        if difference < 60 { return L10n.telegram("Time.JustNow") }
        if difference < 60 * 60 {
            return L10n.telegramPlural("Time.MinutesAgo", count: difference / 60)
        }
        if calendar.isDate(storyDate, inSameDayAs: now) {
            return L10n.telegramPlural("Time.HoursAgo", count: difference / (60 * 60))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(storyDate, inSameDayAs: yesterday)
        {
            return L10n.telegram("Time.YesterdayAt", storyDate.formatted(date: .omitted, time: .shortened))
        }
        return storyDate.formatted(date: .numeric, time: .omitted)
    }
}
