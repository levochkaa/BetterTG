// DataSize.swift

import Foundation

// MARK: - DataSize

/// Telegram's dataSizeString: bytes, then KB, MB and GB by 1024 with one decimal cut down (not rounded) and left out
/// when it is zero, unless `forceDecimal`; the units are FileSize.B, KB, MB and GB.
enum DataSize {
    static func string(_ size: Int64, forceDecimal: Bool = false) -> String {
        let gigabyte: Int64 = 1024 * 1024 * 1024
        let megabyte: Int64 = 1024 * 1024
        if size >= gigabyte {
            let remainder = Int64((Double(size % gigabyte) / (1024 * 1024 * 102.4)).rounded(.down))
            return L10n.telegram("FileSize.GB", number(size / gigabyte, remainder, forceDecimal))
        } else if size >= megabyte {
            let remainder = Int64((Double(size % megabyte) / (1024 * 102.4)).rounded(.down))
            return L10n.telegram("FileSize.MB", number(size / megabyte, remainder, forceDecimal))
        } else if size >= 1024 {
            return L10n.telegram("FileSize.KB", number(size / 1024, (size % 1024) / 102, forceDecimal))
        }
        return L10n.telegram("FileSize.B", "\(size)")
    }

    private static func number(_ whole: Int64, _ remainder: Int64, _ forceDecimal: Bool) -> String {
        remainder != 0 || forceDecimal ? "\(whole).\(remainder)" : "\(whole)"
    }
}
