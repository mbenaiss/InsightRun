import Foundation
import StoreKit
import StoreKitTest
import XCTest

@testable import insightrun

@MainActor
final class StabilityIntegrationTests: XCTestCase {
    func testMissingHealthDataDoesNotProducePositiveRecoveryAdvice() async {
        let empty = RecoveryMetrics(date: Date())
        XCTAssertNotEqual(empty.coachingRecommendation, empty.recoveryStatus.recommendation)
        let invalid = RecoveryMetrics(date: Date(), restingHeartRate: 0)
        XCTAssertEqual(invalid.coachingRecommendation, empty.coachingRecommendation)
        let available = RecoveryMetrics(date: Date(), restingHeartRate: 55, hrvAverage: 65)
        XCTAssertEqual(available.coachingRecommendation, available.recoveryStatus.recommendation)
    }

    func testConfiguredSubscriptionsCanBePurchasedRestoredAndExpired() async throws {
        let session = try SKTestSession(configurationFileNamed: "insightrun")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let identifiers = ["com.altcode.insightrun.Monthly", "com.altcode.insightrun.Annual"]
        let products = try await Product.products(for: identifiers)
        XCTAssertEqual(Set(products.map(\.id)), Set(identifiers))
        let product = try XCTUnwrap(products.first { $0.id == identifiers[0] })

        guard case .success(.verified(let transaction)) = try await product.purchase() else {
            return XCTFail("The local StoreKit purchase did not produce a verified transaction")
        }
        await transaction.finish()
        try await AppStore.sync()
        var restored = Set<String>()
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let item) = result { restored.insert(item.productID) }
        }
        XCTAssertTrue(restored.contains(product.id))
        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        try session.expireSubscription(productIdentifier: product.id)
        var expired = false
        for _ in 0..<20 {
            expired = try await product.subscription?.status.contains { $0.state == .expired } == true
            if expired { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(expired)
    }

    func testFailedPurchaseAndRestoreSurfaceStoreKitErrors() async throws {
        let session = try SKTestSession(configurationFileNamed: "insightrun")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let products = try await Product.products(for: ["com.altcode.insightrun.Monthly"])
        let product = try XCTUnwrap(products.first)
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        do {
            _ = try await product.purchase()
            XCTFail("A failed payment must not succeed")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        do {
            try await AppStore.sync()
            XCTFail("An offline restore must not succeed")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertFalse(session.allTransactions().contains { $0.state == .purchased || $0.state == .restored })
    }

    func testLargeFITImportPreservesTotalsAndBoundsRetainedSamples() async throws {
        let url = try makeFITFile(records: 70_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let started = ContinuousClock.now
        let workout = try await SuuntoParser.parseAsync(from: url)
        print("Large FIT import elapsed: \(started.duration(to: .now))")
        XCTAssertEqual(workout.duration, 70_000, accuracy: 0.001)
        XCTAssertEqual(workout.distance, 210_000, accuracy: 0.001)
        XCTAssertEqual(workout.averageHeartRate ?? 0, 140, accuracy: 0.001)
        XCTAssertLessThanOrEqual(workout.heartRateSamples.count, 2_000)
        XCTAssertEqual(workout.splits.count, 210)
    }

    func testFITImportCancellationAndMalformedInputDoNotSucceed() async throws {
        let url = try makeFITFile(records: 70_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let parsing = Task { try await SuuntoParser.parseAsync(from: url) }
        parsing.cancel()
        do {
            _ = try await parsing.value
            XCTFail("Cancelled parsing must not return a workout")
        } catch is CancellationError {
        }
        try Data("invalid FIT".utf8).write(to: url)
        do {
            _ = try await SuuntoParser.parseAsync(from: url)
            XCTFail("Malformed FIT data must not return a workout")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    private func makeFITFile(records: Int) throws -> URL {
        var payload = Data()
        func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func definition(local: UInt8, global: UInt16, fields: [(UInt8, UInt8, UInt8)]) {
            payload.append(contentsOf: [0x40 | local, 0, 0])
            append(global, to: &payload)
            payload.append(UInt8(fields.count))
            for field in fields { payload.append(contentsOf: [field.0, field.1, field.2]) }
        }
        let start: UInt32 = 1_158_278_400
        definition(local: 0, global: 20, fields: [(253, 4, 0x86), (5, 4, 0x86), (3, 1, 2)])
        for index in 1...records {
            payload.append(0)
            append(start + UInt32(index), to: &payload)
            append(UInt32(index * 300), to: &payload)
            payload.append(140)
        }
        definition(local: 1, global: 18, fields: [(2, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86), (5, 1, 0)])
        payload.append(1)
        append(start, to: &payload)
        append(UInt32(records * 1_000), to: &payload)
        append(UInt32(records * 300), to: &payload)
        payload.append(1)
        var data = Data([14, 0x20])
        append(UInt16(2300), to: &data)
        append(UInt32(payload.count), to: &data)
        data.append(contentsOf: ".FIT".utf8)
        append(fitCRC(data), to: &data)
        data.append(payload)
        append(fitCRC(data), to: &data)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString).fit")
        try data.write(to: url)
        return url
    }

    private func fitCRC(_ bytes: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }
}
