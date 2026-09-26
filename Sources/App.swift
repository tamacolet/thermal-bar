import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let b = item.button {
            b.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            b.title = monitor.title
            b.target = self
            b.action = #selector(handleClick(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let p = NSPopover()
        let hc = NSHostingController(rootView: PanelView(m: monitor))
        hc.sizingOptions = .preferredContentSize
        p.contentViewController = hc
        p.behavior = .transient
        popover = p

        Publishers.CombineLatest(monitor.$level, monitor.$chipAvg)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusItem?.button?.title = self?.monitor.title ?? ""
            }
            .store(in: &cancellables)
    }

    @objc private func handleClick(_: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp ||
            (e?.type == .leftMouseUp && e?.modifierFlags.contains(.control) == true) {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let b = statusItem?.button, let p = popover else { return }
        if p.isShown {
            p.performClose(nil)
        } else {
            monitor.refreshPowerMode()
            p.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let login = NSMenuItem(title: "ログイン時に起動",
                               action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleLoginItem(_: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "ログイン時に起動を変更できませんでした"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
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
            row(m.perfName0, usage(m.s.pUsage, m.s.pFreq))
            row(m.perfName1, usage(m.s.eUsage, m.s.eFreq))
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
