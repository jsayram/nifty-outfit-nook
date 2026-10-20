import CloudKit
import Foundation
import Models
import Testing

/// The merge rules as a table, and a garment as a CloudKit record (Phase 20a).
struct CloudKitAndMergeTests {
    static let base = Garment(id: "g-1", name: "Navy trousers", category: .bottom, addedAt: SpikeSeed.epoch)

    @Test func aGarmentRoundTripsThroughACKRecordWithOnlyTheRevisionInTheClear() throws {
        var garment = Self.base
        garment.notes = "Hem taken up"
        garment.availability = .unavailable(until: SpikeSeed.epoch)
        let record = try SpikeCloudKitMapping.record(for: garment, revision: 4)
        // `allKeys()` lists encrypted keys too, but only `encryptedValues` reads them.
        #expect(Set(record.allKeys()) == SpikeCloudKitMapping.plainKeys.union([SpikeCloudKitMapping.payloadKey]))
        #expect(Set(record.encryptedValues.allKeys()) == [SpikeCloudKitMapping.payloadKey])
        #expect(record[SpikeCloudKitMapping.payloadKey] == nil)
        #expect(record["revision"] as? Int == 4)
        #expect(try SpikeCloudKitMapping.garment(from: record) == garment)
        #expect(record.recordID.zoneID.zoneName == "Closet")

        let fields = SpikeCloudKitMapping.systemFields(of: record)
        let restored = try #require(try SpikeCloudKitMapping.record(fromSystemFields: fields))
        #expect(restored.recordID == record.recordID)
        // System fields carry no content, encrypted or not.
        #expect(restored.allKeys().isEmpty)
        #expect(restored.encryptedValues.allKeys().isEmpty)
    }

    /// `CKSyncEngine`'s state is `Codable`, so the app can keep it anywhere, including a row in
    /// the store (D8(d)). A compile-time check: there's no way to make one without iCloud.
    @Test func theSyncEngineStateIsCodable() {
        let type: any (Codable & Sendable).Type = CKSyncEngine.State.Serialization.self
        #expect("\(type)".hasSuffix("Serialization"))
    }

    enum Case: String, CaseIterable, Sendable {
        case onlyLocalChanged
        case onlyServerChanged
        case bothSameValue
        case bothDifferentKeepsServer
        case deletedBeatsRestore
        case dirtyBeatsClean
        case archivedBeatsUnarchived
        case wearDaysUnion
    }

    @Test(arguments: Case.allCases)
    func merge(_ which: Case) {
        var local = Self.base
        var server = Self.base
        var ancestor = Self.base
        switch which {
        case .onlyLocalChanged:
            local.name = "Work trousers"
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            #expect(result.garment.name == "Work trousers" && result.conflicts.isEmpty)
        case .onlyServerChanged:
            server.brand = "COS"
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            #expect(result.garment.brand == "COS" && result.conflicts.isEmpty)
        case .bothSameValue:
            local.name = "Same"
            server.name = "Same"
            #expect(SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server).conflicts.isEmpty)
        case .bothDifferentKeepsServer:
            local.name = "Mine"
            server.name = "Theirs"
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            #expect(result.garment.name == "Theirs")
            #expect(
                result.conflicts == [SpikeConflict(recordName: "g-1", field: "name", kept: "Theirs", competing: "Mine")])
        case .deletedBeatsRestore:
            ancestor.deletedAt = SpikeSeed.epoch
            local.deletedAt = nil
            server.deletedAt = SpikeSeed.epoch.addingTimeInterval(60)
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            #expect(result.garment.isDeleted && result.conflicts.count == 1)
        case .dirtyBeatsClean:
            ancestor.laundry = .clean
            local.laundry = .dirty
            server.laundry = .dirty
            #expect(SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server).garment.laundry == .dirty)
            ancestor.availability = .available
            local.availability = .unavailable(until: nil)
            server.availability = .unavailable(until: SpikeSeed.epoch)
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            #expect(result.garment.availability == .unavailable(until: SpikeSeed.epoch))
            #expect(result.conflicts.map(\.field) == ["availability"])
        case .archivedBeatsUnarchived:
            ancestor.isArchived = true
            local.isArchived = false
            server.isArchived = true
            local.name = "x"
            server.name = "y"
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            // Only the local side changed the archive flag, so the unarchive applies.
            #expect(!result.garment.isArchived)
        case .wearDaysUnion:
            let day = SpikeSeed.epoch
            ancestor.wornOn = [day]
            local.wornOn = [day, day.addingTimeInterval(86_400)]
            server.wornOn = []
            let result = SpikeMergeRules.merge(ancestor: ancestor, local: local, server: server)
            #expect(result.garment.wornOn == [day.addingTimeInterval(86_400)])
        }
    }

    @Test func independentSuitcaseEditsBothApply() {
        let merged = SpikeMergeRules.mergeMembership(
            ancestor: ["g1", "g2", "g3"], local: ["g1", "g2", "g3", "g4"], server: ["g1", "g3"])
        #expect(merged == ["g1", "g3", "g4"])
    }
}
