// IsPreview.swift

import SwiftUI

private struct IsPreview: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isPreview: Bool {
        get { self[IsPreview.self] }
        set { self[IsPreview.self] = newValue }
    }
}
