import SwiftUI
import AppKit

// Explicit wrapper alias avoids the newer State macro, whose plugin ships with Xcode.
private typealias ViewState<Value> = SwiftUI.State<Value>

enum EditField: Hashable { case currency, salary, start, end }

struct IncomeDisplay: View {
    let settings: IncomeSettings
    let snapshot: IncomeSnapshot
    let now: Date
    var locked = false
    var edit: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("今日收入")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: edit) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("修改设置")
                .help("修改工资与作息，也可右键修改")
            }
            Text(settings.money(snapshot.earned, digits: 3))
                .font(.system(size: 44, weight: .regular))
                .monospacedDigit().tracking(-1.7)
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.4)
                .contentTransition(.numericText(value: snapshot.earned))
                .animation(reduceMotion ? nil : .smooth(duration: 0.8, extraBounce: 0), value: (snapshot.earned * 1000).rounded())
                .accessibilityLabel("今日已赚 \(settings.money(snapshot.earned, digits: 3))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 17)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Text(settings.hoursLabel)
                Spacer(minLength: 4)
                if locked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                Text(snapshot.status == .working ? snapshot.timingLabel(now: now) : snapshot.statusLabel)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(21)
        .frame(width: 292, height: 172)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.primary.opacity(0.045), lineWidth: 0.6))
        .padding(6)
        .frame(width: 304, height: 184)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日收入桌面卡片")
    }
}

struct IncomeCard: View {
    @ObservedObject var store: IncomeStore
    let edit: (EditField) -> Void
    let toggleLock: () -> Void
    var body: some View {
        IncomeDisplay(settings: store.displaySettings, snapshot: store.snapshot, now: store.now, locked: store.locked, edit: { edit(.currency) })
            .contextMenu {
                Button("修改币种…") { edit(.currency) }
                Button("修改工资…") { edit(.salary) }
                Button("修改上班时间…") { edit(.start) }
                Button("修改下班时间…") { edit(.end) }
                Divider()
                Button(store.locked ? "解锁位置" : "锁定位置", action: toggleLock)
            }
    }
}

struct SettingsView: View {
    let initialField: EditField
    let save: (IncomeSettings) throws -> Void
    let cancel: () -> Void
    @ViewState private var draft: IncomeSettings
    @ViewState private var salary: String
    @ViewState private var paidDays: String
    @ViewState private var startDate: Date
    @ViewState private var endDate: Date
    @ViewState private var lunchStartDate: Date
    @ViewState private var lunchEndDate: Date
    @ViewState private var error = ""
    @FocusState private var focus: EditField?

    init(settings: IncomeSettings, initialField: EditField, save: @escaping (IncomeSettings) throws -> Void, cancel: @escaping () -> Void) {
        self.initialField = initialField
        self.save = save
        self.cancel = cancel
        _draft = ViewState(initialValue: settings)
        _salary = ViewState(initialValue: String(format: "%.2f", settings.monthlySalary))
        _paidDays = ViewState(initialValue: String(settings.monthlyWorkdays))
        let shift = IncomeMath.shift(on: Date(), settings: settings)
        _startDate = ViewState(initialValue: shift.start)
        _endDate = ViewState(initialValue: shift.end)
        let calendar = IncomeMath.calendar
        _lunchStartDate = ViewState(initialValue: calendar.date(bySettingHour: settings.lunchStart / 60, minute: settings.lunchStart % 60, second: 0, of: Date())!)
        _lunchEndDate = ViewState(initialValue: calendar.date(bySettingHour: settings.lunchEnd / 60, minute: settings.lunchEnd % 60, second: 0, of: Date())!)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("工资与作息").font(.system(size: 23, weight: .semibold))
                Text("设置会保存在这台 Mac 上。默认金额仅作演示。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding([.horizontal, .top], 24).padding(.bottom, 4)
            Form {
                Section {
                    Picker("币种", selection: $draft.currency) {
                        ForEach(IncomeSettings.currencies, id: \.self) { code in
                            Text("\(code) · \(IncomeSettings.currencyNames[code] ?? code)").tag(code)
                        }
                    }.focused($focus, equals: .currency)
                    TextField("月薪金额", text: $salary).focused($focus, equals: .salary)
                    DatePicker("上班时间", selection: $startDate, displayedComponents: .hourAndMinute).focused($focus, equals: .start)
                    DatePicker("下班时间", selection: $endDate, displayedComponents: .hourAndMinute).focused($focus, equals: .end)
                } footer: {
                    Text("下班时间早于上班时间，视为次日下班。币种只改变单位，不换汇。")
                }
                Section {
                    Toggle("启用午休", isOn: $draft.lunchEnabled)
                    if draft.lunchEnabled {
                        DatePicker("午休开始", selection: $lunchStartDate, displayedComponents: .hourAndMinute)
                        DatePicker("午休结束", selection: $lunchEndDate, displayedComponents: .hourAndMinute)
                        Toggle("午休计薪", isOn: $draft.lunchPaid)
                    }
                } header: {
                    Text("午休")
                } footer: {
                    Text(draft.lunchEnabled ? (draft.lunchPaid ? "午休期间收入继续增长。" : "午休期间暂停增长，日薪按扣除午休后的工作时长分摊。") : "关闭时，整个上班时段连续计薪。")
                }
                Section {
                    TextField("每月计薪天数", text: $paidDays)
                    HStack(spacing: 0) {
                        Text("工作日").frame(width: 58, alignment: .leading)
                        Spacer(minLength: 8)
                        ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { day in
                            Toggle(["日", "一", "二", "三", "四", "五", "六"][day], isOn: Binding(get: { draft.workdays.contains(day) }, set: { selected in
                                if selected { draft.workdays = Array(Set(draft.workdays + [day])).sorted() }
                                else { draft.workdays.removeAll { $0 == day } }
                            }))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("周\(["日", "一", "二", "三", "四", "五", "六"][day])上班")
                        }
                    }
                } header: {
                    Text("计薪规则")
                } footer: {
                    Text("日薪 = 月薪 ÷ 计薪天数，只在工作日的上班时段累计。\n保存修改会按新作息重新估算今日收入，金额可能调整。")
                }
            }
            .formStyle(.grouped)
            if !error.isEmpty {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .accessibilityLabel("设置错误：\(error)")
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Text("点击菜单栏金额查看详情")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存修改", action: submit).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding(18)
        }
        .frame(width: 500, height: 690)
        .onAppear { focus = initialField }
        .onReceive(NotificationCenter.default.publisher(for: .incomeEditField)) { notification in
            if let field = notification.object as? EditField { focus = field }
        }
    }
    private func submit() {
        do {
            guard let amount = Double(salary.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")), let days = Double(paidDays.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SettingsError("请填写有效的工资和计薪天数。") }
            var result = draft
            result.monthlySalary = amount
            result.monthlyWorkdays = days
            let calendar = IncomeMath.calendar
            result.workStart = calendar.component(.hour, from: startDate) * 60 + calendar.component(.minute, from: startDate)
            result.workEnd = calendar.component(.hour, from: endDate) * 60 + calendar.component(.minute, from: endDate)
            result.lunchStart = calendar.component(.hour, from: lunchStartDate) * 60 + calendar.component(.minute, from: lunchStartDate)
            result.lunchEnd = calendar.component(.hour, from: lunchEndDate) * 60 + calendar.component(.minute, from: lunchEndDate)
            try save(result.validated())
        } catch { self.error = error.localizedDescription }
    }
}
