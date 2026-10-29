// TelegramHeaderPanelsView.swift

import UIKit

/// Telegram's HeaderPanelContainerComponent: media then live location in one interactive glass surface.
/// The list's full-width navigation backdrop stays behind it; the controls themselves live inside the glass.
final class TelegramHeaderPanelsView: UIView {
    let voiceHeader = VoicePlaybackHeaderView()
    let liveLocationPanel = LiveLocationPanelView()

    private let glassContainer = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let glass = UIVisualEffectView()
    private let content = UIView()
    private let voiceClip = UIView()
    private let locationClip = UIView()
    private let separator = UIView()
    private var showsVoice = false
    private var showsLocation = false

    var contentHeight: CGFloat {
        let rows = (showsVoice ? VoicePlaybackHeaderView.contentHeight : 0)
            + (showsLocation ? LiveLocationPanelView.contentHeight : 0)
        return rows > 0 ? rows + TelegramGlassPlatter.barBottomInset : 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        glass.effect = effect
        glass.cornerConfiguration = .capsule(maximumRadius: 20)
        addSubview(glassContainer)
        glassContainer.contentView.addSubview(glass)
        glass.contentView.addSubview(content)
        content.clipsToBounds = true
        content.layer.cornerRadius = 20
        content.layer.cornerCurve = .continuous
        for clip in [voiceClip, locationClip] {
            clip.clipsToBounds = true
            content.addSubview(clip)
        }
        voiceClip.addSubview(voiceHeader)
        locationClip.addSubview(liveLocationPanel)
        voiceHeader.showsSeparator = false
        liveLocationPanel.showsSeparator = false
        separator.backgroundColor = .separator
        separator.isUserInteractionEnabled = false
        content.addSubview(separator)
        glassContainer.alpha = 0
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let voiceHeight = showsVoice ? VoicePlaybackHeaderView.contentHeight : 0
        let locationHeight = showsLocation ? LiveLocationPanelView.contentHeight : 0
        let height = max(40, voiceHeight + locationHeight)
        // Telegram gives the container room for glass's lens and shadow outside its panel bounds.
        glassContainer.frame = CGRect(x: -32, y: -32, width: bounds.width + 64, height: height + 64)
        let width = max(0, bounds.width - safeAreaInsets.left - safeAreaInsets.right - 32)
        glass.frame = CGRect(x: 48 + safeAreaInsets.left, y: 32, width: width, height: height)
        content.frame = CGRect(x: 0, y: 0, width: width, height: height)
        voiceClip.frame = CGRect(x: 0, y: 0, width: width, height: voiceHeight)
        voiceHeader.frame = CGRect(x: 0, y: 0, width: width, height: VoicePlaybackHeaderView.contentHeight)
        locationClip.frame = CGRect(x: 0, y: voiceHeight, width: width, height: locationHeight)
        liveLocationPanel.frame = CGRect(x: 0, y: 0, width: width, height: LiveLocationPanelView.contentHeight)
        separator.frame = CGRect(x: 0, y: voiceHeight, width: width, height: 1 / max(1, traitCollection.displayScale))
        separator.alpha = showsVoice && showsLocation ? 1 : 0
        glassContainer.alpha = showsVoice || showsLocation ? 1 : 0
        voiceClip.accessibilityElementsHidden = !showsVoice
        locationClip.accessibilityElementsHidden = !showsLocation
    }

    /// The owner animates its height and calls layoutIfNeeded with the list's content inset in the same transaction.
    @discardableResult func setVisiblePanels(voice: Bool, liveLocation: Bool) -> Bool {
        guard voice != showsVoice || liveLocation != showsLocation else { return false }
        showsVoice = voice
        showsLocation = liveLocation
        isUserInteractionEnabled = voice || liveLocation
        setNeedsLayout()
        return true
    }
}
