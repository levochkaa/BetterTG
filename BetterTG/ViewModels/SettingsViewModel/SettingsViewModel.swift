// SettingsViewModel.swift

import SwiftUI

final class SettingsViewModel: ObservableObject {
    @AppStorage("showAnimojis") var showAnimojis = true
    @AppStorage("showPhotos") var showPhotos = true
    @AppStorage("showAlbums") var showAlbums = true
    @AppStorage("showVoiceNotes") var showVoiceNotes = true
    @AppStorage("showArchivedChatsButton") var showArchivedChatsButton = true
    @AppStorage("showReplies") var showReplies = true
    @AppStorage("showForwardedFrom") var showForwardedFrom = true
    @AppStorage("showEdited") var showEdited = true
}