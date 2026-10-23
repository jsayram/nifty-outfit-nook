import CloudKit
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// The CloudKit mapping with real `CKRecord`s (no account needed), the merge rules, and the
/// account-event table (Phase 21b, decision 0004).
@Suite("iCloud sync rules")
struct SyncRulesTests {
    // MARK: CloudKit mapping

    static let garment = Garment(
        id: Garment.ID("2f6b0e1a-5c3d-4e7f-8a9b-0c1d2e3f4a5b"), name: "Lily's red coat", category: .top,
        notes: "From Mum", addedAt: TestTime.now)

    @Test("Only the record name, type and system fields are plain; everything about her is encrypted")
    func encryptedFields() throws {
        let payload = try RecordPayload.encode(Self.garment)
        let record = CloudKitRecordMapping.ckRecord(
            SyncRecord(
                id: SyncRecordID(zone: .closet, name: "garment.\(Self.garment.id.rawValue)"), type: .garment,
                payload: payload, payloadVersion: RecordPayload.currentVersion))
        let encrypted = Set(record.encryptedValues.allKeys())
        #expect(encrypted == ["payload", "payloadVersion", "tombstone"])
        #expect(Set(record.allKeys()).subtracting(encrypted).isEmpty)
        #expect(record.recordType == "Garment")
        #expect(record.recordID.zoneID.zoneName == "Closet")
        // The name is the record's ID, never a word she typed.
        #expect(!record.recordID.recordName.contains("coat"))
        // No references: relationships live in the payload.
        #expect(Set(record.allKeys()).subtracting(encrypted).allSatisfy { !(record[$0] is CKRecord.Reference) })

        let back = try #require(CloudKitRecordMapping.syncRecord(record))
        #expect(back.payload == payload)
        #expect(back.payloadVersion == RecordPayload.currentVersion)
        #expect(!back.isTombstone)
        #expect(back.systemFields != nil)
    }

    @Test("A tombstone has no payload; an image is an asset and nothing else")
    func tombstoneAndImage() throws {
        let tombstone = CloudKitRecordMapping.ckRecord(
            SyncRecord(id: SyncRecordID(zone: .closet, name: "look.abc"), type: .look, isTombstone: true))
        #expect(tombstone.encryptedValues["payload"] as Data? == nil)
        #expect(tombstone.encryptedValues["tombstone"] as Int? == 1)

        let file = FileManager.default.temporaryDirectory.appending(path: "sync-image-\(UUID().uuidString)")
        try Data(repeating: 1, count: 10).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let image = CloudKitRecordMapping.ckRecord(
            SyncRecord(id: SyncSchema.imageID("photo-1", zone: .closet), type: .image, asset: file))
        #expect(image.allKeys() == ["asset"])
        #expect(image.encryptedValues.allKeys().isEmpty)
        #expect((image["asset"] as? CKAsset)?.fileURL == file)
    }

    @Test("System fields round trip, so a save says which version it's based on")
    func systemFields() throws {
        let original = CKRecord(
            recordType: "Garment",
            recordID: CloudKitRecordMapping.recordID(SyncRecordID(zone: .closet, name: "garment.x")))
        let fields = CloudKitRecordMapping.encodeSystemFields(original)
        let rebuilt = CloudKitRecordMapping.ckRecord(
            SyncRecord(
                id: SyncRecordID(zone: .closet, name: "garment.x"), type: .garment, payload: Data("{}".utf8),
                payloadVersion: 1, systemFields: fields))
        #expect(rebuilt.recordID == original.recordID)
        #expect(rebuilt.recordType == original.recordType)
    }

    @Test("CKError codes map to what the app does about them")
    func errors() {
        #expect(CloudKitRecordMapping.failure(CKError(.quotaExceeded)) == .quotaExceeded)
        #expect(CloudKitRecordMapping.failure(CKError(.networkUnavailable)) == .transient)
        #expect(CloudKitRecordMapping.failure(CKError(.zoneNotFound)) == .zoneNotFound)
        #expect(
            CloudKitRecordMapping.failure(
                CKError(.zoneNotFound, userInfo: [CKErrorUserDidResetEncryptedDataKey: true])) == .encryptedDataReset)
        #expect(CloudKitRecordMapping.failure(CKError(.userDeletedZone)) == .userDeletedZone)
        #expect(CloudKitRecordMapping.failure(CKError(.serverRecordChanged)) == .serverRecordChanged(nil))
    }

    @Test("Record names: every synced kind, nothing she typed, and back again")
    func names() throws {
        #expect(SyncSchema.name(kind: .garmentDraft, key: "garment:abc") == "garmentDraft.garment:abc")
        #expect(SyncSchema.name(kind: .look, key: "naïve") == nil)
        let parsed = try #require(SyncSchema.parse("garmentDraft.garment:abc"))
        #expect(parsed.kind == .garmentDraft && parsed.key == "garment:abc")
        #expect(SyncSchema.parse("aiJob.x") == nil)  // never synced
        #expect(SyncSchema.parse("feedbackDraft.only") == nil)
        #expect(SyncSchema.types[.restoreConflict] == nil && SyncSchema.types[.syncState] == nil)
        // Every record type has a fixed, generic name: the production schema can only grow.
        #expect(
            Set(SyncRecordType.allCases.map(\.rawValue)) == [
                "Garment", "Look", "Suitcase", "TryOnPicture", "Profile", "Draft", "AppState", "StylistThread",
                "Image", "Body", "SyncGeneration",
            ])
    }

    // MARK: Merge

    @Test("Pieces merge field by field: one side's change lands, restriction wins, wear days add up")
    func garmentMerge() {
        var ancestor = Self.garment
        ancestor.wornOn = [TestTime.day(-10)]
        var local = ancestor
        local.notes = "Dry clean"
        local.isArchived = true
        local.wornOn.append(TestTime.day(-1))
        var server = ancestor
        server.name = "Red coat"
        server.isArchived = false
        server.laundry = .dirty
        server.wornOn = [TestTime.day(-2)]

        let (merged, conflicts) = SyncMerge.garment(ancestor: ancestor, local: local, server: server)
        #expect(merged.name == "Red coat")
        #expect(merged.notes == "Dry clean")
        #expect(merged.isArchived)
        #expect(merged.laundry == .dirty)
        #expect(Set(merged.wornOn) == [TestTime.day(-1), TestTime.day(-2)])
        #expect(conflicts.isEmpty)

        local.name = "My coat"
        let (both, fields) = SyncMerge.garment(ancestor: ancestor, local: local, server: server)
        #expect(both.name == "Red coat")
        #expect(fields == ["name"])
    }

    @Test("Suitcase memberships merge as sets; other kinds keep the server's whole record")
    func otherMerges() {
        let a = Garment.ID("a")
        let b = Garment.ID("b")
        let c = Garment.ID("c")
        let base = Suitcase(id: Suitcase.ID("s"), name: "Trip", garmentIDs: [a, b], createdAt: TestTime.now)
        var local = base
        local.garmentIDs = [a, b, c]
        var server = base
        server.garmentIDs = [a]
        let (merged, conflicts) = SyncMerge.suitcase(ancestor: base, local: local, server: server)
        #expect(merged.garmentIDs == [a, c])
        #expect(conflicts.isEmpty)

        #expect(SyncMerge.whole(ancestor: 1, local: 1, server: 2) == (2, []))
        #expect(SyncMerge.whole(ancestor: 1, local: 3, server: 1) == (3, []))
        #expect(SyncMerge.whole(ancestor: 1, local: 3, server: 2) == (2, ["record"]))
        #expect(SyncMerge.whole(ancestor: nil, local: 3, server: 2) == (2, ["record"]))
    }

    @Test("The profile's body data is split off and put back")
    func bodySplit() {
        var profile = Profile(signName: "Lily", usualFit: .relaxed, tryOnPhoto: .stored(EntityID("p")))
        profile.measurements.height = Length(160, .centimeters)
        let (closet, body) = SyncBodyData.split(profile)
        #expect(closet.signName == "Lily")
        #expect(closet.measurements.isEmpty && closet.tryOnPhoto == nil && closet.usualFit == nil)
        #expect(body.applied(to: closet) == profile)
    }

    // MARK: Account events (0004's table)

    typealias State = SyncPolicy.State

    @Test(
        "Account changes: signed out pauses, the same account resumes, a different one pauses and uploads nothing",
        arguments: [
            (State(mode: .on, closetAccount: "A"), String?.none, SyncMode.paused(.signedOut)),
            (State(mode: .paused(.signedOut), closetAccount: "A"), "A", .on),
            (State(mode: .on, closetAccount: "A"), "B", .paused(.differentAccount)),
            (State(mode: .paused(.signedOut), closetAccount: "A"), "B", .paused(.differentAccount)),
            (State(mode: .paused(.differentAccount), closetAccount: "A"), "A", .on),
            (State(mode: .off, closetAccount: "A"), "B", .off),
            (State(mode: .deleting, closetAccount: "A"), "B", .deleting),
            (State(mode: .paused(.removedInSettings), closetAccount: "A"), "A", .paused(.removedInSettings)),
        ])
    func accountChanges(state: State, current: String?, expected: SyncMode) {
        let (next, actions) = SyncPolicy.next(state, .account(current: current))
        #expect(next.mode == expected)
        #expect(next.closetAccount == state.closetAccount)  // only her choice changes which account
        if expected != .on { #expect(!actions.contains(.resume) && !actions.contains(.reuploadEverything)) }
    }

    @Test("Zones deleted: by Settings, by another device (with its reason), or an encrypted data reset")
    func zoneDeletions() {
        let on = State(mode: .on, closetAccount: "A")
        #expect(SyncPolicy.next(on, .zoneDeleted(.purged, remote: nil)).0.mode == .paused(.removedInSettings))
        #expect(
            SyncPolicy.next(on, .zoneDeleted(.deleted, remote: .syncTurnedOff)).0.mode
                == .paused(.turnedOffElsewhere))
        #expect(
            SyncPolicy.next(on, .zoneDeleted(.deleted, remote: .deletedEverything)).0.mode
                == .paused(.deletedElsewhere))
        // No reason to read: the safe answer keeps everything here.
        #expect(SyncPolicy.next(on, .zoneDeleted(.deleted, remote: nil)).0.mode == .paused(.turnedOffElsewhere))
        let reset = SyncPolicy.next(on, .zoneDeleted(.encryptedDataReset, remote: nil))
        #expect(reset.0.mode == .on && reset.1 == [.reuploadEverything])
        // Off, nothing happens.
        #expect(SyncPolicy.next(State(mode: .off), .zoneDeleted(.purged, remote: nil)).0.mode == .off)
    }

    @Test("Her answers: only the offered choices do anything, and only copying changes the account")
    func choices() {
        let different = State(mode: .paused(.differentAccount), closetAccount: "A")
        let copied = SyncPolicy.next(different, .choice(.copyToThisAccount, current: "B"))
        #expect(copied.0 == State(mode: .on, closetAccount: "B") && copied.1 == [.reuploadEverything])
        #expect(SyncPolicy.next(different, .choice(.copyToThisAccount, current: nil)).0 == different)
        #expect(SyncPolicy.next(different, .choice(.keepOnThisDevice, current: "B")).0.mode == .off)
        #expect(SyncPolicy.next(different, .choice(.uploadAgain, current: "B")).0 == different)

        let removed = State(mode: .paused(.removedInSettings), closetAccount: "A")
        #expect(SyncPolicy.next(removed, .choice(.uploadAgain, current: "A")).1 == [.reuploadEverything])
        #expect(SyncPolicy.next(removed, .choice(.uploadAgain, current: "B")).0 == removed)
        #expect(SyncPolicy.next(removed, .choice(.deleteHereToo, current: "A")).1 == [.forgetServer, .eraseThisDevice])

        let elsewhere = State(mode: .paused(.deletedElsewhere), closetAccount: "A")
        #expect(SyncPolicy.next(elsewhere, .choice(.keepOnThisDevice, current: "A")).1 == [.forgetServer])
        #expect(SyncPolicy.next(State(mode: .on), .choice(.deleteHereToo, current: "A")).1.isEmpty)
    }
}

extension SyncPolicy.State: CustomTestStringConvertible {
    public var testDescription: String { "\(mode) for \(closetAccount ?? "none")" }
}
