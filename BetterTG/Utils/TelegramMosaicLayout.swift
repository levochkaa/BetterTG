import UIKit

// Port of Telegram-iOS' ChatMessageBubbleMosaicLayout. Keep the branch structure aligned with
// submodules/MosaicLayout/Sources/ChatMessageBubbleMosaicLayout.swift when refreshing it.
struct TelegramMosaicItemPosition: OptionSet {
    let rawValue: Int

    static let top = Self(rawValue: 1 << 0)
    static let bottom = Self(rawValue: 1 << 1)
    static let left = Self(rawValue: 1 << 2)
    static let right = Self(rawValue: 1 << 3)
    static let inside = Self(rawValue: 1 << 4)
}

private struct TelegramMosaicAttempt {
    let lineCounts: [Int]
    let heights: [CGFloat]
}

func telegramMessageBubbleMosaicLayout(
    maxSize: CGSize,
    itemSizes: [CGSize],
    spacing: CGFloat = 1,
    fillWidth: Bool = false,
) -> ([(CGRect, TelegramMosaicItemPosition)], CGSize) {
    guard !itemSizes.isEmpty else { return ([], .zero) }
    if itemSizes.count == 1 {
        let ratio = max(itemSizes[0].width / max(itemSizes[0].height, 1), 0.01)
        let height = min(maxSize.height, maxSize.width / ratio)
        let width = min(maxSize.width, height * ratio)
        return ([(CGRect(x: 0, y: 0, width: width, height: height), [.top, .bottom, .left, .right])],
                CGSize(width: width, height: height))
    }

    let ratios = itemSizes.map { max($0.width / max($0.height, 1), 0.01) }
    var proportions = ""
    var averageAspectRatio: CGFloat = 1
    var forceCalculation = false
    for ratio in ratios {
        proportions += ratio > 1.2 ? "w" : (ratio < 0.8 ? "n" : "q")
        forceCalculation = forceCalculation || ratio > 2
        averageAspectRatio += ratio
    }
    averageAspectRatio /= CGFloat(ratios.count)

    let minWidth: CGFloat = 68
    let minHeight: CGFloat = 81
    let maxAspectRatio = maxSize.width / maxSize.height
    var frames = Array(repeating: CGRect.zero, count: itemSizes.count)

    if !forceCalculation {
        switch ratios.count {
        case 2:
            if proportions == "ww", averageAspectRatio > 1.4 * maxAspectRatio,
               ratios[1] - ratios[0] < 0.2
            {
                let height = floor(min(
                    maxSize.width / ratios[0],
                    min(maxSize.width / ratios[1], (maxSize.height - spacing) / 2),
                ))
                frames[0] = CGRect(x: 0, y: 0, width: maxSize.width, height: height)
                frames[1] = CGRect(x: 0, y: height + spacing, width: maxSize.width, height: height)
            } else if proportions == "ww" || proportions == "qq" {
                let width = (maxSize.width - spacing) / 2
                let height = floor(min(width / ratios[0], min(width / ratios[1], maxSize.height)))
                frames[0] = CGRect(x: 0, y: 0, width: width, height: height)
                frames[1] = CGRect(x: width + spacing, y: 0, width: width, height: height)
            } else {
                let secondWidth = floor(min(
                    0.5 * (maxSize.width - spacing),
                    round((maxSize.width - spacing) / ratios[0] / (1 / ratios[0] + 1 / ratios[1])),
                ))
                let firstWidth = maxSize.width - secondWidth - spacing
                let height = floor(min(maxSize.height, round(min(firstWidth / ratios[0], secondWidth / ratios[1]))))
                frames[0] = CGRect(x: 0, y: 0, width: firstWidth, height: height)
                frames[1] = CGRect(x: firstWidth + spacing, y: 0, width: secondWidth, height: height)
            }
        case 3:
            if proportions.hasPrefix("n") {
                let firstHeight = maxSize.height
                let thirdHeight = min(
                    (maxSize.height - spacing) * 0.5,
                    round(ratios[1] * (maxSize.width - spacing) / (ratios[2] + ratios[1])),
                )
                let secondHeight = maxSize.height - thirdHeight - spacing
                var rightWidth = max(minWidth, min(
                    (maxSize.width - spacing) * 0.5,
                    round(min(thirdHeight * ratios[2], secondHeight * ratios[1])),
                ))
                if fillWidth { rightWidth = floor(maxSize.width * 0.5) }
                var leftWidth = round(min(firstHeight * ratios[0], maxSize.width - spacing - rightWidth))
                if fillWidth { leftWidth = maxSize.width - spacing - rightWidth }
                frames[0] = CGRect(x: 0, y: 0, width: leftWidth, height: firstHeight)
                frames[1] = CGRect(x: leftWidth + spacing, y: 0, width: rightWidth, height: secondHeight)
                frames[2] = CGRect(
                    x: leftWidth + spacing,
                    y: secondHeight + spacing,
                    width: rightWidth,
                    height: thirdHeight,
                )
            } else {
                let firstHeight = floor(min(maxSize.width / ratios[0], (maxSize.height - spacing) * 0.66))
                let width = (maxSize.width - spacing) / 2
                let secondHeight = min(
                    maxSize.height - firstHeight - spacing,
                    round(min(width / ratios[1], width / ratios[2])),
                )
                frames[0] = CGRect(x: 0, y: 0, width: maxSize.width, height: firstHeight)
                frames[1] = CGRect(x: 0, y: firstHeight + spacing, width: width, height: secondHeight)
                frames[2] = CGRect(x: width + spacing, y: firstHeight + spacing, width: width, height: secondHeight)
            }
        case 4:
            if proportions == "wwww" || proportions.hasPrefix("w") {
                let firstHeight = round(min(maxSize.width / ratios[0], (maxSize.height - spacing) * 0.66))
                var height = round((maxSize.width - 2 * spacing) / (ratios[1] + ratios[2] + ratios[3]))
                let firstWidth = max(minWidth, min((maxSize.width - 2 * spacing) * 0.4, height * ratios[1]))
                let thirdWidth = max(max(minWidth, (maxSize.width - 2 * spacing) * 0.33), height * ratios[3])
                let secondWidth = maxSize.width - firstWidth - thirdWidth - 2 * spacing
                height = max(minHeight, min(maxSize.height - firstHeight - spacing, height))
                frames[0] = CGRect(x: 0, y: 0, width: maxSize.width, height: firstHeight)
                frames[1] = CGRect(x: 0, y: firstHeight + spacing, width: firstWidth, height: height)
                frames[2] = CGRect(
                    x: firstWidth + spacing,
                    y: firstHeight + spacing,
                    width: secondWidth,
                    height: height,
                )
                frames[3] = CGRect(
                    x: firstWidth + secondWidth + 2 * spacing,
                    y: firstHeight + spacing,
                    width: thirdWidth,
                    height: height,
                )
            } else {
                let firstWidth = round(min(maxSize.height * ratios[0], (maxSize.width - spacing) * 0.6))
                var width = round((maxSize.height - 2 * spacing) / (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3]))
                let firstHeight = floor(width / ratios[1])
                let secondHeight = floor(width / ratios[2])
                let thirdHeight = maxSize.height - firstHeight - secondHeight - 2 * spacing
                width = max(minWidth, min(maxSize.width - firstWidth - spacing, width))
                frames[0] = CGRect(x: 0, y: 0, width: firstWidth, height: maxSize.height)
                frames[1] = CGRect(x: firstWidth + spacing, y: 0, width: width, height: firstHeight)
                frames[2] = CGRect(
                    x: firstWidth + spacing,
                    y: firstHeight + spacing,
                    width: width,
                    height: secondHeight,
                )
                frames[3] = CGRect(
                    x: firstWidth + spacing,
                    y: firstHeight + secondHeight + 2 * spacing,
                    width: width,
                    height: thirdHeight,
                )
            }
        default:
            break
        }
    }

    if forceCalculation || ratios.count >= 5 {
        let croppedRatios = ratios.map { ratio -> CGFloat in
            let biased = averageAspectRatio > 1.1 ? max(1, ratio) : min(1, ratio)
            return max(0.66667, min(1.7, biased))
        }
        func multiHeight(_ values: ArraySlice<CGFloat>) -> CGFloat {
            (maxSize.width - CGFloat(values.count - 1) * spacing) / values.reduce(0, +)
        }
        var attempts = [TelegramMosaicAttempt]()
        for first in 1 ..< croppedRatios.count {
            let second = croppedRatios.count - first
            guard first <= 3, second <= 3 else { continue }
            attempts.append(.init(
                lineCounts: [first, second],
                heights: [
                    multiHeight(croppedRatios[0 ..< first]),
                    multiHeight(croppedRatios[first ..< croppedRatios.count]),
                ],
            ))
        }
        if croppedRatios.count >= 3 {
            for first in 1 ..< croppedRatios.count - 1 {
                for second in 1 ..< croppedRatios.count - first {
                    let third = croppedRatios.count - first - second
                    guard first <= 3, second <= (averageAspectRatio < 0.85 ? 4 : 3), third <= 3 else { continue }
                    attempts.append(.init(
                        lineCounts: [first, second, third],
                        heights: [
                            multiHeight(croppedRatios[0 ..< first]),
                            multiHeight(croppedRatios[first ..< croppedRatios.count - third]),
                            multiHeight(croppedRatios[first + second ..< croppedRatios.count]),
                        ],
                    ))
                }
            }
        }
        if croppedRatios.count >= 4 {
            for first in 1 ..< croppedRatios.count - 2 {
                for second in 1 ..< croppedRatios.count - first - 1 {
                    for third in 1 ..< croppedRatios.count - first - second {
                        let fourth = croppedRatios.count - first - second - third
                        guard first <= 3, second <= 3, third <= 3, fourth <= 3 else { continue }
                        attempts.append(.init(
                            lineCounts: [first, second, third, fourth],
                            heights: [
                                multiHeight(croppedRatios[0 ..< first]),
                                multiHeight(croppedRatios[first ..< croppedRatios.count - third - fourth]),
                                multiHeight(croppedRatios[first + second ..< croppedRatios.count - fourth]),
                                multiHeight(croppedRatios[first + second + third ..< croppedRatios.count]),
                            ],
                        ))
                    }
                }
            }
        }

        let targetHeight = floor(maxSize.width / 3 * 4)
        let optimal = attempts.min { lhs, rhs in
            attemptCost(lhs, targetHeight: targetHeight, minWidth: minWidth)
                < attemptCost(rhs, targetHeight: targetHeight, minWidth: minWidth)
        }
        if let optimal {
            var index = 0
            var y: CGFloat = 0
            for (line, count) in optimal.lineCounts.enumerated() {
                let lineHeight = ceil(optimal.heights[line])
                var x: CGFloat = 0
                for _ in 0 ..< count {
                    let width = ceil(croppedRatios[index] * lineHeight)
                    frames[index] = CGRect(x: x, y: y, width: width, height: lineHeight)
                    x += width + spacing
                    index += 1
                }
                y += lineHeight + spacing
            }
            let maxWidth = frames.map(\.maxX).max() ?? maxSize.width
            index = 0
            for count in optimal.lineCounts {
                index += count
                frames[index - 1].size.width = max(frames[index - 1].width, maxWidth - frames[index - 1].minX)
            }
        }
    }

    let size = CGSize(
        width: round(frames.map(\.maxX).max() ?? 0),
        height: round(frames.map(\.maxY).max() ?? 0),
    )
    let epsilon: CGFloat = 0.5
    return (frames.map { frame in
        var position = TelegramMosaicItemPosition()
        if frame.minY <= epsilon { position.insert(.top) }
        if frame.maxY >= size.height - epsilon { position.insert(.bottom) }
        if frame.minX <= epsilon { position.insert(.left) }
        if frame.maxX >= size.width - epsilon { position.insert(.right) }
        if position.isEmpty { position.insert(.inside) }
        return (frame, position)
    }, size)
}

private func attemptCost(_ attempt: TelegramMosaicAttempt, targetHeight: CGFloat, minWidth: CGFloat) -> CGFloat {
    let totalHeight = attempt.heights.reduce(CGFloat(attempt.heights.count - 1), +)
    var cost = abs(totalHeight - targetHeight)
    if zip(attempt.lineCounts, attempt.lineCounts.dropFirst()).contains(where: >) {
        cost *= 1.5
    }
    if attempt.heights.min() ?? 0 < minWidth {
        cost *= 1.5
    }
    return cost
}
