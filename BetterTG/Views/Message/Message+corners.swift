// Message+corners.swift

import SwiftUI
import SwiftUIX

extension MessageView {
    
    enum MessagePart {
        case reply, text, content, edit, forwarded
    }
    
    // swiftlint:disable function_body_length
    func corners(for type: MessagePart) -> [RectangleCorner] {
        func shouldRoundCorners(for comparingWidth: Double) -> Bool {
            var value: Double = 0
            switch type {
                case .forwarded: value = forwardedWidth
                case .reply: value = replyWidth
                case .content: value = contentWidth
                case .text: value = textWidth
                case .edit: value = editWidth
            }
            return comparingWidth <= value || comparingWidth - value <= 15
        }
        
        var corners = [RectangleCorner]()
        switch type {
            case .forwarded:
                corners.append(contentsOf: [.topLeading, .topTrailing])
                if replyWidth != 0, shouldRoundCorners(for: replyWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if replyWidth == 0, contentWidth != 0,
                          shouldRoundCorners(for: contentWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if replyWidth == 0, contentWidth == 0, textWidth != 0,
                          shouldRoundCorners(for: textWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
            case .reply:
                if forwardedWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                } else if shouldRoundCorners(for: forwardedWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                }
                
                if contentWidth != 0, shouldRoundCorners(for: contentWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if contentWidth == 0, textWidth != 0, shouldRoundCorners(for: textWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
            case .content:
                if replyWidth != 0, shouldRoundCorners(for: replyWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0, forwardedWidth != 0,
                          shouldRoundCorners(for: forwardedWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if replyWidth == 0, forwardedWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                
                if textWidth != 0, shouldRoundCorners(for: textWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth == 0, editWidth != 0,
                          shouldRoundCorners(for: editWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                } else if textWidth == 0, editWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                }
            case .text:
                if contentWidth != 0, shouldRoundCorners(for: contentWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if contentWidth == 0, replyWidth != 0,
                          shouldRoundCorners(for: replyWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if contentWidth == 0, replyWidth == 0, forwardedWidth != 0,
                          shouldRoundCorners(for: forwardedWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if contentWidth == 0, replyWidth == 0, forwardedWidth == 0 {
                    corners.append(contentsOf: [.topLeading, .topTrailing])
                }
                
                if editWidth == 0 {
                    corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                } else if shouldRoundCorners(for: editWidth) {
                    corners.append(isOutgoing ? .bottomLeading : .bottomTrailing)
                }
            case .edit:
                corners.append(contentsOf: [.bottomLeading, .bottomTrailing])
                if textWidth != 0, shouldRoundCorners(for: textWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                } else if textWidth == 0, contentWidth != 0,
                          shouldRoundCorners(for: textWidth) {
                    corners.append(isOutgoing ? .topLeading : .topTrailing)
                }
        }
        return corners
    }

}
