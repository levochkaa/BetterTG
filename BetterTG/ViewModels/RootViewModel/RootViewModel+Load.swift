// RootViewModel+Load.swift

extension RootViewModel {
    func loadMainChats() {
        Task {
            let chatIds = await tdGetChats()
            let customChats = await chatIds.asyncCompactMap { await getCustomChat(from: $0) }
            await MainActor.run {
                mainChats = customChats
            }
        }
    }
}
