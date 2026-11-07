// NewSessionInfoViewController.swift

import Lottie
import UIKit

// MARK: - NewSessionInfoViewController

/// NewSessionInfoScreen after No, it's not me!: the warning never to send the login code in red on a red tint, the
/// SessionReviewIcon animation on an accent circle, New Login Prevented, the device and place in bold, and Got it,
/// which counts down from 5 before it closes the sheet.
final class NewSessionInfoViewController: UIViewController {
    private static let sideInset: CGFloat = 16

    private let review: UnconfirmedSessionStore.Review
    private let noticeBackground = UIView()
    private let noticeLabel = UILabel()
    private let iconBackground = UIView()
    private let iconView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic, decodingStrategy: .legacyCodable,
    ))
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let button = UIButton(configuration: .prominentGlass())
    private var remaining = 5
    private var timer: Timer?

    init(review: UnconfirmedSessionStore.Review) {
        self.review = review
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        isModalInPresentation = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        noticeBackground.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        noticeBackground.layer.cornerRadius = 22
        noticeBackground.layer.cornerCurve = .continuous
        noticeLabel.text = L10n.telegram("SessionReview.NoticeText")
        noticeLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        noticeLabel.textColor = .systemRed
        noticeLabel.textAlignment = .center
        noticeLabel.numberOfLines = 0
        iconBackground.backgroundColor = .tintColor
        iconBackground.layer.cornerRadius = 45
        iconView.contentMode = .scaleAspectFit
        iconView.loopMode = .playOnce
        titleLabel.text = L10n.telegram("SessionReview.Title")
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        textLabel.attributedText = Self.text(L10n.telegram("SessionReview.Text", review.device, review.location))
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        button.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        for subview in [noticeBackground, noticeLabel, iconBackground, iconView, titleLabel, textLabel, button] {
            view.addSubview(subview)
        }
        updateButton()
        if let path = Bundle.main.path(forResource: "SessionReviewIcon", ofType: "tgs") {
            Task { [weak self] in
                guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
                iconView.animation = animation
                if view.window != nil { iconView.play() }
            }
        }
        sheetPresentationController?.detents = [.custom { [weak self] _ in self?.contentHeight() }]
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if iconView.animation != nil, !iconView.isAnimationPlaying { iconView.play() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout(width: view.bounds.width)
    }

    /// SessionReview.Text with its `**…**` parts semibold.
    private static func text(_ string: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in string.components(separatedBy: "**").enumerated() {
            result.append(NSAttributedString(string: part, attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: index % 2 == 1 ? .semibold : .regular),
                .foregroundColor: UIColor.label,
            ]))
        }
        return result
    }

    /// NewSessionInfoScreen's 30 pt above the content, the content, 30 pt, then Got it over the bottom inset.
    @discardableResult private func layout(width: CGFloat) -> CGFloat {
        let side = Self.sideInset
        let contentWidth = max(1, width - side * 2)
        var y: CGFloat = 30 - 14
        let noticeSize = noticeLabel.sizeThatFits(CGSize(width: contentWidth - 32, height: .greatestFiniteMagnitude))
        noticeBackground.frame = CGRect(x: side, y: y, width: contentWidth, height: noticeSize.height + 24)
        noticeLabel.frame = CGRect(
            x: side + floor((contentWidth - noticeSize.width) / 2), y: y + 12,
            width: noticeSize.width, height: noticeSize.height,
        )
        y = noticeBackground.frame.maxY + 24
        iconBackground.frame = CGRect(x: floor((width - 90) / 2), y: y, width: 90, height: 90)
        iconView.frame = iconBackground.frame.insetBy(dx: 10, dy: 10)
        y += 90 + 16
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height
        titleLabel.frame = CGRect(x: side, y: y, width: contentWidth, height: titleHeight)
        y += titleHeight + 16
        let textHeight = textLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height
        textLabel.frame = CGRect(x: side, y: y, width: contentWidth, height: textHeight)
        y += textHeight + 1 + 30
        let bottom = max(view.safeAreaInsets.bottom, 16)
        button.frame = CGRect(x: 30, y: y, width: max(1, width - 60), height: 52)
        return y + 52 + bottom
    }

    private func contentHeight() -> CGFloat {
        layout(width: view.bounds.width)
    }

    private func tick() {
        remaining = max(0, remaining - 1)
        if remaining == 0 {
            timer?.invalidate()
            timer = nil
            isModalInPresentation = false
        }
        updateButton()
    }

    /// Got it, with the seconds left beside it at half strength while it waits.
    private func updateButton() {
        var configuration = button.configuration ?? .prominentGlass()
        let title = NSMutableAttributedString(
            string: L10n.telegram("SessionReview.OkAction"),
            attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)],
        )
        if remaining > 0 {
            title.append(NSAttributedString(string: " \(remaining)", attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5),
            ]))
        }
        configuration.attributedTitle = AttributedString(title)
        button.configuration = configuration
        button.isEnabled = remaining == 0
    }
}
