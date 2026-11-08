// MessageFactCheckView.swift

import TDLibKit
import UIKit

// MARK: - MessageFactCheckView

/// ChatMessageFactCheckBubbleContentNode: a message's fact check under its text, in Telegram's scam red. A 3 pt bar
/// and a tinted block hold Fact Check in 14 pt semibold with its "what's this?" badge, which explains the check with
/// the country's name, then the check's text in 14 pt, four lines until a tap expands it.
final class MessageFactCheckView: UIView {
    private static let collapsedLines = 4
    private static let tint = UIColor.systemRed

    /// A tap on a clipped check asks for it in full.
    var onExpand: (() -> Void)?

    private let bar = UIView()
    private let titleLabel = UILabel()
    private let badgeButton = UIButton(type: .system)
    private let textLabel = UILabel()
    private var countryCode = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.tint.withAlphaComponent(0.1)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = Self.tint
        addSubview(bar)

        let fontSize = floor(UIFont.preferredFont(forTextStyle: .body).pointSize * 14 / 17)
        titleLabel.font = .systemFont(ofSize: fontSize, weight: .semibold)
        titleLabel.textColor = Self.tint
        titleLabel.text = L10n.telegram("Message.FactCheck")

        var badge = UIButton.Configuration.plain()
        var badgeTitle = AttributedString(L10n.telegram("Message.FactCheck.WhatIsThis"))
        badgeTitle.font = .systemFont(ofSize: floor(UIFont.preferredFont(forTextStyle: .body).pointSize * 11 / 17))
        badgeTitle.foregroundColor = Self.tint
        badge.attributedTitle = badgeTitle
        badge.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 5, bottom: 1, trailing: 5)
        badge.background.backgroundColor = Self.tint.withAlphaComponent(0.15)
        badge.background.cornerRadius = 8
        badgeButton.configuration = badge
        badgeButton.addTarget(self, action: #selector(badgePressed), for: .touchUpInside)

        textLabel.font = .systemFont(ofSize: fontSize)
        textLabel.textColor = .label
        textLabel.numberOfLines = Self.collapsedLines
        textLabel.isUserInteractionEnabled = true
        textLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(textTapped)))

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, badgeButton, UIView()])
        titleRow.alignment = .center
        titleRow.spacing = 5
        let stack = UIStackView(arrangedSubviews: [titleRow, textLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3
        addSubview(stack)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),
            stack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ factCheck: FactCheck, isExpanded: Bool) {
        countryCode = factCheck.countryCode
        textLabel.attributedText = NSAttributedString(getAttributedString(from: factCheck.text))
        textLabel.font = .systemFont(ofSize: floor(UIFont.preferredFont(forTextStyle: .body).pointSize * 14 / 17))
        textLabel.numberOfLines = isExpanded ? 0 : Self.collapsedLines
    }

    func prepareForReuse() {
        onExpand = nil
        textLabel.attributedText = nil
        textLabel.numberOfLines = Self.collapsedLines
    }

    /// displayMessageTooltip with Conversation.FactCheck.Description and the country's name.
    @objc private func badgePressed() {
        let country = Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode
        guard let host = window?.rootViewController?.view else { return }
        TelegramUndoToast.show(
            text: L10n.telegram("Conversation.FactCheck.Description", country),
            in: host,
            bottomInset: 80,
            undo: nil,
        )
    }

    /// The node's expand: a check longer than four lines opens on a tap.
    @objc private func textTapped() {
        guard textLabel.numberOfLines != 0, let text = textLabel.attributedText else { return }
        let full = text.boundingRect(
            with: CGSize(width: textLabel.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        )
        guard ceil(full.height) > textLabel.bounds.height + 1 else { return }
        onExpand?()
    }
}
