// CustomLottieAnimation.swift

import Foundation
import Lottie

struct CustomEmojiAnimation: Identifiable {
    var id = UUID()
    var lottieAnimation: LottieAnimation
    var realEmoji: String
}

extension CustomEmojiAnimation: Equatable {
    static func == (lhs: CustomEmojiAnimation, rhs: CustomEmojiAnimation) -> Bool {
        lhs.id == rhs.id
    }
}
