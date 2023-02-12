// RootView+BodyPlaceholder.swift

import SwiftUI

extension RootView {
    @ViewBuilder var bodyPlaceholder: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    chatsList(CustomChat.placeholder, redacted: true)
                        .redacted(reason: .placeholder)
                }
                .padding(.top, 8)
            }
            .navigationTitle("BetterTG")
            .searchable(text: .constant(""), prompt: "Search chats...")
            .disabled(true)
            .scrollDisabled(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(systemImage: "square.stack") {}
                        .disabled(true)
                }
            }
        }
    }
}
