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
                if (contentWidth != 0 && replyWidth > contentWidth) || (textWidth != 0 && replyWidth > textWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
                return corners
            case .content:
                if replyWidth != 0 && replyWidth < contentWidth {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                if textWidth != 0 && textWidth < contentWidth {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth == 0 {
                    if editWidth == 0 {
                        corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                    } else if editWidth != 0 && editWidth < contentWidth {
                        corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                    }
                }
                return corners
            case .text:
                if contentWidth != 0 {
                    if contentWidth < textWidth {
                        corners.append(isOutgoing ? .topLeading : .topTrailing)
                    }
                } else if replyWidth != 0 {
                    if replyWidth < textWidth {
                        corners.append(isOutgoing ? .topLeading : .topTrailing)
                    }
                } else {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                if editWidth != 0 {
                    if editWidth < textWidth {
                        corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                    }
                } else if editWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
                return corners
            case .edit:
                corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                if (textWidth != 0 && textWidth < editWidth) || (contentWidth != 0 && contentWidth < editWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                }
                return corners
        }
    }

}
