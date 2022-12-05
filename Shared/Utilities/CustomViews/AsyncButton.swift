// AsyncButton.swift

import SwiftUI

struct AsyncButton<Label>: View where Label: View {
    
    let title: LocalizedStringKey?
    let role: ButtonRole?
    let action: @Sendable () async throws -> Void
    let label: (() -> Label)?
    
    private init(
        title: LocalizedStringKey?,
        role: ButtonRole? = nil,
        action: @escaping @Sendable () async throws -> Void,
        label: (() -> Label)?
    ) {
        self.title = title
        self.role = role
        self.action = action
        self.label = label
    }
    
    init(
        role: ButtonRole? = nil,
        action: @escaping @Sendable () async throws -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.init(title: nil, role: role, action: action, label: label)
    }
    
    var body: some View {
        if let title {
            Button(title, role: role) {
                Task {
                    try await action()
                }
            }
        } else if let label {
            Button(role: role) {
                Task {
                    try await action()
                }
            } label: {
                label()
            }
        } else {
            Text("Unknown state of an AsyncButton")
        }
    }
}

extension AsyncButton where Label == Text {
    internal init(
        _ title: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping @Sendable () async throws -> Void
    ) {
        self.init(title: title, role: role, action: action, label: nil)
    }
}
