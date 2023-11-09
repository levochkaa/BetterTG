// EnvironmentValues.swift

import SwiftUI

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        UIApplication.currentKeyWindow?.safeAreaInsets.swiftUIInsets ?? .init()
    }
}
