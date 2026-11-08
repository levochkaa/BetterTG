// ChatTranslationPanelView.swift

import UIKit

// MARK: - ChatTranslationPanelView

/// Telegram's TranslateHeaderPanelComponent (ChatTranslationPanelNode) in HeaderPanelContainerComponent's glass: a 40
/// pt capsule 16 pt from the sides with the translate icon and Translate to (the language) or Show Original in 17 pt
/// accent text at its centre, and the more button 11 pt from its right, whose menu chooses another language, adds the
/// chat's language to Do Not Translate, or hides the bar. The bar's space under it is the panel's too.
final class ChatTranslationPanelView: UIView {
    static let panelHeight = CGFloat(40)
    static let contentHeight = panelHeight + 8

    var onToggle: (() -> Void)?
    var onMore: ((UIView) -> Void)?

    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let button = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(glassView)
        let panel = glassView.contentView

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "translate",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular),
        )
        configuration.imagePadding = 10
        configuration.titleLineBreakMode = .byTruncatingTail
        // panelControlColor: the accent, which glass content otherwise draws in its own colour.
        configuration.baseForegroundColor = .systemBlue
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.onToggle?() }, for: .touchUpInside)
        panel.addSubview(button)

        moreButton.setImage(
            UIImage(systemName: "ellipsis.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)),
            for: .normal,
        )
        moreButton.tintColor = .systemBlue
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onMore?(moreButton)
        }, for: .touchUpInside)
        panel.addSubview(moreButton)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            glassView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.heightAnchor.constraint(equalToConstant: Self.panelHeight),
            button.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            button.topAnchor.constraint(equalTo: panel.topAnchor),
            button.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: panel.leadingAnchor, constant: 8),
            button.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor),
            moreButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -11),
            moreButton.centerYAnchor.constraint(equalTo: panel.centerYAnchor, constant: -1),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Show Original while the chat shows translations, otherwise Translate to the target language.
    func update(state: ChatTranslationState) {
        let title: String =
            if state.isEnabled {
                L10n.telegram("Conversation.Translation.ShowOriginal")
            } else {
                L10n.telegram(
                    "Conversation.Translation.TranslateTo",
                    MessageTranslation.languageName(state.effectiveToLang) ?? state.effectiveToLang,
                )
            }
        var attributed = AttributedString(title)
        attributed.font = .systemFont(ofSize: 17)
        button.configuration?.attributedTitle = attributed
    }
}
