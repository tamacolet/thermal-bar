import AppKit
import Foundation

final class Monitor: ObservableObject {
    @Published private(set) var level = -1
    @Published private(set) var chipAvg = Double.nan
    @Published private(set) var gpuTemp = Double.nan
    @Published private(set) var palm = Double.nan
    @Published private(set) var battery = Double.nan
    @Published private(set) var internalMax = Double.nan
    @Published private(set) var ssd = Double.nan
    @Published private(set) var s = MacmonSample()
    @Published private(set) var powerMode = -1

    let perfName0: String
    let perfName1: String

    private var proc: Process?
    private var pending = Data()
    private var retry: Timer?
    private var stopping = false
    private let macmonPath: String?

    var title: String {
        let dot = level < 0 ? "⚪" : level == 0 ? "🟢" : level == 1 ? "🟡" : "🔴"
        return "\(dot) \(chipAvg.isNaN ? "—" : "\(Int(chipAvg.rounded()))")°"
    }

    init() {
        (perfName0, perfName1) = perfLevelNames()
        macmonPath = findMacmon()
        tb_smc_init()
        poll()
        refreshPowerMode()
        startMacmon()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.shutdown()
        }
    }

    private func shutdown() {
        stopping = true
        retry?.invalidate()
        proc?.terminationHandler = nil
        proc?.terminate()
        proc = nil
    }

    // SMC/HID/熱レベルの定期読み取り（2秒ごと）
    private func poll() {
        DispatchQueue.global(qos: .utility).async {
            let level = Int(tb_thermal_level())
            let palm = Self.maxV(tb_smc_read("Ts0P"), tb_smc_read("Ts1P"))
            let batt = tb_smc_read("TB0T")
            let imax = tb_smc_ta_max()
            let ssd = tb_hid_max("NAND CH0 temp")
            DispatchQueue.main.async {
                self.level = level
                self.palm = palm
                self.battery = batt
                self.internalMax = imax
                self.ssd = ssd
            }
        }
    }

    private static func maxV(_ a: Double, _ b: Double) -> Double {
        if a.isNaN { return b }
        if b.isNaN { return a }
        return max(a, b)
    }

    // ---- macmon 子プロセス ----

    private func startMacmon() {
        guard !stopping, proc == nil, let path = macmonPath,
              FileManager.default.isExecutableFile(atPath: path) else { return }
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["pipe", "-i", "2000"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.macmonDied() }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if !d.isEmpty { self?.ingest(d) }
        }
        do {
            try p.run()
            proc = p
        } catch {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retry?.invalidate()
        retry = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.startMacmon()
        }
    }

    private func macmonDied() {
        proc = nil
        s = MacmonSample()
        if !stopping { scheduleRetry() }
    }

    private func ingest(_ d: Data) {
        pending.append(d)
        while let nl = pending.firstIndex(of: 0x0a) {
            let line = pending.prefix(upTo: nl)
            pending.removeFirst(pending.distance(from: pending.startIndex, to: nl) + 1)
            if let v = parseMacmonLine(String(decoding: line, as: UTF8.self)) {
                DispatchQueue.main.async { self.apply(v) }
            }
        }
    }

    private func apply(_ v: MacmonSample) {
        s = v
        chipAvg = v.cpuTemp
        gpuTemp = v.gpuTemp
    }

    // ---- 電力モード（起動時とパネル表示時に読む） ----

    func refreshPowerMode() {
        DispatchQueue.global(qos: .utility).async {
            let g = Self.pmset(["-g"])
            var mode = -1
            if let r = g.range(of: #"powermode\s+(-?\d+)"#, options: .regularExpression),
               let v = Int(g[r].split(whereSeparator: \.isWhitespace).last ?? "") {
                mode = v
            }
            DispatchQueue.main.async {
                self.powerMode = mode
            }
        }
    }

    private static func pmset(_ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
}
