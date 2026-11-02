import Foundation

struct IncomeSettings: Codable, Equatable {
    static let currencies = ["CNY", "MYR", "TWD", "USD", "HKD", "EUR", "JPY", "GBP", "SGD"]
    static let currencyNames = ["CNY": "人民币", "MYR": "马币", "TWD": "新台币", "USD": "美元", "HKD": "港币", "EUR": "欧元", "JPY": "日元", "GBP": "英镑", "SGD": "新加坡元"]
    var currency = "CNY"
    var monthlySalary = 5000.0
    var workStart = 9 * 60
    var workEnd = 18 * 60
    var monthlyWorkdays = 21.75
    var lunchEnabled = false
    var lunchStart = 12 * 60
    var lunchEnd = 13 * 60
    var lunchPaid = false
    var workdays = [1, 2, 3, 4, 5] // Sunday=0. Overnight shifts belong to their start day.

    init() {}
    enum CodingKeys: String, CodingKey {
        case currency, monthlySalary, workStart, workEnd, monthlyWorkdays, workdays
        case lunchEnabled, lunchStart, lunchEnd, lunchPaid
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currency = try values.decode(String.self, forKey: .currency)
        monthlySalary = try values.decode(Double.self, forKey: .monthlySalary)
        workStart = try values.decode(Int.self, forKey: .workStart)
        workEnd = try values.decode(Int.self, forKey: .workEnd)
        monthlyWorkdays = try values.decode(Double.self, forKey: .monthlyWorkdays)
        workdays = try values.decode([Int].self, forKey: .workdays)
        lunchEnabled = try values.decodeIfPresent(Bool.self, forKey: .lunchEnabled) ?? false
        lunchStart = try values.decodeIfPresent(Int.self, forKey: .lunchStart) ?? 720
        lunchEnd = try values.decodeIfPresent(Int.self, forKey: .lunchEnd) ?? 780
        lunchPaid = try values.decodeIfPresent(Bool.self, forKey: .lunchPaid) ?? false
    }
    var shiftMinutes: Int { (workEnd - workStart + 1440) % 1440 }
    var lunchStartOffset: Int { (lunchStart - workStart + 1440) % 1440 }
    var lunchMinutes: Int { (lunchEnd - lunchStart + 1440) % 1440 }
    var lunchLabel: String { "\(Self.clock(lunchStart))–\(Self.clock(lunchEnd)) · \(lunchPaid ? "计薪" : "不计薪")" }

    func validated() throws -> IncomeSettings {
        guard Self.currencies.contains(currency) else { throw SettingsError("请选择有效币种。") }
        guard monthlySalary.isFinite, monthlySalary >= 0, monthlySalary <= 10_000_000 else { throw SettingsError("月薪须介于 0 和 10,000,000 之间。") }
        guard (0..<1440).contains(workStart), (0..<1440).contains(workEnd), workStart != workEnd else { throw SettingsError("上下班时间无效，且不能相同。") }
        guard monthlyWorkdays.isFinite, monthlyWorkdays > 0, monthlyWorkdays <= 31 else { throw SettingsError("每月计薪天数须大于 0，且不超过 31。") }
        guard !workdays.isEmpty, workdays.allSatisfy({ (0...6).contains($0) }) else { throw SettingsError("请至少选择一个工作日。") }
        if lunchEnabled {
            guard (0..<1440).contains(lunchStart), (0..<1440).contains(lunchEnd), lunchMinutes > 0 else { throw SettingsError("午休开始和结束时间无效，且不能相同。") }
            guard lunchStartOffset + lunchMinutes <= shiftMinutes else { throw SettingsError("午休必须完整落在上班到下班的时段内。") }
            guard lunchMinutes < shiftMinutes else { throw SettingsError("午休不能占满整个工作时段。") }
        }
        var copy = self
        copy.workdays = Array(Set(workdays)).sorted()
        return copy
    }

    var millionaireExperience: IncomeSettings {
        var experience = self
        experience.monthlySalary = 1_000_000.0 / 12
        return experience
    }
    var dailySalary: Double { monthlySalary / monthlyWorkdays }
    var overnight: Bool { workEnd < workStart }
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    var hoursLabel: String { "\(Self.clock(workStart))–\(Self.clock(workEnd))\(overnight ? " 次日" : "")" }
    func money(_ amount: Double, digits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.currencySymbol = ["CNY": "¥", "MYR": "RM ", "TWD": "NT$", "USD": "US$", "HKD": "HK$", "EUR": "€", "JPY": "JP¥", "GBP": "£", "SGD": "S$"][currency]
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
    }
}

struct SettingsError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct WorkShift {
    let start: Date
    let end: Date
}

struct IncomeSnapshot {
    enum Status { case before, working, lunch, finished, rest }
    let shift: WorkShift
    let status: Status
    let earned: Double
    let progress: Double
    let nextStart: Date?
    let lunchEnd: Date?
    let perHour: Double
    var statusLabel: String {
        switch status {
        case .before: return "尚未上班"
        case .working: return "正在赚钱"
        case .lunch: return "午休中"
        case .finished: return "今日已下班"
        case .rest: return "今天休息"
        }
    }
    func timingLabel(now: Date) -> String {
        if status == .lunch, let end = lunchEnd { return "距上班 \(Self.duration(end.timeIntervalSince(now)))" }
        if status == .working { return "距下班 \(Self.duration(shift.end.timeIntervalSince(now)))" }
        if let next = nextStart { return "距上班 \(Self.duration(next.timeIntervalSince(now)))" }
        return "按工作时间自动计薪"
    }
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(ceil(interval / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)天 \((minutes % 1440) / 60)小时" }
        if minutes >= 60 { return "\(minutes / 60)小时 \(minutes % 60)分钟" }
        return "\(minutes)分钟"
    }
}

enum IncomeMath {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
    static func shift(on day: Date, settings: IncomeSettings, calendar: Calendar = calendar) -> WorkShift {
        // Match calendar wall-clock times rather than adding a fixed number of seconds across DST.
        var startParts = calendar.dateComponents([.year, .month, .day], from: day)
        startParts.hour = settings.workStart / 60
        startParts.minute = settings.workStart % 60
        startParts.second = 0
        let nextDay = settings.overnight ? calendar.date(byAdding: .day, value: 1, to: day)! : day
        var endParts = calendar.dateComponents([.year, .month, .day], from: nextDay)
        endParts.hour = settings.workEnd / 60
        endParts.minute = settings.workEnd % 60
        endParts.second = 0
        return WorkShift(start: calendar.date(from: startParts)!, end: calendar.date(from: endParts)!)
    }
    static func lunch(in shift: WorkShift, settings: IncomeSettings, calendar: Calendar) -> WorkShift? {
        guard settings.lunchEnabled else { return nil }
        func boundary(offset: Int) -> Date {
            let total = settings.workStart + offset
            let day = calendar.date(byAdding: .day, value: total / 1440, to: shift.start)!
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = total % 1440 / 60
            parts.minute = total % 60
            parts.second = 0
            return calendar.date(from: parts)!
        }
        return WorkShift(start: boundary(offset: settings.lunchStartOffset), end: boundary(offset: settings.lunchStartOffset + settings.lunchMinutes))
    }
    static func isWorkday(_ day: Date, settings: IncomeSettings, calendar: Calendar) -> Bool {
        settings.workdays.contains(calendar.component(.weekday, from: day) - 1)
    }
    static func snapshot(_ settings: IncomeSettings, now: Date, calendar: Calendar = calendar) -> IncomeSnapshot {
        var shift = shift(on: now, settings: settings, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let previous = Self.shift(on: yesterday, settings: settings, calendar: calendar)
        if settings.overnight && now < previous.end && isWorkday(yesterday, settings: settings, calendar: calendar) { shift = previous }
        let workday = isWorkday(shift.start, settings: settings, calendar: calendar)
        let pause = lunch(in: shift, settings: settings, calendar: calendar)
        let excluded = pause != nil && !settings.lunchPaid ? pause!.end.timeIntervalSince(pause!.start) : 0
        let length = shift.end.timeIntervalSince(shift.start) - excluded
        let elapsed = max(0, min(now, shift.end).timeIntervalSince(shift.start))
        let pausedElapsed = pause != nil && !settings.lunchPaid ? max(0, min(now, pause!.end).timeIntervalSince(pause!.start)) : 0
        let progress = workday && length > 0 ? max(0, min(1, (elapsed - pausedElapsed) / length)) : 0
        let inLunch = pause.map { now >= $0.start && now < $0.end } ?? false
        let status: IncomeSnapshot.Status = !workday ? .rest : now < shift.start ? .before : now >= shift.end ? .finished : inLunch ? .lunch : .working
        var nextStart: Date?
        for offset in 0...8 {
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            let candidate = Self.shift(on: day, settings: settings, calendar: calendar)
            if candidate.start > now && isWorkday(day, settings: settings, calendar: calendar) { nextStart = candidate.start; break }
        }
        return IncomeSnapshot(shift: shift, status: status, earned: settings.dailySalary * progress, progress: progress, nextStart: nextStart, lunchEnd: pause?.end, perHour: length > 0 ? settings.dailySalary / (length / 3600) : 0)
    }
}
