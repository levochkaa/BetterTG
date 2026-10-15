// TelegramLinkRouterProbe.swift

#if DEBUG
    import Foundation

    /// Offline check of which URLs the router hands to TDLib's getInternalLinkType: Telegram's hosts and schemes in
    /// LinkManager::get_link_info's forms, and nothing else. No TDLib request, navigation or URL open runs.
    @MainActor enum TelegramLinkRouterProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-telegram-links") else { return }
            let result: String
            do {
                try verify()
                result = "Telegram link probe passed: hosts/subdomains/schemes/ports/credentials=true; "
                    + "usernames=true; TDLib/navigation/URL-open=0"
            } catch { result = "Telegram link probe failed: \(error)" }
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("telegram-link-probe.txt"),
                    options: .atomic,
                )
            }
        }

        private static func require(_ value: Bool, _ reason: String) throws {
            guard value else { throw Failure(description: reason) }
        }

        private static func link(_ string: String) -> String? {
            URL(string: string).flatMap(TelegramLinkRouter.internalLink(for:))
        }

        private static func verify() throws {
            for telegramLink in [
                "https://t.me/durov",
                "http://telegram.me/durov/42",
                "https://www.telegram.dog/joinchat/AbCd",
                "https://T.ME/+AbCdEf",
                "https://t.me:443/c/1234/56?thread=7",
                "https://durov.t.me",
                "https://www.t.me/addstickers/Pack",
                "tg://resolve?domain=durov&start=x",
                "TG:resolve?domain=durov",
            ] {
                try require(link(telegramLink) == telegramLink, "rejected \(telegramLink)")
            }
            try require(
                link("bettertg://resolve?domain=durov") == "tg://resolve?domain=durov"
                    && link("bettertg:addlist?slug=abc") == "tg:addlist?slug=abc",
                "bettertg scheme not mapped to tg",
            )
            for otherLink in [
                "https://example.com/t.me/durov",
                "https://t.me.example.com/durov",
                "https://evil.com.t.me/durov",
                "https://addstickers.t.me",
                "https://a_.t.me",
                "https://1abc.t.me",
                "https://t.me:8443/durov",
                "https://user:secret@t.me/durov",
                "https://telegra.ph/page",
                "ftp://t.me/durov",
                "mailto:durov@t.me",
                "tel:+123",
            ] {
                try require(link(otherLink) == nil, "accepted \(otherLink)")
            }
            for valid in ["a", "durov", "a_b", "Abc123", String(repeating: "a", count: 32)] {
                try require(TelegramLinkRouter.isTelegramUsername(valid), "username \(valid) rejected")
            }
            for invalid in ["", "_a", "1a", "a_", "a__b", "a-b", "dúrov", String(repeating: "a", count: 33)] {
                try require(!TelegramLinkRouter.isTelegramUsername(invalid), "username \(invalid) accepted")
            }
        }
    }
#endif
