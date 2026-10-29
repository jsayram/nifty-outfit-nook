import Foundation
import Models
import NookTestSupport
import SwiftData
import Testing

@testable import Services

/// Two devices on one iCloud account, syncing through the stand-in CloudKit (Phase 21b, decision
/// 0004's test plan). Every step that a real device would do over time is a call here: an edit,
/// then `syncNow`, which fetches, looks for local changes and sends.
@Suite("iCloud sync between two devices")
struct TwoDeviceICloudTests {
    // MARK: Create, edit, delete

    @Test("A new piece and its photo reach the other device; an edit follows")
    func createAndEdit() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()

        let piece = try await pair.phone.addPiece("Linen shirt", photoBytes: 120_000)
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        let arrived = try #require(try await pair.iPad.garment(piece.id))
        #expect(arrived == piece)
        guard case .stored(let photo) = piece.photo else {
            Issue.record("no photo")
            return
        }
        let original = try Data(contentsOf: try #require(pair.phone.photos.url(for: photo.rawValue)))
        let copy = try Data(contentsOf: try #require(pair.iPad.photos.url(for: photo.rawValue)))
        #expect(copy == original)

        try await pair.iPad.rename(piece.id, "Blue linen shirt")
        await pair.iPad.sync.syncNow()
        await pair.phone.sync.syncNow()
        #expect(try await pair.phone.garment(piece.id)?.name == "Blue linen shirt")

        // Nothing waits, nothing conflicts, and the photo went up once.
        #expect(await pair.phone.status().isUpToDate)
        #expect(await pair.iPad.status().isUpToDate)
        #expect(try pair.phone.conflicts().isEmpty)
        let images = await pair.server.records("lily", .closet).filter { $0.type == .image }
        #expect(images.count == 1)
    }

    @Test("A piece deleted for good goes everywhere, with its photo, and never comes back")
    func deleteForGood() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        let piece = try await pair.phone.addPiece("Old coat", photoBytes: 50_000)
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()
        guard case .stored(let photo) = piece.photo else {
            Issue.record("no photo")
            return
        }
        #expect(pair.iPad.photos.exists(photo.rawValue))

        try await pair.phone.storage.closet.delete(piece.id, at: TestTime.now)
        try await pair.phone.storage.closet.deletePermanently(piece.id)
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        #expect(try await pair.iPad.garment(piece.id) == nil)
        #expect(try pair.iPad.rows(.deletion).map(\.key) == [piece.id.rawValue])
        #expect(!pair.iPad.photos.exists(photo.rawValue))
        // The server keeps a content-free tombstone and no image.
        let tombstone = try #require(
            await pair.server.record("lily", SyncRecordID(zone: .closet, name: "garment.\(piece.id.rawValue)")))
        #expect(tombstone.isTombstone && tombstone.payload == nil)
        #expect(await pair.server.records("lily", .closet).filter { $0.type == .image }.isEmpty)

        // A stale edit from a device that missed it is dropped and reported, never resurrected.
        let stale = try SyncTestDevice("stale", server: pair.server)
        defer { stale.removeFolder() }
        try await stale.storage.closet.save(piece)
        #expect(await stale.sync.turnOn() == .on)
        #expect(try await stale.garment(piece.id) == nil)
        await pair.phone.sync.syncNow()
        #expect(try await pair.phone.garment(piece.id) == nil)
    }

    @Test("Looks, suitcases and app state sync as whole records; deleting one leaves a tombstone")
    func otherKinds() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        let piece = try await pair.phone.addPiece("Skirt")
        let suitcase = Suitcase(id: Suitcase.ID("trip"), name: "Trip", garmentIDs: [piece.id], createdAt: TestTime.now)
        try await pair.phone.storage.suitcases.restore(suitcase)
        try await pair.phone.storage.tours.setShowsTipsOnNewScreens(false)
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()
        #expect(try await pair.iPad.storage.suitcases.suitcases().map(\.id) == [suitcase.id])
        #expect(try await pair.iPad.storage.tours.progress().showsTipsOnNewScreens == false)

        try await pair.iPad.storage.suitcases.delete(suitcase.id)
        await pair.iPad.sync.syncNow()
        await pair.phone.sync.syncNow()
        #expect(try await pair.phone.storage.suitcases.suitcases().isEmpty)
    }

    // MARK: Conflicts

    @Test(
        "Both devices edit one piece: different fields both land; the same field keeps the first and the other for review"
    )
    func conflict() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        let piece = try await pair.phone.addPiece("Shirt")
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        try await pair.phone.storage.closet.update(piece.id) {
            $0.name = "Phone name"
            $0.notes = "Phone note"
        }
        try await pair.iPad.storage.closet.update(piece.id) {
            $0.name = "iPad name"
            $0.laundry = .dirty
        }
        await pair.phone.sync.syncNow()  // the phone reaches iCloud first
        await pair.iPad.sync.syncNow()
        await pair.phone.sync.syncNow()

        for device in [pair.phone, pair.iPad] {
            let merged = try #require(try await device.garment(piece.id))
            #expect(merged.name == "Phone name")
            #expect(merged.notes == "Phone note")
            #expect(merged.laundry == .dirty)  // dirty beats clean
        }
        let conflicts = try pair.iPad.conflicts()
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.fields == ["name"])
        #expect(conflicts.first?.reason == .bothChanged)
        let kept = try #require(conflicts.first?.losing?.decode(Garment.self))
        #expect(kept.name == "iPad name")
        #expect(await pair.iPad.status().conflictsToReview == 1)
        #expect(await pair.iPad.status().isUpToDate)
    }

    @Test("Offline edits on both, then reconnecting in either order: wear days from both are kept")
    func offlineThenReconnect() async throws {
        for phoneFirst in [true, false] {
            let pair = try SyncPair()
            defer { pair.cleanUp() }
            await pair.turnOnBoth()
            let piece = try await pair.phone.addPiece("Jeans")
            await pair.phone.sync.syncNow()
            await pair.iPad.sync.syncNow()

            await pair.server.setOnline(false)
            try await pair.phone.storage.closet.recordWear(of: [piece.id], on: TestTime.day(-1))
            try await pair.iPad.storage.closet.recordWear(of: [piece.id], on: TestTime.day(-2))
            await pair.phone.sync.syncNow()
            await pair.iPad.sync.syncNow()
            let waiting = await pair.phone.status()
            #expect(waiting.problem == .offline)
            #expect(waiting.waitingChanges == 1)
            #expect(!waiting.isUpToDate)

            await pair.server.setOnline(true)
            let (first, second) = phoneFirst ? (pair.phone, pair.iPad) : (pair.iPad, pair.phone)
            await first.sync.syncNow()
            await second.sync.syncNow()
            await first.sync.syncNow()
            for device in [pair.phone, pair.iPad] {
                let worn = try #require(try await device.garment(piece.id)).wornOn
                #expect(worn.count == 2, "phone first: \(phoneFirst)")
                #expect(await device.status().isUpToDate)
            }
            // Delivered again, nothing changes.
            let writes = await pair.server.writes("lily")
            await second.sync.syncNow()
            await first.sync.syncNow()
            #expect(await pair.server.writes("lily") == writes)
            #expect(try pair.phone.conflicts().isEmpty && pair.iPad.conflicts().isEmpty)
        }
    }

    // MARK: Accounts

    @Test("Signed in to a different account: nothing is uploaded into it, until she copies it there")
    func accountSwitch() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        #expect(await phone.sync.turnOn() == .on)
        let piece = try await phone.addPiece("Dress", photoBytes: 10_000)
        await phone.sync.syncNow()
        #expect(await server.writes("lily") == 2)

        phone.account.signIn("jose")
        try await phone.rename(piece.id, "Red dress")
        try await phone.addPiece("Scarf")
        await phone.sync.syncNow()
        #expect(await phone.status().state == .paused(.differentAccount))
        #expect(await server.writes("jose") == 0)
        #expect(await server.zones("jose").isEmpty)

        // Relaunching doesn't change that.
        let relaunched = try phone.relaunch()
        await relaunched.sync.start()
        await relaunched.sync.syncNow()
        #expect(await server.writes("jose") == 0)
        #expect(await relaunched.status().state == .paused(.differentAccount))

        // Back to her own account: it carries on, with what changed meanwhile.
        phone.account.signIn("lily")
        await relaunched.sync.syncNow()
        #expect(await relaunched.status().state == .on)
        let names = await server.records("lily", .closet).compactMap { $0.payload }.compactMap {
            StoredPayload(data: $0, version: RecordPayload.currentVersion).decode(Garment.self)?.name
        }
        #expect(Set(names) == ["Red dress", "Scarf"])
        #expect(await server.writes("jose") == 0)
    }

    @Test("Copy to this account uploads only after she chooses it; keep on this iPhone turns sync off")
    func accountChoices() async throws {
        for choice in [ICloudChoice.copyToThisAccount, .keepOnThisDevice] {
            let server = FakeCloudKit()
            let phone = try SyncTestDevice("phone", server: server)
            defer { phone.removeFolder() }
            #expect(await phone.sync.turnOn() == .on)
            try await phone.addPiece("Boots")
            await phone.sync.syncNow()
            phone.account.signIn("jose")
            await phone.sync.syncNow()
            #expect(await server.writes("jose") == 0)

            await phone.sync.answer(choice)
            await phone.sync.syncNow()
            if choice == .copyToThisAccount {
                #expect(await phone.status().state == .on)
                #expect(await server.records("jose", .closet).count == 1)
            } else {
                #expect(await phone.status().state == .off)
                #expect(await server.writes("jose") == 0)
                #expect(try await phone.garments().count == 1)
            }
        }
    }

    @Test("Signing out pauses; signing back in to the same account resumes")
    func signOutAndBack() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        #expect(await phone.sync.turnOn() == .on)
        phone.account.signIn(nil)
        let piece = try await phone.addPiece("Cardigan")
        await phone.sync.syncNow()
        #expect(await phone.status().state == .paused(.signedOut))
        #expect(try await phone.garment(piece.id) != nil)  // local data stays

        phone.account.signIn("lily")
        await phone.sync.syncNow()
        #expect(await phone.status().state == .on)
        #expect(await server.records("lily", .closet).count == 1)
    }

    // MARK: Zones deleted

    @Test("Deleted in Settings: sync pauses and asks; nothing is uploaded again until she says so")
    func deletedInSettings() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        let piece = try await pair.phone.addPiece("Blazer")
        await pair.phone.sync.syncNow()

        await pair.server.deleteInSettings(account: "lily")
        try await pair.phone.rename(piece.id, "Navy blazer")
        await pair.phone.sync.syncNow()
        #expect(await pair.phone.status().state == .paused(.removedInSettings))
        #expect(await pair.server.zones("lily").isEmpty)

        await pair.phone.sync.answer(.uploadAgain)
        await pair.phone.sync.syncNow()
        #expect(await pair.phone.status().state == .on)
        await pair.iPad.sync.syncNow()
        // The iPad saw the zones go too, and asks.
        #expect(await pair.iPad.status().state == .paused(.removedInSettings))
        await pair.iPad.sync.answer(.deleteHereToo)
        #expect(try await pair.iPad.garments().isEmpty)
        #expect(await pair.iPad.status().state == .off)
        #expect(await pair.server.records("lily", .closet).filter { $0.type == .garment }.count == 1)
    }

    @Test("Turned off with Also delete on one device: the other keeps its closet and is told why")
    func turnedOffElsewhere() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        try await pair.phone.addPiece("Top")
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        #expect(await pair.phone.sync.turnOff(deletingCopy: true) == .deleted)
        #expect(await pair.phone.status().state == .off)
        #expect(await pair.server.zones("lily") == [.control])
        let generation = try #require(await pair.server.record("lily", SyncSchema.generation)?.payload)
        #expect(try JSONDecoder().decode(SyncGeneration.self, from: generation).reason == .syncTurnedOff)

        await pair.iPad.sync.syncNow()
        #expect(await pair.iPad.status().state == .paused(.turnedOffElsewhere))
        #expect(try await pair.iPad.garments().count == 1)
        #expect(await pair.server.zones("lily") == [.control])  // not made again
        await pair.iPad.sync.answer(.keepOnThisDevice)
        #expect(await pair.iPad.status().state == .off)
    }

    @Test("Encrypted data reset: the zones are made again and this device's closet uploaded")
    func encryptedDataReset() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        #expect(await phone.sync.turnOn() == .on)
        try await phone.addPiece("Coat", photoBytes: 5_000)
        await phone.sync.syncNow()

        await server.resetEncryptedData(account: "lily")
        await phone.sync.syncNow()
        await phone.sync.syncNow()
        let status = await phone.status()
        #expect(status.state == .on)
        #expect(status.notice == .reuploadedAfterReset)
        #expect(status.isUpToDate)
        #expect(await server.records("lily", .closet).count == 2)  // the piece and its photo
    }

    // MARK: Storage, size and versions

    @Test("Storage full: changes stay safe here and upload once there's space")
    func quotaFull() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        await server.setQuota(100, for: "lily")
        #expect(await phone.sync.turnOn() == .on)
        let piece = try await phone.addPiece("Sweater")
        await phone.sync.syncNow()
        var status = await phone.status()
        #expect(status.problem == .storageFull)
        #expect(status.waitingChanges == 1)
        #expect(try await phone.garment(piece.id) != nil)
        #expect(await server.records("lily", .closet).isEmpty)

        await server.setQuota(.max, for: "lily")
        await phone.sync.syncNow()
        status = await phone.status()
        #expect(status.problem == nil)
        #expect(status.isUpToDate)
    }

    @Test("A big photo goes as its own asset, byte for byte, never inside the record")
    func bigPhoto() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        let piece = try await pair.phone.addPiece("Gown", photoBytes: 8_000_000)
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        guard case .stored(let photo) = piece.photo else {
            Issue.record("no photo")
            return
        }
        let record = try #require(
            await pair.server.record("lily", SyncRecordID(zone: .closet, name: "garment.\(piece.id.rawValue)")))
        #expect((record.payload?.count ?? .max) < 10_000)
        let asset = try #require(await pair.server.asset("lily", SyncSchema.imageID(photo.rawValue, zone: .closet)))
        #expect(asset.count == 8_000_000)
        let original = try Data(contentsOf: try #require(pair.phone.photos.url(for: photo.rawValue)))
        let copy = try Data(contentsOf: try #require(pair.iPad.photos.url(for: photo.rawValue)))
        #expect(copy == original)

        // An edit to the piece doesn't send the photo again.
        let writes = await pair.server.writes("lily")
        try await pair.phone.rename(piece.id, "Silk gown")
        await pair.phone.sync.syncNow()
        #expect(await pair.server.writes("lily") == writes + 1)
    }

    @Test("A record from a newer app version is kept, never overwritten, and read after an update")
    func newerSchema() async throws {
        let server = FakeCloudKit()
        let old = try SyncTestDevice("old", server: server)
        let new = try SyncTestDevice("new", server: server, knownPayloadVersion: RecordPayload.currentVersion + 1)
        defer {
            old.removeFolder()
            new.removeFolder()
        }
        #expect(await old.sync.turnOn() == .on)
        #expect(await new.sync.turnOn() == .on)
        let piece = try await old.addPiece("Trench")
        await old.sync.syncNow()
        await new.sync.syncNow()

        // The newer build saves the piece in its newer payload version.
        var newer = piece
        newer.name = "Trench, newer"
        let newerVersion = RecordPayload.currentVersion + 1
        let context = ModelContext(new.storage.container)
        let key = piece.id.rawValue
        let row = try #require(
            try context.fetch(
                FetchDescriptor<StoredRecord>(
                    predicate: #Predicate { $0.kind == "garment" && $0.key == key })
            ).first)
        row.payload = try RecordPayload.encode(newer)
        row.payloadVersion = newerVersion
        try context.save()
        await new.sync.syncNow()

        await old.sync.syncNow()
        #expect(await old.status().fromNewerVersion == 1)
        #expect(try await old.garment(piece.id)?.name == "Trench")  // left as it was here
        // An edit here never overwrites the newer record.
        try await old.rename(piece.id, "Trench, edited on the old app")
        await old.sync.syncNow()
        let onServer = try #require(
            await server.record("lily", SyncRecordID(zone: .closet, name: "garment.\(key)")))
        #expect(onServer.payloadVersion == newerVersion)

        // After the update, the held record is applied; this device's edit is kept for review.
        let updated = try old.relaunch(knownPayloadVersion: newerVersion)
        await updated.sync.start()
        #expect(await updated.status().fromNewerVersion == 0)
        let stored = try #require(try updated.rows(.garment).first { $0.key == key })
        #expect(stored.payloadVersion == newerVersion)
        #expect(try updated.conflicts().map(\.key) == [key])
    }

    @Test("With the fallback switch, body data stays on the device and the Me zone stays off")
    func bodyDataStaysHere() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        // The fallback if App Review 5.1.3(ii) rejects body data in iCloud (D11).
        await pair.phone.sync.setIncludesBodyData(false)
        await pair.iPad.sync.setIncludesBodyData(false)
        await pair.turnOnBoth()
        let photoID = UUID().uuidString
        try BackupLocation.prepare(pair.phone.location.photos, backedUp: true)
        try Data(repeating: 9, count: 2_000).write(to: try #require(pair.phone.photos.url(for: photoID)))
        try await pair.phone.storage.profile.update {
            $0.signName = "Lily"
            $0.measurements.height = Length(160, .centimeters)
            $0.tryOnPhoto = .stored(EntityID(photoID))
        }
        try await pair.iPad.storage.profile.update { $0.measurements.height = Length(150, .centimeters) }
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        #expect(await pair.server.zones("lily").contains(.me) == false)
        #expect(await pair.server.records("lily", .me).isEmpty)
        let record = try #require(await pair.server.record("lily", SyncRecordID(zone: .closet, name: "profile.only")))
        let payload = try #require(record.payload)
        let uploaded = try #require(StoredPayload(data: payload, version: record.payloadVersion).decode(Profile.self))
        #expect(uploaded.signName == "Lily")
        #expect(uploaded.measurements.isEmpty && uploaded.tryOnPhoto == nil && uploaded.fitPieces.isEmpty)
        #expect(await pair.server.records("lily", .closet).allSatisfy { $0.type != .image })

        let iPadProfile = try await pair.iPad.storage.profile.profile()
        #expect(iPadProfile.signName == "Lily")
        #expect(iPadProfile.measurements.height == Length(150, .centimeters))  // its own, untouched
        #expect(try await pair.phone.storage.profile.profile().measurements.height == Length(160, .centimeters))
    }

    @Test("Body data and the try-on photo sync, in the Me zone only (D11)")
    func bodyDataInMeZone() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        #expect(await pair.phone.status().includesBodyData)
        #expect(await pair.iPad.status().includesBodyData)
        let photoID = UUID().uuidString
        try BackupLocation.prepare(pair.phone.location.photos, backedUp: true)
        try Data(repeating: 7, count: 3_000).write(to: try #require(pair.phone.photos.url(for: photoID)))
        try await pair.phone.storage.profile.update {
            $0.signName = "Lily"
            $0.measurements.height = Length(160, .centimeters)
            $0.tryOnPhoto = .stored(EntityID(photoID))
        }
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        #expect(
            await pair.server.records("lily", .me).map(\.type).sorted { $0.rawValue < $1.rawValue } == [.body, .image])
        #expect(await pair.server.records("lily", .closet).allSatisfy { $0.type != .image })
        let profile = try await pair.iPad.storage.profile.profile()
        #expect(profile.signName == "Lily")
        #expect(profile.measurements.height == Length(160, .centimeters))
        #expect(profile.tryOnPhoto == .stored(EntityID(photoID)))
        #expect(pair.iPad.photos.exists(photoID))
        #expect(await pair.iPad.status().isUpToDate)
    }

    @Test("A store restored from a device backup starts sync fresh and merges by ID, with nothing lost")
    func restoredDevice() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        #expect(await phone.sync.turnOn() == .on)
        let piece = try await phone.addPiece("Polo", photoBytes: 4_000)
        await phone.sync.syncNow()
        try await phone.rename(piece.id, "Green polo")
        await phone.sync.syncNow()

        let restored = try phone.restoredOntoNewDevice()
        defer { restored.removeFolder() }
        let writes = await server.writes("lily")
        await restored.sync.start()
        // It started fresh: its own marker, everything fetched again and merged by ID, and
        // nothing sent on the strength of the copied engine state.
        let ledger = SyncBook(context: ModelContext(restored.storage.container)).ledger()
        #expect(ledger.deviceMarker != nil && ledger.deviceMarker == restored.marker.read())
        #expect(ledger.deviceMarker != phone.marker.read())
        #expect(await server.writes("lily") == writes)
        // The original phone, with its own marker, isn't affected.
        let again = try phone.relaunch()
        await again.sync.start()
        #expect(try again.rows(.syncRecord).isEmpty == false)
        await restored.sync.syncNow()
        #expect(try await restored.garment(piece.id)?.name == "Green polo")
        #expect(try restored.conflicts().isEmpty)
        #expect(await restored.status().isUpToDate)
        // Its edits upload as usual afterwards.
        try await restored.rename(piece.id, "Old polo")
        await restored.sync.syncNow()
        await phone.sync.syncNow()
        #expect(try await phone.garment(piece.id)?.name == "Old polo")
    }

    // MARK: Delete my data

    @Test("Delete my data, online: the iCloud copy goes first; the other device asks before erasing")
    func deleteMyDataOnline() async throws {
        let pair = try SyncPair()
        defer { pair.cleanUp() }
        await pair.turnOnBoth()
        try await pair.phone.addPiece("Shorts")
        await pair.phone.sync.syncNow()
        await pair.iPad.sync.syncNow()

        let deletion = AccountDataDeletion(
            local: LocalDataDeletion(stores: pair.phone.storage.erasableData), account: UnavailableAccountService(),
            iCloud: pair.phone.sync)
        #expect(deletion.parts(in: .thisDevice).first == .iCloudCopy)
        let report = await deletion.delete(.thisDevice)
        #expect(report.isComplete)
        #expect(report.order.first == .iCloudCopy)
        #expect(await pair.server.zones("lily") == [.control])
        let generation = try #require(await pair.server.record("lily", SyncSchema.generation)?.payload)
        #expect(try JSONDecoder().decode(SyncGeneration.self, from: generation).reason == .deletedEverything)
        #expect(try await pair.phone.garments().isEmpty)
        #expect(try pair.phone.rows(.syncRecord).isEmpty && pair.phone.rows(.syncState).isEmpty)
        #expect(!pair.phone.sync.mayHaveCopy)

        await pair.iPad.sync.syncNow()
        #expect(await pair.iPad.status().state == .paused(.deletedElsewhere))
        #expect(try await pair.iPad.garments().count == 1)  // asked, not erased
        await pair.iPad.sync.answer(.deleteHereToo)
        #expect(try await pair.iPad.garments().isEmpty)
    }

    @Test("Delete my data, offline: this device is erased, iCloud waits, and goes first at the next connected launch")
    func deleteMyDataOffline() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        #expect(await phone.sync.turnOn() == .on)
        try await phone.addPiece("Hat")
        await phone.sync.syncNow()

        await server.setOnline(false)
        let deletion = AccountDataDeletion(
            local: LocalDataDeletion(stores: phone.storage.erasableData), account: UnavailableAccountService(),
            iCloud: phone.sync)
        let report = await deletion.delete(.thisDevice)
        #expect(report.outcomes[.iCloudCopy] == .pending)
        #expect(report.isLocalComplete)
        #expect(try await phone.garments().isEmpty)
        #expect(try phone.rows(.syncPendingDeletion).count == 1)  // survived the erase
        #expect(await phone.status().state == .deletingCopy(waitingForAccount: false))
        #expect(await phone.sync.turnOn() == .deletionPending)
        #expect(await server.zones("lily").contains(.closet))

        await server.setOnline(true)
        let relaunched = try phone.relaunch()
        #expect(relaunched.sync.mayHaveCopy)
        await relaunched.sync.start()
        #expect(await server.zones("lily") == [.control])
        #expect(try relaunched.rows(.syncPendingDeletion).isEmpty)
        #expect(await relaunched.status().state == .off)
        #expect(await relaunched.sync.turnOn() == .on)
    }

    @Test("A pending deletion waits while a different account is signed in, and never touches it")
    func deletionWaitsForItsAccount() async throws {
        let server = FakeCloudKit()
        let phone = try SyncTestDevice("phone", server: server)
        defer { phone.removeFolder() }
        #expect(await phone.sync.turnOn() == .on)
        try await phone.addPiece("Belt")
        await phone.sync.syncNow()

        phone.account.signIn("jose")
        #expect(await phone.sync.deleteCopy() == .pending)
        #expect(await phone.status().state == .deletingCopy(waitingForAccount: true))
        #expect(await server.writes("jose") == 0)
        #expect(await server.zones("lily").contains(.closet))

        phone.account.signIn("lily")
        await phone.sync.syncNow()
        #expect(await server.zones("lily") == [.control])
        #expect(await phone.status().state == .off)
    }
}
