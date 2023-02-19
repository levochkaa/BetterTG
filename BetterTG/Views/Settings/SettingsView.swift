// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    
    @EnvironmentObject var settings: SettingsViewModel
    
    var body: some View {
        List {
            Section {
                SpacingAround(axis: .horizontal) {
                    Text("Change settings for the app here")
                }
            } header: {
                SpacingAround(axis: .horizontal) {
                    Text("Settings")
                        .padding()
                }
                .headerProminence(.increased)
            }
            .listRowBackground(Color.clear)
            
            customSection(header: "Chats List") {
                Toggle("Archived Chats", isOn: $settings.showArchivedChatsButton)
            }
            
            customSection(header: "Chat") {
                Toggle("Albums", isOn: $settings.showAlbums)
                Toggle("Photos", isOn: $settings.showPhotos)
                Toggle("Animojis", isOn: $settings.showAnimojis)
                Toggle("Voice Notes", isOn: $settings.showVoiceNotes)
                Toggle("Replies", isOn: $settings.showReplies)
                Toggle("Forwarded From", isOn: $settings.showForwardedFrom)
                Toggle("Edited", isOn: $settings.showEdited)
            }
        }
        .listStyle(.automatic)
        .scrollContentBackground(.hidden)
    }
    
    @ViewBuilder func customSection<Content: View>(
        header: String? = nil,
        increasedHeader: Bool = true,
        footer: String? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            if let header {
                Text(header)
                    .headerProminence(increasedHeader ? .increased : .standard)
            }
        } footer: {
            if let footer {
                Text(footer)
            }
        }
        .listRowBackground(
            Rectangle()
                .fill(.thinMaterial)
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsViewModel())
    }
}
