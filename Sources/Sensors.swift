import Darwin
import Foundation

struct FanInfo {
    var name: String
    var rpm: Int
    var max: Int
}

struct MacmonSample {
    var pFreq = Double.nan, pUsage = Double.nan
    var eFreq = Double.nan, eUsage = Double.nan
    var gFreq = Double.nan, gUsage = Double.nan
    var sysPower = Double.nan
    var cpuTemp = Double.nan, gpuTemp = Double.nan
    var fans: [FanInfo] = []
}

private func num(_ v: Any?) -> Double {
    (v as? NSNumber)?.doubleValue ?? .nan
}

/// macmon pipe が吐く1行JSONをパース。失敗時 nil。
func parseMacmonLine(_ line: String) -> MacmonSample? {
    guard let d = line.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          j["timestamp"] != nil else { return nil }
    var s = MacmonSample()
    for (u, f, p) in [("pcpu_usage", \MacmonSample.pFreq, \MacmonSample.pUsage),
                      ("ecpu_usage", \MacmonSample.eFreq, \MacmonSample.eUsage),
                      ("gpu_usage", \MacmonSample.gFreq, \MacmonSample.gUsage)] as [(String, WritableKeyPath<MacmonSample, Double>, WritableKeyPath<MacmonSample, Double>)] {
        if let a = j[u] as? [Any], a.count >= 2 {
            s[keyPath: f] = num(a[0])
            s[keyPath: p] = num(a[1])
        }
    }
    s.sysPower = num(j["sys_power"])
    if let t = j["temp"] as? [String: Any] {
        s.cpuTemp = num(t["cpu_temp_avg"])
        s.gpuTemp = num(t["gpu_temp_avg"])
    }
    if let fa = j["fans"] as? [[String: Any]] {
        s.fans = fa.map { FanInfo(name: $0["name"] as? String ?? "fan",
                                  rpm: Int(num($0["rpm"])),
                                  max: Int(num($0["max_rpm"]))) }
    }
    return s
}

// ---- コア群の表示名 ----

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

private func perfLabel(_ raw: String?, _ fallback: String) -> String {
    switch raw {
    case "Super": return "最速コア"
    case "Performance": return "高性能コア"
    case "Efficiency": return "省電力コア"
    case .some(let s): return s
    case .none: return fallback
    }
}

/// macmon の pcpu_*=perflevel0, ecpu_*=perflevel1 に対応する表示名
func perfLevelNames() -> (String, String) {
    (perfLabel(sysctlString("hw.perflevel0.name"), "コア群1"),
     perfLabel(sysctlString("hw.perflevel1.name"), "コア群2"))
}

/// 同梱の macmon を最優先、無ければ Homebrew の定番パスを探す
func findMacmon() -> String? {
    [Bundle.main.path(forResource: "macmon", ofType: nil),
     "/opt/homebrew/bin/macmon",
     "/usr/local/bin/macmon"]
        .compactMap { $0 }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}
