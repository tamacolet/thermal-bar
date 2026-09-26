import AppKit
import SwiftUI

@main
struct ThermalBarApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            PanelView(m: monitor)
        } label: {
            Text(monitor.title)
        }
        .menuBarExtraStyle(.window)
    }
}

struct PanelView: View {
    @ObservedObject var m: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("状態", statusText)
            section("温度")
            row("CPU", t(m.chipAvg))
            row("GPU", t(m.gpuTemp))
            row("手を置く部分", t(m.palm))
            row("バッテリー", t(m.battery))
            row("SSD", t(m.ssd))
            row("本体内部", t(m.internalMax))
            section("チップの動き")
            row("最速コア", usage(m.s.pUsage, m.s.pFreq))
            row("高性能コア", usage(m.s.eUsage, m.s.eFreq))
            row("GPU", usage(m.s.gUsage, m.s.gFreq))
            row("消費電力", m.s.sysPower.isNaN ? "—" : String(format: "%.1fW", m.s.sysPower))
            section("ファン・電源")
            if m.s.fans.isEmpty {
                row("ファン", "—")
            } else {
                ForEach(Array(m.s.fans.enumerated()), id: \.offset) { e in
                    row(m.s.fans.count > 1 ? "ファン\(e.offset + 1)" : "ファン",
                        "\(e.element.rpm) / \(e.element.max)rpm")
                }
            }
            row("電力モード", powerText)
            Divider()
            HStack {
                Spacer()
                Button("終了") { NSApplication.shared.terminate(nil) }
                Spacer()
            }
        }
        .padding(10)
        .frame(width: 260)
        .onAppear { m.refreshPowerMode() }
    }

    private var statusText: String {
        switch m.level {
        case 0: return "正常"
        case 1: return "やや高い"
        case 2: return "速度低下中"
        case 3: return "強く低下中"
        case 4: return "停止寸前"
        default: return "不明"
        }
    }

    private var powerText: String {
        switch m.powerMode {
        case 0: return "自動"
        case 1: return "低電力"
        case 2: return "高パワー"
        default: return "不明"
        }
    }

    private func t(_ v: Double) -> String {
        v.isNaN ? "—" : String(format: "%.0f℃", v)
    }

    private func usage(_ u: Double, _ f: Double) -> String {
        let up = u.isNaN ? "—" : String(format: "%.0f%%", u * 100)
        let fp = f.isNaN ? "—" : String(format: "%.0fMHz", f)
        return "\(up) · \(fp)"
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).monospacedDigit()
        }
    }

    private func section(_ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(s).font(.caption).foregroundStyle(.secondary)
        }
    }
}
