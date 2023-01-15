// MessageView+Corners.swift

import SwiftUI
import SwiftUIX

extension MessageView {
    
    enum MessagePart {
        case reply, text, content, edit
    }
    
    func corners(for type: MessagePart) -> [RectangleCorner] {
        var corners = [RectangleCorner]()
        switch type {
            case .reply:
                corners.append(contentsOf: [.topLeading, .topTrailing])
                if (contentWidth != 0 && replyWidth > contentWidth) || (textWidth != 0 && replyWidth > textWidth)
                    || (contentWidth != 0 && contentWidth - replyWidth < 15)
                    || (textWidth != 0 && textWidth - replyWidth < 15) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
            case .content:
                if replyWidth != 0 && replyWidth < contentWidth {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                if (textWidth != 0 && textWidth < contentWidth)
                    || (textWidth == 0 && bottomTextWidth != 0 && bottomTextWidth < contentWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth == 0 && bottomTextWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
            case .text:
                if (contentWidth != 0 && contentWidth < textWidth)
                    || (contentWidth != 0 && contentWidth - textWidth < 15)
                    || (replyWidth != 0 && replyWidth < textWidth)
                    || (replyWidth != 0 && replyWidth - textWidth < 15) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0 && contentWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                if bottomTextWidth != 0 && bottomTextWidth < textWidth {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if bottomTextWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
            case .edit:
                corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                if (textWidth != 0 && textWidth < bottomTextWidth)
                    || (contentWidth != 0 && contentWidth < bottomTextWidth)
                    || (textWidth != 0 && textWidth - bottomTextWidth < 15)
                    || (contentWidth != 0 && contentWidth - bottomTextWidth < 15) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                }
        }
        return corners
    }

}
