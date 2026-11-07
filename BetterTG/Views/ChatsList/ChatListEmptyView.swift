// ChatListEmptyView.swift

import Lottie
import UIKit

// MARK: - ChatListEmptyView

/// ChatListEmptyNode: its animation played once at 124 pt, the title in 17 pt semibold 24 pt under it, a note in 14 pt
/// 8 pt lower, and the button, a 52 pt glass capsule up to 270 pt wide, 20 pt above the list's bottom. `.filter` is an
/// empty folder ("Folder is empty.", Edit Folder), `.chats` an empty main list ("You have no conversations yet." or,
/// with archived chats, "All of your chats are archived.", and New Message). Where the content doesn't fit, the
/// animation fades and the text moves up, as Telegram lays it out.
final class ChatListEmptyView: UIView {
    enum Subject {
        case filter(showsEdit: Bool)
        case chats(hasArchive: Bool)
    }

    private static let animationSide: CGFloat = 124

    /// Edit Folder or New Message.
    var onAction: (() -> Void)?
    /// The list's bars, which the content keeps clear of.
    var insets = UIEdgeInsets.zero {
        didSet { setNeedsLayout() }
    }

    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic, decodingStrategy: .legacyCodable,
    ))
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let button = UIButton(configuration: .prominentGlass())

    init(subject: Subject) {
        super.init(frame: .zero)
        let animationName: String
        let title: String
        let note: String?
        let buttonTitle: String?
        switch subject {
        case .filter(let showsEdit):
            animationName = "ChatListFilterEmpty"
            title = L10n.telegram("ChatList.EmptyChatListFilterTitle")
            note = L10n.telegram("ChatList.EmptyChatListFilterText")
            buttonTitle = showsEdit ? L10n.telegram("ChatList.EmptyChatListEditFilter") : nil
        case .chats(let hasArchive):
            animationName = "ChatListEmpty"
            title = L10n.telegram(hasArchive ? "ChatList.EmptyChatListWithArchive" : "ChatList.EmptyChatList")
            note = nil
            buttonTitle = L10n.telegram("ChatList.EmptyChatListNewMessage")
        }
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .playOnce
        animationView.isUserInteractionEnabled = true
        animationView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(replay)))
        if let path = Bundle.main.path(forResource: animationName, ofType: "tgs") {
            Task { [weak self] in
                guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
                animationView.animation = animation
                animationView.play()
            }
        }
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        textLabel.text = note
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        button.configuration?.attributedTitle = AttributedString(
            buttonTitle ?? "",
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]),
        )
        button.configuration?.cornerStyle = .capsule
        button.addTarget(self, action: #selector(editPressed), for: .touchUpInside)
        button.isHidden = buttonTitle == nil
        for view in [animationView, titleLabel, textLabel, button] as [UIView] {
            addSubview(view)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let available = bounds.height - insets.top - insets.bottom
        let textWidth = width - 40
        let titleSize = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let textSize = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let buttonHeight: CGFloat = 52
        let animationSpacing: CGFloat = 24
        let contentHeight = Self.animationSide + animationSpacing + titleSize.height + buttonHeight
        let contentOffset: CGFloat
        if available < contentHeight {
            contentOffset = -Self.animationSide - animationSpacing + 44
            animationView.alpha = 0
        } else {
            contentOffset = -40
            animationView.alpha = 1
        }
        let animationFrame = CGRect(
            x: ((width - Self.animationSide) / 2).rounded(.down),
            y: insets.top + ((available - contentHeight) / 2).rounded(.down) + contentOffset,
            width: Self.animationSide,
            height: Self.animationSide,
        )
        animationView.frame = animationFrame
        titleLabel.frame = CGRect(
            x: ((width - titleSize.width) / 2).rounded(.down), y: animationFrame.maxY + animationSpacing,
            width: titleSize.width, height: titleSize.height,
        )
        textLabel.frame = CGRect(
            x: ((width - textSize.width) / 2).rounded(.down), y: titleLabel.frame.maxY + 8,
            width: textSize.width, height: textSize.height,
        )
        let buttonWidth = min(270, width - 64)
        button.frame = CGRect(
            x: ((width - buttonWidth) / 2).rounded(.down),
            y: bounds.height - insets.bottom - buttonHeight - 20,
            width: buttonWidth,
            height: buttonHeight,
        )
    }

    @objc private func replay() {
        guard !animationView.isAnimationPlaying else { return }
        animationView.play()
    }

    @objc private func editPressed() {
        onAction?()
    }
}

// MARK: - ChatListArchiveEmptyView

/// ChatListEmptyNode's `.archive`: ArchiveInfoContentComponent 16 pt in from the sides, centred 50 pt above the middle
/// of the space under the bars and at least 20 pt below them.
final class ChatListArchiveEmptyView: UIView {
    /// The list's bars, which the content keeps clear of.
    var insets = UIEdgeInsets.zero {
        didSet { setNeedsLayout() }
    }

    let content: ArchiveInfoContentView

    init(keepsUnmutedArchived: Bool, openSettings: @escaping () -> Void) {
        self.content = ArchiveInfoContentView(keepsUnmutedArchived: keepsUnmutedArchived, openSettings: openSettings)
        super.init(frame: .zero)
        addSubview(content)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - 32
        let height = content.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        .height
        let available = bounds.height - insets.top - insets.bottom
        let y = insets.top + max(20, ((available - height - 50) / 2).rounded(.down))
        content.frame = CGRect(x: 16, y: y, width: width, height: height)
    }
}
