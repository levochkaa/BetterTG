// TwoStepVerificationIntroViewController.swift

import Lottie
import UIKit

// MARK: - TwoStepVerificationIntroViewController

/// TwoFactorAuthSplashScreen's `.intro`, which Privacy and Security opens for an account without a password: the
/// TwoFactorSetupIntro animation played once at 124 pt, the bold 32 pt title 8 pt under it, the 16 pt text 19 pt under
/// that, 32 pt from the sides and centred a little above the middle, and the 52 pt glass Set Additional Password
/// button 48 pt from the sides and 60 pt above the bottom inset. The button opens the password setup.
final class TwoStepVerificationIntroViewController: UIViewController {
    // MARK: Internal

    /// Runs when the button is tapped; the presenter starts the setup.
    var onAction: (() -> Void)?

    // MARK: Private

    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let button = UIButton(configuration: .prominentGlass())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        titleLabel.text = L10n.telegram("TwoFactorSetup.Intro.Title")
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        textLabel.text = L10n.telegram("TwoFactorSetup.Intro.Text")
        textLabel.font = .systemFont(ofSize: 16)
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        var configuration = UIButton.Configuration.prominentGlass()
        configuration.title = L10n.telegram("TwoFactorSetup.Intro.Action")
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        button.configuration = configuration
        button.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        for subview in [animationView, titleLabel, textLabel, button] {
            view.addSubview(subview)
        }
        if let path = Bundle.main.path(forResource: "TwoFactorSetupIntro", ofType: "tgs") {
            Task { [weak self] in
                guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
                animationView.animation = animation
                if view.window != nil { animationView.play() }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if animationView.animation != nil, !animationView.isAnimationPlaying, animationView.currentProgress == 0 {
            animationView.play()
        }
    }

    /// TwoFactorAuthSplashScreenNode.containerLayoutUpdated.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        let bandMinX = view.safeAreaInsets.left
        let bandWidth = size.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        let sideInset: CGFloat = 32
        let iconSide: CGFloat = 124
        let iconSpacing: CGFloat = 8
        let titleSpacing: CGFloat = 19
        let buttonHeight: CGFloat = 52
        let textWidth = bandWidth - sideInset * 2
        let titleSize = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let textSize = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let contentHeight = iconSide + iconSpacing + titleSize.height + titleSpacing + textSize.height
        let buttonFrame = CGRect(
            x: bandMinX + 48,
            y: size.height - view.safeAreaInsets.bottom - 60 - buttonHeight,
            width: bandWidth - 96,
            height: buttonHeight,
        )
        button.frame = buttonFrame
        let origin = min(
            floor((size.height - contentHeight - iconSide / 2) / 2),
            buttonFrame.minY - 12 - contentHeight,
        )
        animationView.frame = CGRect(
            x: bandMinX + floor((bandWidth - iconSide) / 2),
            y: origin,
            width: iconSide,
            height: iconSide,
        )
        titleLabel.frame = CGRect(
            x: bandMinX + floor((bandWidth - titleSize.width) / 2),
            y: animationView.frame.maxY + iconSpacing,
            width: titleSize.width,
            height: titleSize.height,
        )
        textLabel.frame = CGRect(
            x: bandMinX + floor((bandWidth - textSize.width) / 2),
            y: titleLabel.frame.maxY + titleSpacing,
            width: textSize.width,
            height: textSize.height,
        )
    }
}
