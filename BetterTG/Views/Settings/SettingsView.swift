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
            
            Section {
                Toggle("Albums", isOn: $settings.showAlbums)
                Toggle("Photos", isOn: $settings.showPhotos)
                Toggle("Animojis", isOn: $settings.showAnimojis)
                Toggle("Voice Notes", isOn: $settings.showVoiceNotes)
            } header: {
                Text("Chat")
                    .headerProminence(.increased)
            } footer: {
                Text("Toggle these things to fix problems with perfomance in messages list")
            }
            .listRowBackground(
                Rectangle()
                    .fill(.thinMaterial)
            )
        }
        .listStyle(.automatic)
        .scrollContentBackground(.hidden)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsViewModel())
    }
}
