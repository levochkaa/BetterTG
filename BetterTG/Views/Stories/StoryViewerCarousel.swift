// StoryViewerCarousel.swift

import TDLibKit
import UIKit

// MARK: - StoryCarouselLayout

/// StoryItemSetContainerComponent.ItemLayout/updateScrolling: 12 pt gaps and side cards 54 pt narrower
/// than the centred story. Fractions address stories in this poster, never the neighbouring poster.
enum StoryCarouselLayout {
    static func spacing(width: CGFloat, scale: CGFloat) -> CGFloat {
        max(1, width * scale - 27 + 12)
    }

    static func transform(
        content: CGRect, layout: StoryViewListLayout.Result, distance: CGFloat,
    ) -> CGAffineTransform {
        let centralWidth = content.width * layout.contentScale
        let sideWidth = max(1, centralWidth - 54 * layout.expandFraction)
        let fullDistance = centralWidth / 2 + 12 + sideWidth / 2
        let halfDistance = sideWidth + 12
        let magnitude = abs(distance)
        let x = (min(1, magnitude) * fullDistance + max(0, magnitude - 1) * halfDistance)
            * (distance < 0 ? -1 : 1)
        let scale = layout.contentScale - min(1, magnitude) * (centralWidth - sideWidth) / max(1, content.width)
        return CGAffineTransform(translationX: x, y: layout.contentTransform.ty).scaledBy(x: scale, y: scale)
    }

    static func destination(index: Int, count: Int, fraction: CGFloat, velocity: CGFloat, cancelled: Bool) -> Int {
        guard !cancelled else { return index }
        if fraction <= -0.3 || (fraction <= -0.05 && velocity <= -200) { return min(count - 1, index + 1) }
        if fraction >= 0.3 || (fraction >= 0.05 && velocity >= 200) { return max(0, index - 1) }
        return index
    }
}

// MARK: - StoryViewListCarousel

/// Live thumbnails around the current story; the controller keeps its real image/player and footer in front.
/// A transparent UIKit scroller supplies Telegram's continuous movement and snapping above the viewers list.
final class StoryViewListCarousel: UIView, UIScrollViewDelegate {
    private final class Scroller: UIScrollView {
        var adjust: ((Int) -> Void)?

        override func accessibilityIncrement() { adjust?(1) }
        override func accessibilityDecrement() { adjust?(-1) }
    }

    private final class Card: UIView {
        let image = TDImageLoadingView()
        let footer = StoryFooterPanelView()
        var requested = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(white: 0.1, alpha: 1)
            clipsToBounds = true
            layer.cornerCurve = .continuous
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            addSubview(image)
            footer.isUserInteractionEnabled = false
            footer.expandFraction = 1
        }

        @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

        func configure(_ story: Story, client: TDLibClient) {
            let origin = TDImageOrigin.captured(client: client)
            switch story.content {
            case .storyContentPhoto(let value):
                if let file = StoryMedia.photoFile(value.photo) {
                    image.load(
                        file: file,
                        placeholderData: value.photo.minithumbnail?.data,
                        maximumPixelSize: 2560,
                        origin: origin,
                    )
                } else {
                    image.loadPlaceholder(data: value.photo.minithumbnail?.data, origin: origin)
                }
            case .storyContentVideo(let value):
                if let thumbnail = value.video.thumbnail {
                    image.load(
                        file: thumbnail.file,
                        placeholderData: value.video.minithumbnail?.data,
                        maximumPixelSize: 1280,
                        origin: origin,
                    )
                } else {
                    image.loadPlaceholder(data: value.video.minithumbnail?.data, origin: origin)
                }
            case .storyContentLive,
                 .storyContentUnsupported: image.cancel()
            }
            footer.configure(
                StoryFooterPanel.configuration(story: story, isOwn: true),
                avatar: { _ in nil },
                client: client,
            )
        }
    }

    var onSelect: ((Int) -> Void)?
    var onMove: (() -> Void)?
    var onCloseList: (() -> Void)?
    var fetch: ((Int) async -> Story?)?

    private let scroller = Scroller()
    private var cards = [Int: Card]()
    private var tasks = [Int: Task<Void, Never>]()
    private var ids = [Int]()
    private var currentIndex = 0
    private var distance = CGFloat(1)
    private var ignoresScrolling = false
    private var listTop = CGFloat.zero
    private var position = CGFloat.zero
    private var animatingScroll = false

    var isMoving: Bool { scroller.isDragging || scroller.isDecelerating || animatingScroll }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        scroller.delegate = self
        scroller.backgroundColor = .clear
        scroller.showsHorizontalScrollIndicator = false
        scroller.showsVerticalScrollIndicator = false
        scroller.alwaysBounceHorizontal = true
        scroller.decelerationRate = .fast
        scroller.contentInsetAdjustmentBehavior = .never
        addSubview(scroller)
        scroller.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        scroller.isAccessibilityElement = true
        scroller.accessibilityTraits = .adjustable
        scroller.accessibilityLabel = L10n.telegram("Notifications.Stories")
        scroller.adjust = { [weak self] delta in
            guard let self, !ids.isEmpty else { return }
            onSelect?(max(0, min(ids.count - 1, currentIndex + delta)))
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, point.y < listTop else { return nil }
        return super.hitTest(point, with: event)
    }

    func update(
        ids: [Int], index: Int, content: CGRect, layout: StoryViewListLayout.Result,
        halfScale: CGFloat, listFraction: CGFloat?, liveStoryID: Int?, client: TDLibClient,
    ) -> CGAffineTransform {
        let oldIDs = self.ids
        self.ids = ids
        currentIndex = index
        listTop = layout.listFrame.minY
        let newDistance = StoryCarouselLayout.spacing(width: content.width, scale: halfScale)
        ignoresScrolling = true
        scroller.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, listTop))
        scroller.contentSize = CGSize(
            width: newDistance * CGFloat(max(0, ids.count - 1)) + bounds.width,
            height: scroller.bounds.height,
        )
        scroller.isScrollEnabled = layout.expandFraction >= 0.999 && ids.count > 1
        if oldIDs != ids || distance != newDistance || (!isMoving && listFraction == nil) {
            scroller.contentOffset.x = CGFloat(index) * newDistance
        }
        distance = newDistance
        position = listFraction.map { CGFloat(index) - $0 } ?? scroller.contentOffset.x / distance
        ignoresScrolling = false
        scroller.accessibilityValue = "\(index + 1)/\(ids.count)"
        let visible = Set(ids.enumerated().filter { abs(CGFloat($0.offset) - position) < 3 }.map(\.element))
        for id in Array(cards.keys) where !visible.contains(id) {
            if let card = cards.removeValue(forKey: id) {
                card.image.cancel()
                card.footer.removeFromSuperview()
                card.removeFromSuperview()
            }
            tasks.removeValue(forKey: id)?.cancel()
        }
        for (itemIndex, id) in ids.enumerated() where visible.contains(id) {
            let card: Card
            if let current = cards[id] { card = current }
            else {
                card = Card()
                cards[id] = card
                insertSubview(card, belowSubview: scroller)
                insertSubview(card.footer, belowSubview: scroller)
            }
            if !card.requested, let fetch {
                card.requested = true
                tasks[id] = Task { [weak self, weak card] in
                    let story = await fetch(id)
                    guard !Task.isCancelled, let self, let card, cards[id] === card else { return }
                    tasks[id] = nil
                    if let story { card.configure(story, client: client) }
                }
            }
            let transform = StoryCarouselLayout.transform(
                content: content,
                layout: layout,
                distance: CGFloat(itemIndex) - position,
            )
            card.bounds = CGRect(origin: .zero, size: content.size)
            card.center = CGPoint(x: content.midX, y: content.midY)
            card.image.frame = card.bounds
            card.transform = transform
            card.layer.cornerRadius = StoryChromeLayout.cornerRadius / max(0.01, transform.a)
            card.isHidden = id == liveStoryID
            card.footer.isHidden = card.isHidden
            let footerScale = transform.a / max(0.01, layout.contentScale)
            card.footer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: StoryFooterPanelView.height)
            card.footer.center = CGPoint(
                x: bounds.midX + transform.tx,
                y: content.midY + transform.ty + content.height * transform.a / 2 - 41
                    + StoryFooterPanelView.height * (2 - footerScale) / 2,
            )
            card.footer.transform = CGAffineTransform(scaleX: footerScale, y: footerScale)
            card.footer.accessibilityElementsHidden = true
            card.footer.alpha = layout.footerAlpha * layout.expandFraction
            card.alpha = layout.expandFraction
        }
        return StoryCarouselLayout.transform(content: content, layout: layout, distance: CGFloat(index) - position)
    }

    func stop() {
        ignoresScrolling = true
        animatingScroll = false
        scroller.setContentOffset(scroller.contentOffset, animated: false)
        ignoresScrolling = false
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        for card in cards.values {
            card.image.cancel()
            card.footer.removeFromSuperview()
            card.removeFromSuperview()
        }
        cards.removeAll()
        isHidden = true
    }

    func prepareToClose() {
        ignoresScrolling = true
        animatingScroll = false
        scroller.setContentOffset(CGPoint(x: CGFloat(currentIndex) * distance, y: 0), animated: false)
        ignoresScrolling = false
    }

    func updateStory(_ story: Story, client: TDLibClient) {
        tasks.removeValue(forKey: story.id)?.cancel()
        cards[story.id]?.requested = true
        cards[story.id]?.configure(story, client: client)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !ignoresScrolling, !ids.isEmpty else { return }
        position = scrollView.contentOffset.x / distance
        let index = max(0, min(ids.count - 1, Int(position.rounded())))
        if index != currentIndex { onSelect?(index) }
        onMove?()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        let x = targetContentOffset.pointee.x
        guard x > 0, x < scrollView.contentSize.width - scrollView.bounds.width else { return }
        targetContentOffset.pointee.x = (x / distance).rounded() * distance
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { snap() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) { snap() }

    func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
        animatingScroll = false
        onMove?()
    }

    func scrollViewWillBeginDragging(_: UIScrollView) { animatingScroll = false }

    private func snap() {
        let index = max(0, min(ids.count - 1, Int((scroller.contentOffset.x / distance).rounded())))
        scroll(to: index)
    }

    private func scroll(to index: Int) {
        guard !ids.isEmpty, abs(scroller.contentOffset.x - CGFloat(index) * distance) > 0.01 else {
            onMove?()
            return
        }
        animatingScroll = true
        scroller.setContentOffset(CGPoint(x: CGFloat(index) * distance, y: 0), animated: true)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let item = cards.first(where: { !$0.value.isHidden && $0.value.frame.contains(point) }),
           let index = ids.firstIndex(of: item.key)
        {
            scroll(to: index)
        } else { onCloseList?() }
    }
}
