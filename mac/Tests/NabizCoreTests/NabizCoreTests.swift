import Testing
@testable import NabizCore

@Suite struct CPUTests {
    @Test func farkHesabi() {
        let a = [CoreTicks(user: 100, system: 100, idle: 800, nice: 0), CoreTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let b = [CoreTicks(user: 150, system: 150, idle: 900, nice: 0), CoreTicks(user: 0, system: 0, idle: 1100, nice: 0)]
        let u = CPUSampler.usage(previous: a, current: b)
        #expect(u?.cores == [50, 0])
        #expect(abs((u?.total ?? 0) - 100.0 / 3.0) < 0.001)
    }

    @Test func sayacTasmasi() {
        let a = [CoreTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)]
        let b = [CoreTicks(user: 10, system: 0, idle: 20, nice: 0)]
        let u = CPUSampler.usage(previous: a, current: b)
        #expect(u?.total == 50) // busy 20, idle 20
    }

    @Test func uyumsuzDiziNil() {
        let a = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        #expect(CPUSampler.usage(previous: a, current: a + a) == nil)
        #expect(CPUSampler.usage(previous: [], current: []) == nil)
    }

    @Test func degismeyenSayacSifir() {
        let a = [CoreTicks(user: 5, system: 5, idle: 5, nice: 5)]
        #expect(CPUSampler.usage(previous: a, current: a)?.total == 0)
    }
}

@Suite struct MemoryTests {
    @Test func kullanilan() {
        let used = MemorySampler.usedBytes(internalPages: 1000, purgeablePages: 200, wiredPages: 300, compressedPages: 100, pageSize: 16384)
        #expect(used == 1200 * 16384)
    }

    @Test func purgeableFazlaysa() {
        #expect(MemorySampler.usedBytes(internalPages: 10, purgeablePages: 50, wiredPages: 5, compressedPages: 5, pageSize: 1) == 10)
    }

    @Test func basincAdi() {
        #expect(MemorySampler.pressureName(level: 1) == "normal")
        #expect(MemorySampler.pressureName(level: 2) == "warn")
        #expect(MemorySampler.pressureName(level: 4) == "critical")
        #expect(MemorySampler.pressureName(level: nil) == nil)
    }
}

@Suite struct FormatTests {
    @Test func bayt() {
        #expect(Format.bytes(512) == "512 B")
        #expect(Format.bytes(1536) == "1,5 KB")
        #expect(Format.bytes(16 * 1024 * 1024 * 1024) == "16,0 GB")
        #expect(Format.bytes(500_000_000_000, base: 1000) == "500 GB")
        #expect(Format.bytes(nil) == "--")
    }

    @Test func hizYuzdeSure() {
        #expect(Format.speed(2048) == "2,0 KB/s")
        #expect(Format.speed(nil) == "--")
        #expect(Format.percent(23) == "23%")
        #expect(Format.percent(nil) == "--")
        #expect(Format.percent(fraction: 0.614) == "61%")
        #expect(Format.duration(seconds: 3725) == "1 sa 2 dk")
        #expect(Format.duration(seconds: 90000) == "1 g 1 sa")
        #expect(Format.duration(seconds: nil) == "--")
    }
}

@Suite struct NetworkTests {
    @Test func normalFark() {
        #expect(NetworkSampler.delta(previous: 100, current: 350) == 250)
        #expect(NetworkSampler.rate(previous: 0, current: 2000, seconds: 2) == 1000)
    }

    @Test func tasmaVeKayipSifir() {
        #expect(NetworkSampler.delta(previous: 5000, current: 100) == 0)
        #expect(NetworkSampler.rate(previous: 5000, current: 100, seconds: 2) == 0)
        #expect(NetworkSampler.rate(previous: 0, current: 100, seconds: 0) == 0)
    }
}
