// SendAsProbe.swift

import TDLibKit
import UIKit

#if DEBUG
    /// `-ui-probe-send-as`: opens the first of the account's "BetterTG parity" chats where TDLib offers more than one
    /// sender, so the Send As avatar and its menu can be checked without posting. The result goes to the log and to
    /// Documents/send-as-probe.txt.
    @MainActor enum SendAsProbe {
        static func openIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-send-as") else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let client = TDLib.shared.activeClient
                let found = try? await client.send(TDNativeRequests.searchChats(
                    query: "BetterTG parity",
                    typeFilter: nil,
                    limit: 10,
                ))
                for chatID in found?.chatIds ?? [] {
                    let senders = try? await client.send(TDNativeRequests.getChatAvailableMessageSenders(
                        chatId: chatID,
                    ))
                    guard (senders?.senders.count ?? 0) > 1,
                          let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
                    else { continue }
                    finish("Send As probe opened a chat with \(senders?.senders.count ?? 0) senders")
                    NavigationStorage.shared.push(.customChat(chat))
                    return
                }
                finish("Send As probe found no chat with a choice of senders")
            }
        }

        private static func finish(_ result: String) {
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("send-as-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }
#endif
