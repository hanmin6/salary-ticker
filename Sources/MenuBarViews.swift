import SwiftUI

struct IncomeDetails: View {
    @ObservedObject var store: IncomeStore
    let edit: () -> Void
    let loginEnabled: () -> Bool
    let toggleLogin: () -> Void
    let quit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let snapshot = store.snapshot
        let settings = store.displaySettings
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(store.millionaireMode ? "百万年薪体验" : "今日收入").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(snapshot.statusLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(settings.money(snapshot.earned, digits: 3))
                .font(.system(size: 40, weight: .regular)).monospacedDigit().tracking(-1.4)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentTransition(.numericText(value: snapshot.earned))
                .animation(reduceMotion ? nil : .smooth(duration: 0.8, extraBounce: 0), value: (snapshot.earned * 1000).rounded())
                .accessibilityLabel("今日已赚 \(settings.money(snapshot.earned, digits: 3))")
            VStack(spacing: 9) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.07))
                        Capsule().fill(.primary.opacity(0.45)).frame(width: geometry.size.width * snapshot.progress)
                    }
                }.frame(height: 3)
                HStack {
                    Text(snapshot.timingLabel(now: store.now))
                    Spacer()
                    Text("\(Int((snapshot.progress * 100).rounded()))%")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(spacing: 11) {
                detail("工作时间", settings.hoursLabel)
                if settings.lunchEnabled { detail("午休", settings.lunchLabel) }
                detail(store.millionaireMode ? "体验月薪" : "月薪", settings.money(settings.monthlySalary))
                detail("日薪估算", settings.money(settings.dailySalary))
                detail("每小时", settings.money(snapshot.perHour))
            }
            MillionaireButton(active: store.millionaireMode, action: store.toggleMillionaireMode)
            if store.millionaireMode {
                Text("体验金额 · 年薪 100 万 ÷ 12，退出后恢复真实工资")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("修改设置", action: edit).buttonStyle(.borderless)
                Spacer()
                Menu {
                    Button(loginEnabled() ? "关闭开机启动" : "开启开机启动", action: toggleLogin)
                    Divider()
                    Button("退出今日收入", action: quit)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 22, height: 18)
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多选项")
            }.font(.system(size: 11))
        }
        .padding(22)
        .frame(width: 308)
        .tint(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日收入详情")
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.system(size: 11))
    }
}

struct MillionaireButton: View {
    let active: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
                let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.5) / 3.5
                HStack(spacing: 7) {
                    Image(systemName: active ? "arrow.uturn.backward" : "sparkles")
                    Text(active ? "退出百万年薪体验" : "一键体验年薪百万")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.34, green: 0.22, blue: 0.06))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background {
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.85, green: 0.65, blue: 0.29), Color(red: 1, green: 0.91, blue: 0.61), Color(red: 0.91, green: 0.73, blue: 0.37)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 45).rotationEffect(.degrees(22))
                            .offset(x: (geometry.size.width + 110) * phase - 65)
                    }.allowsHitTesting(false)
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 0.7))
                .shadow(color: Color(red: 0.85, green: 0.63, blue: 0.2).opacity(0.22), radius: 6, y: 2)
                .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .help(active ? "恢复真实工资，原设置不变" : "临时按年薪一百万体验，工作与午休时间不变")
    }
}
