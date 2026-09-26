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
