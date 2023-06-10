// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @AppStorage("showAnimojis") var showAnimojis = true
    @AppStorage("showPhotos") var showPhotos = true
    @AppStorage("showAlbums") var showAlbums = true
    @AppStorage("showVoiceNotes") var showVoiceNotes = true
    @AppStorage("showArchivedChatsButton") var showArchivedChatsButton = true
    @AppStorage("showReplies") var showReplies = true
    @AppStorage("showForwardedFrom") var showForwardedFrom = true
    @AppStorage("showEdited") var showEdited = true
    
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
                Toggle("Archived Chats", isOn: $showArchivedChatsButton)
            }
            
            customSection(header: "Chat") {
                Toggle("Albums", isOn: $showAlbums)
                Toggle("Photos", isOn: $showPhotos)
                Toggle("Animojis", isOn: $showAnimojis)
                Toggle("Voice Notes", isOn: $showVoiceNotes)
                Toggle("Replies", isOn: $showReplies)
                Toggle("Forwarded From", isOn: $showForwardedFrom)
                Toggle("Edited", isOn: $showEdited)
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
    }
}
