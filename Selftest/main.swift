import Foundation

var failures = 0

func fmt(_ v: Double) -> String { v.isNaN ? "—" : String(format: "%.1f", v) }

func temp(_ label: String, _ v: Double) {
    let ok = !v.isNaN && v >= 0 && v <= 130
    if !ok { failures += 1 }
    print("\(label): \(fmt(v))\(ok ? "" : "  <- NG")")
}

print("熱レベル: \(tb_thermal_level())  (0=Nominal 1=Moderate 2=Heavy 3=Trapping 4=Sleeping)")

let (pn0, pn1) = perfLevelNames()
print("コア群ラベル: \(pn0) / \(pn1)")

_ = tb_smc_init()
print("SMC Taキー数: \(tb_smc_ta_count())")
for i in 0..<tb_smc_ta_count() {
    let k = String(cString: tb_smc_ta_key(i))
    temp("SMC \(k)", tb_smc_read(k))
}
temp("手を置く部分 Ts0P", tb_smc_read("Ts0P"))
temp("手を置く部分 Ts1P", tb_smc_read("Ts1P"))
temp("バッテリー TB0T", tb_smc_read("TB0T"))
temp("本体内部 Ta最大", tb_smc_ta_max())

print("--- HIDセンサー一覧 ---")
tb_hid_list()
print("----------------------")
temp("チップ最大 PMU tdie*", tb_hid_max("PMU tdie"))
temp("SSD NAND CH0 temp", tb_hid_max("NAND CH0 temp"))

let pipe = Pipe()
let p = Process()
let macmonPath = findMacmon() ?? "/opt/homebrew/bin/macmon"
print("macmon パス: \(macmonPath)")
p.executableURL = URL(fileURLWithPath: macmonPath)
p.arguments = ["pipe", "-i", "1000"]
p.standardOutput = pipe
p.standardError = FileHandle.nullDevice
do {
    try p.run()
    var buf = Data()
    let deadline = Date().addingTimeInterval(8)
    while !buf.contains(0x0a) && Date() < deadline && p.isRunning {
        buf.append(pipe.fileHandleForReading.availableData)
    }
    p.terminate()
    if let line = buf.split(separator: 0x0a).first,
       let s = parseMacmonLine(String(decoding: line, as: UTF8.self)) {
        func i(_ v: Double) -> String { v.isNaN ? "—" : "\(Int(v.rounded()))" }
        temp("macmon cpu_temp_avg", s.cpuTemp)
        temp("macmon gpu_temp_avg", s.gpuTemp)
        print("macmon 最速コア: \(i(s.pUsage * 100))% \(i(s.pFreq))MHz")
        print("macmon 高性能コア: \(i(s.eUsage * 100))% \(i(s.eFreq))MHz")
        print("macmon GPU: \(i(s.gUsage * 100))% \(i(s.gFreq))MHz")
        print("macmon sys_power: \(fmt(s.sysPower))W")
        for f in s.fans { print("macmon \(f.name): \(f.rpm)/\(f.max)rpm") }
    } else {
        print("macmon: 取得失敗")
        failures += 1
    }
} catch {
    print("macmon: 起動失敗 \(error)")
    failures += 1
}

print(failures == 0 ? "SELFTEST OK" : "SELFTEST NG (\(failures)件)")
exit(failures == 0 ? 0 : 1)
