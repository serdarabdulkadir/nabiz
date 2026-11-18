import Testing
import Foundation
@testable import NabizCore

@Suite struct HistoryTests {
    @Test func dolunceEskiDuser() {
        var h = History<Int>(capacity: 3)
        for i in 1...5 { h.append(i) }
        #expect(h.values == [3, 4, 5])
        #expect(h.last == 5)
        #expect(h.count == 3)
    }

    @Test func bosVeKismiDolu() {
        var h = History<Int>(capacity: 4)
        #expect(h.isEmpty && h.values.isEmpty && h.last == nil)
        h.append(7); h.append(8)
        #expect(h.values == [7, 8])
    }

    @Test func eskileriAtma() {
        var h = History<HistoryPoint>(capacity: 10)
        for t in [0.0, 100, 200, 700, 800] { h.append(HistoryPoint(ts: t, cpu: 1)) }
        h.removeOldest { $0.ts < 800 - 600 }
        #expect(h.values.map(\.ts) == [200, 700, 800])
        h.append(HistoryPoint(ts: 900))
        #expect(h.values.map(\.ts) == [200, 700, 800, 900])
    }

    @Test func snapshottanNokta() {
        let s = Snapshot(ts: 50, cpu: CPUStats(total: 30, cores: [30]), mem: MemStats(used: 4, total: 8), net: NetStats(up: 1, down: 2))
        let p = HistoryPoint(snapshot: s)
        #expect(p.cpu == 30 && p.mem == 0.5 && p.down == 2 && p.up == 1)
        #expect(HistoryPoint(snapshot: Snapshot(ts: 1)).cpu == nil)
    }
}

@Suite struct ProcessMathTests {
    @Test func tekCekirdekYuzYuz() {
        // 1 sn'de 1 sn CPU zamani = %100; 0.5 sn = %50.
        let top = ProcessMath.top(previous: [1: 0, 2: 0, 3: 10], current: [1: 1_000_000_000, 2: 500_000_000, 3: 10, 4: 99],
                                  elapsedNanos: 1e9, limit: 5)
        #expect(top.map(\.pid) == [1, 2])
        #expect(abs(top[0].percent - 100) < 0.001 && abs(top[1].percent - 50) < 0.001)
    }

    @Test func cokCekirdekYuzuAsabilir() {
        let top = ProcessMath.top(previous: [1: 0], current: [1: 3_000_000_000], elapsedNanos: 1e9, limit: 5)
        #expect(abs(top[0].percent - 300) < 0.001)
    }

    @Test func limitVeGecersizSure() {
        let prev: [Int32: UInt64] = [1: 0, 2: 0, 3: 0]
        let cur: [Int32: UInt64] = [1: 300, 2: 200, 3: 100]
        #expect(ProcessMath.top(previous: prev, current: cur, elapsedNanos: 1000, limit: 2).map(\.pid) == [1, 2])
        #expect(ProcessMath.top(previous: prev, current: cur, elapsedNanos: 0, limit: 2).isEmpty)
    }
}

@Suite struct ThermalTests {
    @Test func cpuEnYuksek() {
        let r: [(name: String, value: Double)] = [("PMU tdie1", 48), ("PMU tdie2", 52.5), ("pACC MTR Temp Sensor0", 50),
                                                   ("gas gauge battery", 31), ("PMU tdie9", -127)]
        #expect(ThermalMath.cpuTemperature(r) == 52.5)
    }

    @Test func cpuSensoruYoksaNil() {
        #expect(ThermalMath.cpuTemperature([("NAND CH0 temp", 30)]) == nil)
        #expect(ThermalMath.cpuTemperature([]) == nil)
    }

    @Test func smcCozum() {
        #expect(SMCDecode.value(type: "ui8 ", bytes: [2]) == 2)
        #expect(SMCDecode.value(type: "fpe2", bytes: [0x1C, 0x20]) == 1800)
        #expect(SMCDecode.value(type: "flt ", bytes: [0x00, 0x00, 0xE6, 0x44]) == 1840)
        #expect(SMCDecode.value(type: "sp78", bytes: [0x34, 0x80]) == 52.5)
        #expect(SMCDecode.value(type: "xxxx", bytes: [1, 2]) == nil)
        #expect(SMCDecode.value(type: "flt ", bytes: [1]) == nil)
    }
}

@Suite struct BluetoothParseTests {
    let json = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
     "device_connected":[
      {"AirPods Pro":{"device_address":"AA","device_batteryLevelLeft":"80%","device_batteryLevelRight":"70%","device_batteryLevelCase":"20%"}},
      {"Magic Mouse":{"device_address":"BB","device_batteryLevelMain":"55%"}},
      {"Klavye":{"device_address":"CC"}}],
     "device_not_connected":[{"Eski":{"device_batteryLevelMain":"10%"}}]}]}
    """

    @Test func profilerCozumu() {
        let d = BluetoothParse.parseProfiler(Data(json.utf8))
        #expect(d.count == 2)
        #expect(d.contains(DeviceBattery(name: "AirPods Pro", percent: 70)))
        #expect(d.contains(DeviceBattery(name: "Magic Mouse", percent: 55)))
    }

    @Test func bozukJSONBos() {
        #expect(BluetoothParse.parseProfiler(Data("x".utf8)).isEmpty)
        #expect(BluetoothParse.parseProfiler(Data("{}".utf8)).isEmpty)
    }

    @Test func birlestirmeAyniAdTekrarsiz() {
        let m = BluetoothParse.merge([[DeviceBattery(name: "B", percent: 1)],
                                      [DeviceBattery(name: "B", percent: 9), DeviceBattery(name: "A", percent: 2)]])
        #expect(m == [DeviceBattery(name: "A", percent: 2), DeviceBattery(name: "B", percent: 1)])
    }
}
