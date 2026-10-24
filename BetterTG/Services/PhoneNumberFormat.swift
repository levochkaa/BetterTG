// PhoneNumberFormat.swift

import Foundation
import TDLibKit

// MARK: - PhoneNumberFormat

/// Telegram's formatPhoneNumber (PhoneNumberFormat/PhoneNumbers.swift): a number read as international and shown in its
/// country's mask from the server's country list (lookupPatternByNumber, formatPhoneNumberToMask). TDLib keeps the
/// same list and applies its masks in getPhoneNumberInfoSync, which TDLibKit only sends asynchronously. Telegram falls
/// back to libphonenumber for a number the list has no mask for; BetterTG doesn't bundle libphonenumber, so such a
/// number keeps the caller's text.
enum PhoneNumberFormat {
    /// The number as "+7 999 123 4567"; nil when TDLib knows no country for it, where Telegram's formatter also
    /// returns the text unchanged because the number doesn't parse.
    static func international(_ number: String, client: TDLibClient) async -> String? {
        let digits = String(number.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
        guard !digits.isEmpty,
              let info = try? await client.getPhoneNumberInfoSync(languageCode: "en", phoneNumberPrefix: digits),
              info.country != nil,
              !info.countryCallingCode.isEmpty
        else { return nil }
        return masked(callingCode: info.countryCallingCode, rest: info.formattedPhoneNumber)
    }

    /// formatPhoneNumberToMask stops at the number's last digit, while TDLib also returns the mask's unfilled tail, a
    /// "-" for each missing digit with its separators; that tail goes.
    private static func masked(callingCode: String, rest: String) -> String {
        var rest = rest.replacing("-", with: "")
        while let last = rest.last, !last.isNumber {
            rest.removeLast()
        }
        return rest.isEmpty ? "+" + callingCode : "+\(callingCode) \(rest)"
    }
}
