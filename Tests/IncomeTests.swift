import Foundation

@main
struct IncomeTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var settings = IncomeSettings()
        settings.monthlySalary = 21750
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            precondition(condition(), name)
            print("PASS: \(name)")
        }
        func snapshot(_ day: Int, _ hour: Int, _ minute: Int = 0) -> IncomeSnapshot {
            IncomeMath.snapshot(settings, now: date(day, hour, minute), calendar: calendar)
        }
        check("before work earns zero", snapshot(26, 8, 59).earned == 0)
        check("work starts at zero", snapshot(26, 9).earned == 0 && snapshot(26, 9).status == .working)
        check("half shift earns half daily pay", abs(snapshot(26, 13, 30).earned - 500) < 1e-8)
        check("after work caps at daily pay", snapshot(26, 23).earned == 1000 && snapshot(26, 23).status == .finished)
        check("Saturday rests", snapshot(31, 13).earned == 0 && snapshot(31, 13).status == .rest)
        check("Friday after work finds Monday", calendar.component(.day, from: snapshot(30, 19).nextStart!) == 2)
        settings.workdays.append(6)
        check("selected Saturday earns", snapshot(31, 18).earned == 1000)
        settings.workdays = [1, 2, 3, 4, 5]
        settings.workStart = 22 * 60
        settings.workEnd = 6 * 60
        check("Friday shift continues on Saturday", snapshot(31, 2).earned == 500 && snapshot(31, 2).status == .working)
        check("overnight shift reaches full pay before Saturday rest", snapshot(31, 5, 59).earned > 990)
        check("Saturday midnight shift does not start", snapshot(31, 23).earned == 0)
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        settings.workdays = [0, 1, 2, 3, 4, 5, 6]
        settings.workStart = 0
        settings.workEnd = 8 * 60
        let springDay = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8))!
        let spring = IncomeMath.snapshot(settings, now: springDay, calendar: ny)
        check("full DST spring shift still earns one daily amount", spring.earned == 1000)
        let fallDay = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 8))!
        check("full DST fall shift still earns one daily amount", IncomeMath.snapshot(settings, now: fallDay, calendar: ny).earned == 1000)
        for mutate in [
            { (s: inout IncomeSettings) in s.workStart = s.workEnd },
            { (s: inout IncomeSettings) in s.workdays = [] },
            { (s: inout IncomeSettings) in s.monthlySalary = -1 },
            { (s: inout IncomeSettings) in s.monthlyWorkdays = 0 },
            { (s: inout IncomeSettings) in s.currency = "INVALID" }
        ] {
            var bad = settings
            mutate(&bad)
            do { _ = try bad.validated(); fatalError("Invalid settings accepted") }
            catch { print("PASS: rejects invalid settings (\(error.localizedDescription))") }
        }
        settings = IncomeSettings()
        settings.monthlySalary = 6000
        settings.workStart = 600
        settings.workEnd = 1080
        settings.lunchEnabled = true
        settings.lunchStart = 720
        settings.lunchEnd = 780
        settings.lunchPaid = false
        let dayPay = 6000.0 / 21.75
        let expectedBeforeLunch = dayPay * 2 / 7
        check("unpaid lunch starts with correct earned amount", abs(snapshot(26, 12).earned - expectedBeforeLunch) < 1e-8)
        check("unpaid lunch amount stays constant", snapshot(26, 12).earned == snapshot(26, 12, 59).earned)
        check("unpaid lunch progress stays constant", snapshot(26, 12).progress == snapshot(26, 12, 30).progress)
        check("lunch status at start boundary", snapshot(26, 12).status == .lunch)
        check("resume work at end boundary", snapshot(26, 13).status == .working)
        check("no jump at unpaid lunch end", snapshot(26, 13).earned == snapshot(26, 12).earned)
        check("afternoon income resumes", abs(snapshot(26, 14).earned - dayPay * 3 / 7) < 1e-8)
        check("daily income remains unchanged", abs(snapshot(26, 18).earned - dayPay) < 1e-8)
        check("unpaid hourly rate uses seven hours", abs(snapshot(26, 14).perHour - dayPay / 7) < 1e-8)
        check("lunch countdown targets return to work", snapshot(26, 12, 30).timingLabel(now: date(26, 12, 30)) == "距上班 30分钟")
        check("lunch does not activate on rest day", snapshot(31, 12, 30).status == .rest && snapshot(31, 12, 30).earned == 0)
        settings.lunchPaid = true
        check("paid lunch keeps accumulating", snapshot(26, 12, 30).earned > snapshot(26, 12).earned)
        check("paid lunch still identifies lunch status", snapshot(26, 12, 30).status == .lunch)
        check("paid lunch retains eight-hour rate", abs(snapshot(26, 14).perHour - dayPay / 8) < 1e-8)
        settings.lunchEnabled = false
        check("disabled lunch keeps original formula", snapshot(26, 12, 30).status == .working && abs(snapshot(26, 12, 30).earned - dayPay * 2.5 / 8) < 1e-8)
        settings.lunchEnabled = true
        settings.lunchPaid = false
        settings.workStart = 22 * 60
        settings.workEnd = 6 * 60
        settings.lunchStart = 1 * 60
        settings.lunchEnd = 2 * 60
        _ = try settings.validated()
        check("overnight lunch belongs to Friday shift", snapshot(31, 1, 30).status == .lunch)
        check("overnight unpaid lunch pauses income", snapshot(31, 1).earned == snapshot(31, 1, 59).earned)
        check("overnight lunch resumes correctly", snapshot(31, 2).status == .working && abs(snapshot(31, 2).earned - dayPay * 3 / 7) < 1e-8)
        settings.lunchStart = 23 * 60 + 30
        settings.lunchEnd = 30
        _ = try settings.validated()
        check("lunch itself may cross midnight", snapshot(31, 0).status == .lunch && snapshot(31, 0, 30).status == .working)
        for mutate in [
            { (s: inout IncomeSettings) in s.lunchEnd = s.lunchStart },
            { (s: inout IncomeSettings) in s.lunchStart = 20 * 60; s.lunchEnd = 21 * 60 },
            { (s: inout IncomeSettings) in s.lunchStart = 5 * 60; s.lunchEnd = 7 * 60 },
            { (s: inout IncomeSettings) in s.lunchStart = s.workStart; s.lunchEnd = s.workEnd },
            { (s: inout IncomeSettings) in s.lunchStart = -1 }
        ] {
            var invalid = settings
            mutate(&invalid)
            do { _ = try invalid.validated(); fatalError("Invalid lunch accepted") }
            catch { print("PASS: rejects invalid lunch (\(error.localizedDescription))") }
        }
        let legacyJSON = "{\"currency\":\"CNY\",\"monthlySalary\":6000,\"workStart\":600,\"workEnd\":1080,\"monthlyWorkdays\":21.75,\"workdays\":[1,2,3,4,5]}"
        let legacy = try JSONDecoder().decode(IncomeSettings.self, from: Data(legacyJSON.utf8)).validated()
        check("old settings load with lunch disabled", !legacy.lunchEnabled && legacy.monthlySalary == 6000 && legacy.workStart == 600)
        let real = settings
        let experience = settings.millionaireExperience
        check("millionaire annual rate is exactly one million", abs(experience.monthlySalary * 12 - 1_000_000) < 1e-7)
        check("experience preserves schedule", experience.workStart == real.workStart && experience.workEnd == real.workEnd && experience.workdays == real.workdays)
        check("experience preserves lunch and paid days", experience.lunchStart == real.lunchStart && experience.lunchEnd == real.lunchEnd && experience.lunchPaid == real.lunchPaid && experience.lunchEnabled == real.lunchEnabled && experience.monthlyWorkdays == real.monthlyWorkdays)
        check("experience does not mutate real salary", settings == real)
        let realSnapshot = IncomeMath.snapshot(real, now: date(30, 23), calendar: calendar)
        let demoSnapshot = IncomeMath.snapshot(experience, now: date(30, 23), calendar: calendar)
        check("experience preserves work progress and status", realSnapshot.progress == demoSnapshot.progress && realSnapshot.status == demoSnapshot.status)
        check("experience scales earned amount only", abs(demoSnapshot.earned - realSnapshot.earned * experience.monthlySalary / real.monthlySalary) < 1e-7)
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(IncomeSettings.self, from: encoded)
        check("settings survive JSON round trip", decoded == settings)
        check("CNY formatted with yuan symbol", settings.money(123.45).contains("¥123.45"))
        check("countdown rounds remaining seconds up", IncomeSnapshot.duration(1) == "1分钟")
    }
}
