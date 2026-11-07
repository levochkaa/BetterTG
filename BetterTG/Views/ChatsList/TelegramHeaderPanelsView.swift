// TelegramHeaderPanelsView.swift

import UIKit

/// Telegram's HeaderPanelContainerComponent: the chat list notice (a login to review), media, then live location in one
/// interactive glass surface.
/// The list's full-width navigation backdrop stays behind it; the controls themselves live inside the glass.
final class TelegramHeaderPanelsView: UIView {
    let notice = ChatListNoticeView()
    let voiceHeader = VoicePlaybackHeaderView()
    let liveLocationPanel = LiveLocationPanelView()
    /// The owner's width, for the notice's height before this view has been laid out.
    var fallbackWidth: CGFloat = 0

    private let glassContainer = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let glass = UIVisualEffectView()
    private let content = UIView()
    private let noticeClip = UIView()
    private let voiceClip = UIView()
    private let locationClip = UIView()
    private let noticeSeparator = UIView()
    private let separator = UIView()
    private var showsNotice = false
    private var showsVoice = false
    private var showsLocation = false

    var contentHeight: CGFloat {
        let rows = noticeHeight
            + (showsVoice ? VoicePlaybackHeaderView.contentHeight : 0)
            + (showsLocation ? LiveLocationPanelView.contentHeight : 0)
        return rows > 0 ? rows + TelegramGlassPlatter.barBottomInset : 0
    }

    private var glassWidth: CGFloat {
        let width = bounds.width > 0 ? bounds.width : fallbackWidth
        return max(0, width - safeAreaInsets.left - safeAreaInsets.right - 32)
    }

    private var noticeHeight: CGFloat {
        showsNotice ? notice.height(forWidth: glassWidth) : 0
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
        for clip in [noticeClip, voiceClip, locationClip] {
            clip.clipsToBounds = true
            content.addSubview(clip)
        }
        noticeClip.addSubview(notice)
        voiceClip.addSubview(voiceHeader)
        locationClip.addSubview(liveLocationPanel)
        voiceHeader.showsSeparator = false
        liveLocationPanel.showsSeparator = false
        for line in [noticeSeparator, separator] {
            line.backgroundColor = .separator
            line.isUserInteractionEnabled = false
            content.addSubview(line)
        }
        glassContainer.alpha = 0
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let noticeHeight = noticeHeight
        let voiceHeight = showsVoice ? VoicePlaybackHeaderView.contentHeight : 0
        let locationHeight = showsLocation ? LiveLocationPanelView.contentHeight : 0
        let height = max(40, noticeHeight + voiceHeight + locationHeight)
        // Telegram gives the container room for glass's lens and shadow outside its panel bounds.
        glassContainer.frame = CGRect(x: -32, y: -32, width: bounds.width + 64, height: height + 64)
        let width = max(0, bounds.width - safeAreaInsets.left - safeAreaInsets.right - 32)
        glass.frame = CGRect(x: 48 + safeAreaInsets.left, y: 32, width: width, height: height)
        content.frame = CGRect(x: 0, y: 0, width: width, height: height)
        noticeClip.frame = CGRect(x: 0, y: 0, width: width, height: noticeHeight)
        notice.frame = CGRect(x: 0, y: 0, width: width, height: notice.height(forWidth: width))
        voiceClip.frame = CGRect(x: 0, y: noticeHeight, width: width, height: voiceHeight)
        voiceHeader.frame = CGRect(x: 0, y: 0, width: width, height: VoicePlaybackHeaderView.contentHeight)
        locationClip.frame = CGRect(x: 0, y: noticeHeight + voiceHeight, width: width, height: locationHeight)
        liveLocationPanel.frame = CGRect(x: 0, y: 0, width: width, height: LiveLocationPanelView.contentHeight)
        let line = 1 / max(1, traitCollection.displayScale)
        noticeSeparator.frame = CGRect(x: 0, y: noticeHeight, width: width, height: line)
        noticeSeparator.alpha = showsNotice && (showsVoice || showsLocation) ? 1 : 0
        separator.frame = CGRect(x: 0, y: noticeHeight + voiceHeight, width: width, height: line)
        separator.alpha = showsVoice && showsLocation ? 1 : 0
        glassContainer.alpha = showsNotice || showsVoice || showsLocation ? 1 : 0
        noticeClip.accessibilityElementsHidden = !showsNotice
        voiceClip.accessibilityElementsHidden = !showsVoice
        locationClip.accessibilityElementsHidden = !showsLocation
    }

    /// The owner animates its height and calls layoutIfNeeded with the list's content inset in the same transaction.
    @discardableResult func setVisiblePanels(notice: Bool = false, voice: Bool, liveLocation: Bool) -> Bool {
        guard notice != showsNotice || voice != showsVoice || liveLocation != showsLocation else { return false }
        showsNotice = notice
        showsVoice = voice
        showsLocation = liveLocation
        isUserInteractionEnabled = notice || voice || liveLocation
        setNeedsLayout()
        return true
    }
}
