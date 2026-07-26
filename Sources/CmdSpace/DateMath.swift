import Foundation

enum DateMath {
    // TODO: Add locale-specific grammar and localized month, weekday, and
    // holiday aliases. Input parsing is currently English-only.
    private struct ParsedDate {
        let date: Date
        let hasExplicitYear: Bool
    }

    private enum Unit {
        case day
        case week
        case month
        case year
        case businessDay
    }

    static func evaluate(
        _ rawExpression: String,
        now: Date,
        calendar requestedCalendar: Calendar,
        locale: Locale
    ) -> CalculatorResult? {
        var calendar = requestedCalendar
        calendar.locale = locale
        let today = calendar.startOfDay(for: now)
        let expression = normalize(rawExpression)
        guard !expression.isEmpty else { return nil }

        if let captures = captures(
            #"^(business\s+)?days\s+between\s+(.+?)\s+and\s+(.+)$"#,
            in: expression
        ) {
            let businessDays = captures[0] != nil
            guard let dates = datePair(
                captures[1]!,
                captures[2]!,
                today: today,
                calendar: calendar
            ) else {
                return nil
            }
            let count = businessDays
                ? businessDayDifference(from: dates.0, to: dates.1, calendar: calendar)
                : calendar.dateComponents([.day], from: dates.0, to: dates.1).day
            guard let count else { return nil }
            return countResult(count, unit: businessDays ? "business day" : "day")
        }

        if let captures = captures(
            #"^(business\s+)?days\s+until\s+(.+)$"#,
            in: expression
        ) {
            let businessDays = captures[0] != nil
            guard let target = parseDate(
                captures[1]!,
                today: today,
                calendar: calendar,
                preferFuture: true
            )?.date else {
                return nil
            }
            let count = businessDays
                ? businessDayDifference(from: today, to: target, calendar: calendar)
                : calendar.dateComponents([.day], from: today, to: target).day
            guard let count else { return nil }
            return countResult(count, unit: businessDays ? "business day" : "day")
        }

        if let captures = captures(
            #"^(\d+)\s+(business\s+)?(days?|weeks?|months?|years?)\s+(from|after|before)\s+(.+)$"#,
            in: expression
        ) {
            guard let count = Int(captures[0]!),
                  let unit = unit(
                    named: captures[2]!,
                    isBusiness: captures[1] != nil
                  ),
                  let base = parseDate(
                    captures[4]!,
                    today: today,
                    calendar: calendar,
                    preferFuture: false
                  )?.date else {
                return nil
            }
            let direction = captures[3] == "before" ? -1 : 1
            guard let result = add(
                count * direction,
                unit: unit,
                to: base,
                calendar: calendar
            ) else {
                return nil
            }
            return dateResult(result, locale: locale, calendar: calendar)
        }

        if let captures = captures(
            #"^(\d+)\s+(business\s+)?(days?|weeks?|months?|years?)\s+ago$"#,
            in: expression
        ) {
            guard let count = Int(captures[0]!),
                  let unit = unit(
                    named: captures[2]!,
                    isBusiness: captures[1] != nil
                  ),
                  let result = add(-count, unit: unit, to: today, calendar: calendar) else {
                return nil
            }
            return dateResult(result, locale: locale, calendar: calendar)
        }

        if let captures = captures(
            #"^(.+?)\s*([+-])\s*(\d+)\s+(business\s+)?(days?|weeks?|months?|years?)$"#,
            in: expression
        ) {
            guard let base = parseDate(
                captures[0]!,
                today: today,
                calendar: calendar,
                preferFuture: false
            )?.date,
                  let count = Int(captures[2]!),
                  let unit = unit(
                    named: captures[4]!,
                    isBusiness: captures[3] != nil
                  ) else {
                return nil
            }
            let direction = captures[1] == "-" ? -1 : 1
            guard let result = add(
                count * direction,
                unit: unit,
                to: base,
                calendar: calendar
            ) else {
                return nil
            }
            return dateResult(result, locale: locale, calendar: calendar)
        }

        if expression == "today"
            || expression == "tomorrow"
            || expression == "yesterday"
            || expression.hasPrefix("next ") {
            guard let result = parseDate(
                expression,
                today: today,
                calendar: calendar,
                preferFuture: true
            )?.date else {
                return nil
            }
            return dateResult(result, locale: locale, calendar: calendar)
        }

        return nil
    }

    private static func normalize(_ expression: String) -> String {
        var normalized = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
        for prefix in ["what date is ", "what day is ", "date "] {
            if normalized.hasPrefix(prefix) {
                normalized.removeFirst(prefix.count)
                break
            }
        }
        return normalized
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "?.")
            ))
    }

    private static func captures(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: text) else {
                return nil
            }
            return String(text[swiftRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func datePair(
        _ firstText: String,
        _ secondText: String,
        today: Date,
        calendar: Calendar
    ) -> (Date, Date)? {
        let currentYear = calendar.component(.year, from: today)
        guard let first = parseDate(
            firstText,
            today: today,
            calendar: calendar,
            defaultYear: currentYear,
            preferFuture: false
        ) else {
            return nil
        }
        let firstYear = calendar.component(.year, from: first.date)
        guard var second = parseDate(
            secondText,
            today: today,
            calendar: calendar,
            defaultYear: firstYear,
            preferFuture: false
        ) else {
            return nil
        }
        if !second.hasExplicitYear, second.date < first.date,
           let nextYear = parseDate(
               secondText,
               today: today,
               calendar: calendar,
               defaultYear: firstYear + 1,
               preferFuture: false
           ) {
            second = nextYear
        }
        return (first.date, second.date)
    }

    private static func parseDate(
        _ rawText: String,
        today: Date,
        calendar: Calendar,
        defaultYear: Int? = nil,
        preferFuture: Bool
    ) -> ParsedDate? {
        let text = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"^the\s+"#, with: "", options: .regularExpression)

        switch text {
        case "today", "now":
            return ParsedDate(date: today, hasExplicitYear: true)
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: today).map {
                ParsedDate(date: $0, hasExplicitYear: true)
            }
        case "yesterday":
            return calendar.date(byAdding: .day, value: -1, to: today).map {
                ParsedDate(date: $0, hasExplicitYear: true)
            }
        default:
            break
        }

        if text.hasPrefix("next "),
           let weekday = weekdayNumber(String(text.dropFirst(5))) {
            let currentWeekday = calendar.component(.weekday, from: today)
            let difference = (weekday - currentWeekday + 7) % 7
            let daysAhead = difference == 0 ? 7 : difference
            return calendar.date(byAdding: .day, value: daysAhead, to: today).map {
                ParsedDate(date: $0, hasExplicitYear: true)
            }
        }

        if let holiday = holidayComponents(text) {
            return date(
                month: holiday.month,
                day: holiday.day,
                year: defaultYear ?? calendar.component(.year, from: today),
                hasExplicitYear: false,
                today: today,
                calendar: calendar,
                preferFuture: preferFuture
            )
        }

        if let values = captures(
            #"^(\d{4})-(\d{1,2})-(\d{1,2})$"#,
            in: text
        ),
           let year = Int(values[0]!),
           let month = Int(values[1]!),
           let day = Int(values[2]!) {
            return date(
                month: month,
                day: day,
                year: year,
                hasExplicitYear: true,
                today: today,
                calendar: calendar,
                preferFuture: false
            )
        }

        if let values = captures(
            #"^(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?$"#,
            in: text
        ),
           let month = Int(values[0]!),
           let day = Int(values[1]!) {
            let explicitYear = values[2].flatMap(Int.init)
            let normalizedYear = explicitYear.map { $0 < 100 ? 2_000 + $0 : $0 }
            return date(
                month: month,
                day: day,
                year: normalizedYear
                    ?? defaultYear
                    ?? calendar.component(.year, from: today),
                hasExplicitYear: explicitYear != nil,
                today: today,
                calendar: calendar,
                preferFuture: preferFuture
            )
        }

        if let values = captures(
            #"^([a-z]+)\s+(\d{1,2})(?:,?\s+(\d{4}))?$"#,
            in: text
        ),
           let month = monthNumber(values[0]!),
           let day = Int(values[1]!) {
            let explicitYear = values[2].flatMap(Int.init)
            return date(
                month: month,
                day: day,
                year: explicitYear
                    ?? defaultYear
                    ?? calendar.component(.year, from: today),
                hasExplicitYear: explicitYear != nil,
                today: today,
                calendar: calendar,
                preferFuture: preferFuture
            )
        }

        return nil
    }

    private static func date(
        month: Int,
        day: Int,
        year: Int,
        hasExplicitYear: Bool,
        today: Date,
        calendar: Calendar,
        preferFuture: Bool
    ) -> ParsedDate? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard var result = calendar.date(from: components),
              calendar.component(.year, from: result) == year,
              calendar.component(.month, from: result) == month,
              calendar.component(.day, from: result) == day else {
            return nil
        }
        if preferFuture, !hasExplicitYear, result < today {
            components.year = year + 1
            guard let future = calendar.date(from: components) else { return nil }
            result = future
        }
        return ParsedDate(date: result, hasExplicitYear: hasExplicitYear)
    }

    private static func unit(named name: String, isBusiness: Bool) -> Unit? {
        if isBusiness {
            return name.hasPrefix("day") ? .businessDay : nil
        }
        return switch name {
        case "day", "days": .day
        case "week", "weeks": .week
        case "month", "months": .month
        case "year", "years": .year
        default: nil
        }
    }

    private static func add(
        _ value: Int,
        unit: Unit,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        switch unit {
        case .day:
            calendar.date(byAdding: .day, value: value, to: date)
        case .week:
            calendar.date(byAdding: .weekOfYear, value: value, to: date)
        case .month:
            calendar.date(byAdding: .month, value: value, to: date)
        case .year:
            calendar.date(byAdding: .year, value: value, to: date)
        case .businessDay:
            addBusinessDays(value, to: date, calendar: calendar)
        }
    }

    private static func addBusinessDays(
        _ value: Int,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        guard abs(value) <= 100_000 else { return nil }
        if value == 0 { return date }
        let direction = value > 0 ? 1 : -1
        var remaining = abs(value)
        var result = date
        while remaining > 0 {
            guard let next = calendar.date(byAdding: .day, value: direction, to: result) else {
                return nil
            }
            result = next
            if !calendar.isDateInWeekend(result) {
                remaining -= 1
            }
        }
        return result
    }

    private static func businessDayDifference(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> Int? {
        if start == end { return 0 }
        let direction = end > start ? 1 : -1
        guard let totalDays = calendar.dateComponents(
            [.day],
            from: min(start, end),
            to: max(start, end)
        ).day,
              totalDays <= 100_000 else {
            return nil
        }
        var count = 0
        var cursor = start
        while cursor != end {
            guard let next = calendar.date(byAdding: .day, value: direction, to: cursor) else {
                return nil
            }
            cursor = next
            if !calendar.isDateInWeekend(cursor) {
                count += direction
            }
        }
        return count
    }

    private static func countResult(_ count: Int, unit: String) -> CalculatorResult {
        let label = abs(count) == 1 ? unit : "\(unit)s"
        return CalculatorResult(
            value: "\(count) \(label)",
            detail: "Press Return to copy"
        )
    }

    private static func dateResult(
        _ date: Date,
        locale: Locale,
        calendar: Calendar
    ) -> CalculatorResult {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return CalculatorResult(
            value: formatter.string(from: date),
            detail: "Press Return to copy"
        )
    }

    private static func monthNumber(_ name: String) -> Int? {
        let months = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december"
        ]
        let abbreviations = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "oct", "nov", "dec"
        ]
        if let index = months.firstIndex(of: name) {
            return index + 1
        }
        if let index = abbreviations.firstIndex(of: name) {
            return index + 1
        }
        return nil
    }

    private static func weekdayNumber(_ name: String) -> Int? {
        let weekdays = [
            "sunday", "monday", "tuesday", "wednesday",
            "thursday", "friday", "saturday"
        ]
        let abbreviations = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let index = weekdays.firstIndex(of: name) {
            return index + 1
        }
        if let index = abbreviations.firstIndex(of: name) {
            return index + 1
        }
        return nil
    }

    private static func holidayComponents(_ name: String) -> (month: Int, day: Int)? {
        switch name {
        case "new year", "new years", "new year's", "new year's day":
            (1, 1)
        case "independence day", "fourth of july", "4th of july":
            (7, 4)
        case "halloween":
            (10, 31)
        case "christmas", "christmas day":
            (12, 25)
        default:
            nil
        }
    }
}
