// Sendable.swift

import SwiftUI
import TDLibKit

extension ChatAction: @unchecked Sendable {}

extension ChatViewModel: @unchecked Sendable {}

extension RootViewModel: @unchecked Sendable {}

extension LoginViewModel: @unchecked Sendable {}
