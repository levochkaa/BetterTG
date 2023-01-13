// Task+AsyncAfter.swift

import SwiftUI

extension Task where Success == Never, Failure == Never {
    static func async(after time: TimeInterval, _ execute: @escaping @convention(block) () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: execute)
    }
}
