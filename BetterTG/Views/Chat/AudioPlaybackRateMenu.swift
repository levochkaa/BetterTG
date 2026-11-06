// AudioPlaybackRateMenu.swift

import Combine
import UIKit

// MARK: - AudioPlaybackRateMenu

/// The voice and music rate button's menu and tooltip, after MediaNavigationAccessoryHeaderNode and
/// OverlayAudioPlayerControlsNode (Telegram `fb0e62ba8a`). Holding the button opens contextMenuSpeedItems: the presets
/// with a check on the playing one, then SliderContextItem from 0.2 to 2.5. Telegram puts the slider in a second list
/// under the presets (`.twoLists`); BetterTG's menu has one card, so a separator stands between them. The slider sets
/// the rate in tenths as it moves and clears the check, and the tooltip waits for the menu to close; a preset closes
/// the menu and shows its tooltip at once. MediaPlaybackHeaderPanelComponent's tooltip names the new speed: normal,
/// 1.5x, two times faster, or a slider's value, and none for 0.5x or a slider that ends where it began.
@MainActor enum AudioPlaybackRateMenu {
    // MARK: Internal

    /// MediaNavigationAccessoryPanel.ChangeType without `.sliderChange`, which shows no tooltip.
    enum Change: Equatable {
        case preset
        case sliderCommit(previous: Float, new: Float)
    }

    /// Opens the menu from the rate button, with the finger that held it.
    static func present(
        from controller: UIViewController,
        sourceView: UIView,
        gesture: UIGestureRecognizer?,
        showTooltip: @escaping (String) -> Void,
    ) {
        let media = Media.shared
        let previous = media.playbackRate
        let sliderMoved = PassthroughSubject<Void, Never>()
        var scheduledChange: Change?
        let checkmark = UIImage(systemName: "checkmark")
        var actions = Media.playbackRates.map { rate in
            var action = TelegramContextMenuAction(
                title: StoryMoreMenu.speedTitle(Double(rate)),
                image: rate == previous ? checkmark : UIImage(),
                handler: {
                    scheduledChange = nil
                    media.setPlaybackRate(rate)
                    let change: Change = Media.playbackRates.contains(previous)
                        ? .preset
                        : .sliderCommit(previous: previous, new: rate)
                    if let text = tooltip(rate: rate, change: change) { showTooltip(text) }
                },
            )
            action.imageUpdates = sliderMoved.map { UIImage() as UIImage? }.eraseToAnyPublisher()
            return action
        }
        var slider = TelegramContextMenuAction.slider(TelegramContextMenuSlider(
            minimumValue: CGFloat(MediaPlaybackRate.range.lowerBound),
            maximumValue: CGFloat(MediaPlaybackRate.range.upperBound),
            value: { CGFloat(media.playbackRate) },
            accessibilityLabel: L10n.telegram("PlaybackSpeed.Title"),
            valueChanged: { value, isFinished in
                let rate = (Float(value) * 10).rounded() / 10
                media.setPlaybackRate(rate)
                sliderMoved.send()
                if isFinished { scheduledChange = .sliderCommit(previous: previous, new: rate) }
            },
        ))
        slider.startsNewSection = true
        actions.append(slider)
        controller.presentTelegramContextMenu(
            sourceView: sourceView,
            actions: actions,
            tracking: gesture,
            presentationStyle: .menuOnly,
            onDismiss: {
                guard let change = scheduledChange,
                      let text = tooltip(rate: media.playbackRate, change: change)
                else { return }
                showTooltip(text)
            },
        )
    }

    /// The rate button's press recognizer, which grows the button and hands its finger to the menu.
    static func makePressRecognizer(target: Any, action: Selector) -> ContextMenuPressGestureRecognizer {
        let press = ContextMenuPressGestureRecognizer(target: target, action: action)
        press.castsShadow = false
        return press
    }

    /// MediaPlaybackHeaderPanelComponent's UndoOverlayController `.audioRate` text for a change to `rate`.
    static func tooltip(rate: Float, change: Change) -> String? {
        switch change {
        case .sliderCommit(let previous, let new):
            guard new != previous else { return nil }
            if rate == 1 { return L10n.telegram("Conversation.AudioRateTooltipNormal") }
            return L10n.telegram("Conversation.AudioRateTooltipCustom", String(format: "%0.1f", rate))
        case .preset:
            switch rate {
            case 1: return L10n.telegram("Conversation.AudioRateTooltipNormal")
            case 1.5: return L10n.telegram("Conversation.AudioRateTooltip15X")
            case 2: return L10n.telegram("Conversation.AudioRateTooltipSpeedUp")
            default: return nil
            }
        }
    }
}
