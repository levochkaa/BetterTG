// MessageView+Corners.swift

import SwiftUI

extension MessageView {
    
    enum MessagePart {
        case reply, text, content, edit, forwarded
    }
    
    // swiftlint:disable:next function_body_length
    func corners(for type: MessagePart) -> UIRectCorner {
        func shouldRoundCorners(for comparingWidth: Int) -> Bool {
            var value = 0
            switch type {
                case .forwarded: value = forwardedWidth
                case .reply: value = replyWidth
                case .content: value = contentWidth
                case .text: value = textWidth
                case .edit: value = editWidth
            }
            return comparingWidth <= value || comparingWidth - value <= 15
        }
        
        var corners = UIRectCorner()
        
        switch type {
            case .forwarded:
                corners.insert(.topLeft, .topRight)
                if replyWidth != 0, shouldRoundCorners(for: replyWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                } else if replyWidth == 0, contentWidth != 0,
                          shouldRoundCorners(for: contentWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                } else if replyWidth == 0, contentWidth == 0, textWidth != 0,
                          shouldRoundCorners(for: textWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                }
            case .reply:
                if forwardedWidth == 0 {
                    corners.insert(.topLeft, .topRight)
                } else if shouldRoundCorners(for: forwardedWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                }
                
                if contentWidth != 0, shouldRoundCorners(for: contentWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                } else if contentWidth == 0, textWidth != 0, shouldRoundCorners(for: textWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                }
            case .content:
                if replyWidth != 0, shouldRoundCorners(for: replyWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                } else if replyWidth == 0, forwardedWidth != 0,
                          shouldRoundCorners(for: forwardedWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                } else if replyWidth == 0, forwardedWidth == 0 {
                    corners.insert(.topLeft, .topRight)
                }
                
                if textWidth != 0, shouldRoundCorners(for: textWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                } else if textWidth == 0, editWidth != 0,
                          shouldRoundCorners(for: editWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                } else if textWidth == 0, editWidth == 0 {
                    corners.insert(.bottomLeft, .bottomRight)
                }
            case .text:
                if contentWidth != 0, shouldRoundCorners(for: contentWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                } else if contentWidth == 0, replyWidth != 0,
                          shouldRoundCorners(for: replyWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                } else if contentWidth == 0, replyWidth == 0, forwardedWidth != 0,
                          shouldRoundCorners(for: forwardedWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                } else if contentWidth == 0, replyWidth == 0, forwardedWidth == 0 {
                    corners.insert(.topLeft, .topRight)
                }
                
                if editWidth == 0 {
                    corners.insert(.bottomLeft, .bottomRight)
                } else if shouldRoundCorners(for: editWidth) {
                    corners.insert(isOutgoing ? .bottomLeft : .bottomRight)
                }
            case .edit:
                corners.insert(.bottomLeft, .bottomRight)
                if textWidth != 0, shouldRoundCorners(for: textWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                } else if textWidth == 0, contentWidth != 0,
                          shouldRoundCorners(for: textWidth) {
                    corners.insert(isOutgoing ? .topLeft : .topRight)
                }
        }
        return corners
    }
}
