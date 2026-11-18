import Testing
import Foundation
@testable import NabizCore

@Test func systemHealthParsesPercentBothWays() {
    let a = #"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_cycle_count":256,"sppower_battery_health_maximum_capacity":"%90"}}]}"#
    let b = #"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"88%"}}]}"#
    #expect(SystemBatteryHealth.parse(Data(a.utf8)) == 90)
    #expect(SystemBatteryHealth.parse(Data(b.utf8)) == 88)
    #expect(SystemBatteryHealth.parse(Data("{}".utf8)) == nil)
}

@Test func rawCapacityRatio() {
    #expect(BatterySampler.healthPercent(maxCapacity: 4118, designCapacity: 4629) == 89)
}
