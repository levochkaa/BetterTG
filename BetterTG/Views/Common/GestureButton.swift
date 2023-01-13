// GestureButton.swift

import SwiftUI

struct GestureButton<Label: View>: View {
    
    var label: () -> Label
    var style: GestureButtonStyle
    var releaseAction: () -> Void
    
    init(
        doubleTapTimeout: TimeInterval = 0.5,
        longPressTime: TimeInterval = 0.5,
        pressAction: @escaping () -> Void = {},
        releaseAction: @escaping () -> Void = {},
        endAction: @escaping () -> Void = {},
        longPressAction: @escaping () -> Void = {},
        doubleTapAction: @escaping () -> Void = {},
        label: @escaping () -> Label
    ) {
        self.style = GestureButtonStyle(
            pressAction: pressAction,
            doubleTapTimeout: doubleTapTimeout,
            doubleTapAction: doubleTapAction,
            longPressTime: longPressTime,
            longPressAction: longPressAction,
            endAction: endAction
        )
        self.releaseAction = releaseAction
        self.label = label
    }
    
    var body: some View {
        Button(action: releaseAction, label: label)
            .buttonStyle(style)
    }
}
