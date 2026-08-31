// AvatarColorPalette.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - TelegramAvatarIcon

enum TelegramAvatarIcon: Equatable {
    case none
    case savedMessages
    case replies
    case anonymousSavedMessages
    case deleted
}

// MARK: - TelegramAvatarPlaceholder

struct TelegramAvatarPlaceholder {
    let peerID: Int64
    let accentColorID: Int
    let upgradedGiftColors: UpgradedGiftColors?
    let letters: [String]
    let isDeleted: Bool

    func icon(accountUserID: Int64?) -> TelegramAvatarIcon {
        if peerID == 708_513 || peerID == 1_271_266_957 {
            return .replies
        }
        if peerID == 2_666_000 {
            return .anonymousSavedMessages
        }
        if peerID == accountUserID {
            return .savedMessages
        }
        if isDeleted {
            return .deleted
        }
        return .none
    }
}

// MARK: - AvatarColorPalette

@MainActor final class AvatarColorPalette {
    // MARK: Internal

    static let shared = AvatarColorPalette()

    // MARK: Private

    private static let gradients: [[UIColor]] = [
        [UIColor(rgb: 0xFF516A), UIColor(rgb: 0xFF885E)],
        [UIColor(rgb: 0xFFA85C), UIColor(rgb: 0xFFCD6A)],
        [UIColor(rgb: 0x665FFF), UIColor(rgb: 0x82B1FF)],
        [UIColor(rgb: 0x54CB68), UIColor(rgb: 0xA0DE7E)],
        [UIColor(rgb: 0x4ACCCD), UIColor(rgb: 0x00FCFD)],
        [UIColor(rgb: 0x2A9EF1), UIColor(rgb: 0x72D5FD)],
        [UIColor(rgb: 0xD669ED), UIColor(rgb: 0xE0A2F3)],
    ]

    private static let grayscaleGradient = [UIColor(rgb: 0xB1B1B1), UIColor(rgb: 0xCDCDCD)]

    private var serverColors = [Int: AccentColor]()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    private static func normalizedPaletteIndex(_ value: Int) -> Int {
        let remainder = value % gradients.count
        return remainder >= 0 ? remainder : remainder + gradients.count
    }

    private static func paletteIndex(forRGB rgb: Int) -> Int {
        let color = UIColor(rgb: rgb)
        var hue = CGFloat.zero
        guard color.getHue(&hue, saturation: nil, brightness: nil, alpha: nil) else { return 5 }
        if hue > 0.9 || hue < 0.02 {
            return 0
        } else if hue < 0.1 {
            return 1
        } else if hue < 0.4 {
            return 3
        } else if hue < 0.5 {
            return 4
        } else if hue < 0.6 {
            return 5
        } else if hue < 0.75 {
            return 2
        } else {
            return 6
        }
    }

    func start() {
        guard !started else { return }
        started = true

        nc.publisher(
            &cancellables,
            for: TdNotification<UpdateAccentColors>.updateAccentColors,
        ) { [weak self] update in
            self?.serverColors = Dictionary(uniqueKeysWithValues: update.colors.map { ($0.id, $0) })
            nc.post(name: .telegramAvatarColorsChanged)
        }
        nc.publisher(&cancellables, for: .activeTelegramAccountChanged) { [weak self] _ in
            self?.serverColors = [:]
            nc.post(name: .telegramAvatarColorsChanged)
        }
    }

    func gradient(
        for placeholder: TelegramAvatarPlaceholder,
        icon: TelegramAvatarIcon,
    ) -> [UIColor] {
        switch icon {
        case .anonymousSavedMessages, .replies, .savedMessages:
            return Self.gradients[5]
        case .deleted:
            return Self.grayscaleGradient
        case .none:
            break
        }

        if let upgradedGiftColors = placeholder.upgradedGiftColors {
            return Self.gradients[Self.paletteIndex(forRGB: upgradedGiftColors.lightThemeAccentColor)]
        }

        let colorID = placeholder.accentColorID
        if colorID > 13,
           let serverColor = serverColors[colorID],
           let mainColor = serverColor.lightThemeColors.first
        {
            return Self.gradients[Self.paletteIndex(forRGB: mainColor)]
        }
        return Self.gradients[Self.normalizedPaletteIndex(colorID)]
    }
}

// MARK: - Avatar placeholder factories

extension CustomChat {
    var telegramAvatarPlaceholder: TelegramAvatarPlaceholder {
        if let user {
            let userPlaceholder = user.telegramAvatarPlaceholder
            return TelegramAvatarPlaceholder(
                peerID: user.id,
                accentColorID: chat.accentColorId,
                upgradedGiftColors: chat.upgradedGiftColors,
                letters: userPlaceholder.letters,
                isDeleted: userPlaceholder.isDeleted,
            )
        }
        return TelegramAvatarPlaceholder(
            peerID: chat.id,
            accentColorID: chat.accentColorId,
            upgradedGiftColors: chat.upgradedGiftColors,
            letters: chat.title.telegramAvatarFirstLetter.map { [$0] } ?? [],
            isDeleted: false,
        )
    }
}

extension User {
    var telegramAvatarPlaceholder: TelegramAvatarPlaceholder {
        TelegramAvatarPlaceholder(
            peerID: id,
            accentColorID: accentColorId,
            upgradedGiftColors: upgradedGiftColors,
            letters: telegramAvatarLetters,
            isDeleted: isDeletedOrUnknown,
        )
    }

    private var isDeletedOrUnknown: Bool {
        switch type {
        case .userTypeDeleted, .userTypeUnknown:
            true
        case .userTypeBot, .userTypeRegular:
            false
        }
    }

    private var telegramAvatarLetters: [String] {
        if let firstLetter = firstName.telegramAvatarFirstLetter,
           let lastLetter = lastName.telegramAvatarFirstLetter
        {
            return [firstLetter, lastLetter]
        }
        if let firstLetter = firstName.telegramAvatarFirstLetter {
            return [firstLetter]
        }
        if let lastLetter = lastName.telegramAvatarFirstLetter {
            return [lastLetter]
        }
        return []
    }
}

private extension String {
    var telegramAvatarFirstLetter: String? {
        first.map { String($0).uppercased() }
    }
}

extension Foundation.Notification.Name {
    static let telegramAvatarColorsChanged = Self("telegramAvatarColorsChanged")
}
