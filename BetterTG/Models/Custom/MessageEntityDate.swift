// MessageEntityDate.swift

import Foundation
import TDLibKit

// MARK: - MessageEntityDate

/// TextFormat's stringForEntityFormattedDate for a `textEntityTypeDateTime` with a formatting type: relative as
/// "in 3 days" or "2 hours ago", absolute as the weekday, the short or long date and the time, as the entity asks.
/// Times follow BetterTG's 24-hour message times; a short date puts the day or the month first as the locale does.
enum MessageEntityDate {
    static func string(unixTime: Int, format: TDNativeDateTimeFormattingType, now: Date = Date()) -> String {
        switch format {
        case .dateTimeFormattingTypeRelative:
            relative(unixTime: unixTime, now: now)
        case .dateTimeFormattingTypeAbsolute(let absolute):
            absoluteString(
                unixTime: unixTime,
                time: absolute.timePrecision,
                date: absolute.datePrecision,
                dayOfWeek: absolute.showDayOfWeek,
            )
        }
    }

    /// The date menu's Copy: the long date and the short time.
    static func fullString(unixTime: Int) -> String {
        absoluteString(
            unixTime: unixTime,
            time: .dateTimePartPrecisionShort,
            date: .dateTimePartPrecisionLong,
            dayOfWeek: false,
        )
    }

    private static func relative(unixTime: Int, now: Date) -> String {
        let value = Int(now.timeIntervalSince1970) - unixTime
        let magnitude = abs(value)
        let (unit, count): (String, Int) =
            if magnitude < 60 {
                ("Seconds", magnitude)
            } else if magnitude <= 60 * 60 {
                ("Minutes", Int((Double(magnitude) / 60).rounded()))
            } else if magnitude <= 24 * 60 * 60 {
                ("Hours", Int((Double(magnitude) / 3600).rounded()))
            } else {
                ("Days", Int((Double(magnitude) / 86400).rounded()))
            }
        let key = value > 0 ? "FormattedDate.\(unit)Ago" : "FormattedDate.In\(unit)"
        return L10n.telegramPlural(key, count: count, formattedCount: "\(count)")
    }

    private static func absoluteString(
        unixTime: Int,
        time: TDNativeDateTimePartPrecision,
        date: TDNativeDateTimePartPrecision,
        dayOfWeek: Bool,
    ) -> String {
        let moment = Date(timeIntervalSince1970: TimeInterval(unixTime))
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second], from: moment)
        var string = ""
        let shortDate =
            if case .dateTimePartPrecisionShort = date {
                true
            } else {
                false
            }
        if dayOfWeek, let weekday = parts.weekday {
            string = weekdayName(weekday, short: shortDate)
        }
        switch date {
        case .dateTimePartPrecisionNone:
            break
        case .dateTimePartPrecisionShort:
            if !string.isEmpty { string += " " }
            string += Self.shortDate(parts)
        case .dateTimePartPrecisionLong:
            if !string.isEmpty { string += " " }
            string += L10n.telegram(
                "FormattedDate.LongDate_m\(parts.month ?? 1)", "\(parts.day ?? 1)", "\(parts.year ?? 2000)",
            )
        }
        let timeString: String? =
            switch time {
            case .dateTimePartPrecisionNone: nil
            case .dateTimePartPrecisionShort:
                String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
            case .dateTimePartPrecisionLong:
                String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
            }
        if let timeString {
            string = string.isEmpty ? timeString : L10n.telegram("Time.AtPreciseDate", string, timeString)
        }
        return string
    }

    /// stringForShortDate: two digits each, the day or the month first as the locale writes them.
    private static func shortDate(_ parts: DateComponents) -> String {
        let template = DateFormatter.dateFormat(fromTemplate: "MMdd", options: 0, locale: .current) ?? "dd.MM"
        let monthFirst = (template.firstIndex(of: "M") ?? template.endIndex) <
            (template.firstIndex(of: "d") ?? template.endIndex)
        let day = parts.day ?? 1
        let month = parts.month ?? 1
        let year = (parts.year ?? 2000) % 100
        return monthFirst
            ? String(format: "%02d/%02d/%02d", month, day, year)
            : String(format: "%02d.%02d.%02d", day, month, year)
    }

    private static func weekdayName(_ weekday: Int, short: Bool) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let name = names[(weekday - 1 + 7) % 7]
        return L10n.telegram(short ? "Weekday.Short\(name)" : "Weekday.\(name)")
    }
}

extension FormattedText {
    /// stringWithAppliedEntities' formattedDateReplacement: each date with a formatting type shows the formatted
    /// date in place of its text; entities after it move and entities around it stretch with it. Display only.
    func applyingFormattedDates(now: Date = Date()) -> FormattedText {
        let dates = entities.compactMap { entity -> (TextEntity, String)? in
            guard case .textEntityTypeDateTime(let value) = entity.type, let format = value.formattingType else {
                return nil
            }
            return (entity, MessageEntityDate.string(unixTime: value.unixTime, format: format, now: now))
        }
        guard !dates.isEmpty else { return self }
        let result = NSMutableString(string: text)
        var updated = entities
        for (date, replacement) in dates.sorted(by: { $0.0.offset > $1.0.offset }) {
            let range = NSRange(location: date.offset, length: date.length)
            guard range.location >= 0, NSMaxRange(range) <= result.length else { continue }
            result.replaceCharacters(in: range, with: replacement)
            let delta = (replacement as NSString).length - date.length
            updated = updated.map { entity in
                let end = entity.offset + entity.length
                if entity == date {
                    return TextEntity(length: entity.length + delta, offset: entity.offset, type: entity.type)
                } else if entity.offset >= NSMaxRange(range) {
                    return TextEntity(length: entity.length, offset: entity.offset + delta, type: entity.type)
                } else if entity.offset <= range.location, end >= NSMaxRange(range) {
                    return TextEntity(length: entity.length + delta, offset: entity.offset, type: entity.type)
                }
                return entity
            }
        }
        return FormattedText(entities: updated, text: result as String)
    }
}
