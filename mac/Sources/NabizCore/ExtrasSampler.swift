// Mac'e ozel ek olcumler (protokol Snapshot'inin disinda): surecler, sicaklik, fan. Ana is parcacigi disinda.
import Foundation

public struct MacExtras: Sendable, Equatable {
    public var processes: [ProcessUsage] = []
    /// C; okunamazsa nil.
    public var temperature: Double?
    /// rpm; fansiz Mac'te bos.
    public var fans: [Int] = []
    public init() {}
}

public actor ExtrasSampler {
    private let processSampler = ProcessSampler()
    public init() {}

    public func sample(processes: Bool, sensors: Bool) async -> MacExtras {
        var e = MacExtras()
        if processes { e.processes = await processSampler.sample(limit: 5) }
        if sensors {
            e.temperature = ThermalSampler.cpuTemperature()
            e.fans = ThermalSampler.fanSpeeds()
        }
        return e
    }
}
