// MessageView+Corners.swift

import SwiftUIX

extension MessageView {
    
    enum MessagePart {
        case reply, text, content, edit
    }
    
    func corners(for type: MessagePart) -> [RectangleCorner] {
        let isOutgoing = customMessage.message.isOutgoing
        var corners = [RectangleCorner]()
        switch type {
            case .reply:
                corners.append(contentsOf: [.topLeading, .topTrailing])
                if (contentWidth != 0 && replyWidth > contentWidth) || (textWidth != 0 && replyWidth > textWidth)
                    || (contentWidth != 0 && contentWidth - replyWidth < 15)
                    || (textWidth != 0 && textWidth - replyWidth < 15) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
                return corners
            case .content:
                if replyWidth != 0 && replyWidth < contentWidth {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                if (textWidth != 0 && textWidth < contentWidth)
                    || (textWidth == 0 && editWidth != 0 && editWidth < contentWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth == 0 && editWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
                return corners
            case .text:
                if (contentWidth != 0 && contentWidth < textWidth)
                    || (contentWidth != 0 && contentWidth - textWidth < 15)
                    || (replyWidth != 0 && replyWidth < textWidth)
                    || (replyWidth != 0 && replyWidth - textWidth < 15) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0 && contentWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                if editWidth != 0 && editWidth < textWidth {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if editWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
                return corners
            case .edit:
                corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                if (textWidth != 0 && textWidth < editWidth) || (contentWidth != 0 && contentWidth < editWidth)
                    || (textWidth != 0 && textWidth - editWidth < 15)
                    || (contentWidth != 0 && contentWidth - editWidth < 15) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                }
                return corners
        }
    }

}
