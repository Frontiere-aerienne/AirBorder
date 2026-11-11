import Foundation
import HealthKit

/// Reads the traveller's walking speed from a connected account.
protocol WalkingDataSource: Sendable {
    var isAvailable: Bool { get }
    /// Shows the system permission sheet. Returns when the traveller has answered.
    func requestAccess() async throws
    /// Average walking speed over recent weeks in km/h, or nil when the account has none.
    func averageWalkingSpeedKmh() async throws -> Double?
}

/// Apple Health: HKQuantityTypeIdentifier.walkingSpeed (recorded by iPhone and Apple Watch).
final class AppleHealthWalkingData: WalkingDataSource, @unchecked Sendable {
    private let store = HKHealthStore()
    private let speedType = HKQuantityType(.walkingSpeed)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [speedType])
    }

    func averageWalkingSpeedKmh() async throws -> Double? {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -28, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let unit = HKUnit.meter().unitDivided(by: .second())
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: speedType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let metresPerSecond = statistics?.averageQuantity()?.doubleValue(for: unit) {
                    continuation.resume(returning: metresPerSecond * 3.6)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }
}

/// Fixed source for UI tests (launch argument `-walkingSpeed <km/h>`).
struct FixedWalkingData: WalkingDataSource {
    let kmh: Double?
    var isAvailable: Bool { true }
    func requestAccess() async throws {}
    func averageWalkingSpeedKmh() async throws -> Double? { kmh }
}

enum PaceText {
    /// "4.6 km/h"
    static func kmh(_ value: Double) -> String {
        String(format: "%.1f km/h", value)
    }
}
