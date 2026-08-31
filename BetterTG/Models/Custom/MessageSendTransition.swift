// MessageSendTransition.swift

import Foundation

// MARK: - ComposerSendTransitionKind

enum ComposerSendTransitionKind: Equatable {
    case media
    case text
    case videoNote
    case voiceNote
}

// MARK: - ComposerSendTransitionRequest

struct ComposerSendTransitionRequest {
    let id: UUID
    let kind: ComposerSendTransitionKind
}

// MARK: - ComposerSendTransitionAcceptance

struct ComposerSendTransitionAcceptance {
    let id: UUID
    let messageIDs: [Int64]
}
