import Foundation
import Models
import SwiftData
import Synchronization

// Private iCloud sync (Phase 21b, decision 0004 §5): the app's side of `CKSyncEngine`.
//
// What's pending is worked out from the store, not remembered: a synced row whose value differs
// from the version both sides last agreed on (its ancestor), a row that went (a tombstone), a
// photo the records point to that iCloud doesn't have yet, a photo nothing points to any more.
// So the engine resetting its state (an account change), a crash between a save and its
// bookkeeping, or a restore all end the same way: the next look finds what's different and sends
// it, and the server's change tags turn anything stale into a merge.
//
// Nothing is sent unless sync is on and the iCloud account signed in at that moment is the one
// the closet belongs to. That's checked before every batch, whatever order the engine's events
// come in, so one account's data never uploads into another (PRD 15.1).

public actor ICloudSync: ICloudSyncService, SyncEngineDelegate {
    private let storage: NookStorage
    private let photos: PhotoFiles
    private let book: SyncBook
    private let makeEngine: SyncEngineMaker
    private var engine: (any SyncEngineDriving)?
    private let now: @Sendable () -> Date
    /// The newest payload version this build reads. A record from a newer one is held.
    private let knownPayloadVersion: Int
    /// Erases everything on this device, as Delete my data does, for "Delete it here too".
    private let eraseThisDevice: @Sendable () async -> Bool
    /// Whether there may be an iCloud copy, readable from any thread for Delete my data's list.
    private let copyMayExist: Mutex<Bool>
    /// Records too big for CloudKit, from the last batches.
    private var tooLarge: Set<String> = []
    /// A pending deletion waits because a different account is signed in.
    private var deletionWaitsForAccount = false
    private let deviceMarker: any SyncDeviceMarker

    /// - Parameters:
    ///   - location: where her photos are (`BackupLocation.photos`).
    ///   - engine: makes `CloudKitSyncEngine` in the app, the stand-in in tests.
    ///   - now: the clock, for dates on markers and conflicts.
    public init(
        storage: NookStorage, location: BackupLocation, engine: @escaping SyncEngineMaker,
        now: @escaping @Sendable () -> Date = { .now }, knownPayloadVersion: Int? = nil,
        deviceMarker: any SyncDeviceMarker = KeychainSyncDeviceMarker(),
        eraseThisDevice: @escaping @Sendable () async -> Bool
    ) {
        self.deviceMarker = deviceMarker
        self.storage = storage
        photos = PhotoFiles(directory: location.photos)
        let book = SyncBook(context: ModelContext(storage.container))
        self.book = book
        makeEngine = engine
        self.now = now
        self.knownPayloadVersion = knownPayloadVersion ?? RecordPayload.currentVersion
        self.eraseThisDevice = eraseThisDevice
        copyMayExist = Mutex(book.ledger().everOn || book.pendingDeletion() != nil)
    }

    // MARK: Starting

    /// At launch, once the store is open: a pending iCloud deletion runs first, before anything
    /// can sync (0004 §6); records held from a newer version are applied if this build reads them
    /// now; then sync carries on if it was on.
    public func start() async {
        startFreshIfRestored()
        await applyHeldRecords()
        if book.pendingDeletion() != nil {
            _ = await runPendingDeletion()
            return
        }
        switch book.ledger().mode {
        case .off: return
        case .deleting:
            // A deletion that has nothing left to delete.
            updateLedger { $0.mode = .off }
            return
        case .on, .paused:
            break
        }
        _ = engineNow()
        await checkAccount()
        if book.ledger().mode == .on {
            await engine?.add(zoneSaves())
            await fetchQueueAndSend()
        }
    }

    // MARK: ICloudSyncService

    public nonisolated var mayHaveCopy: Bool { copyMayExist.withLock { $0 } }

    public func status() -> ICloudSyncStatus {
        let ledger = book.ledger()
        var status = ICloudSyncStatus()
        if book.pendingDeletion() != nil {
            status.state = .deletingCopy(waitingForAccount: deletionWaitsForAccount)
        } else {
            switch ledger.mode {
            case .off: status.state = .off
            case .on: status.state = .on
            case .paused(let pause): status.state = .paused(pause)
            case .deleting: status.state = .deletingCopy(waitingForAccount: false)
            }
        }
        status.includesBodyData = ledger.includesBodyData
        status.lastConfirmed = ledger.lastConfirmedAt
        status.notice = ledger.notice
        status.conflictsToReview = book.conflicts().count
        status.fromNewerVersion = book.held().count
        if ledger.quotaFull {
            status.problem = .storageFull
        } else if !tooLarge.isEmpty {
            status.problem = .tooLarge(tooLarge.count)
        } else if ledger.offline {
            status.problem = .offline
        }
        let scan = scanLocal(ledger: ledger)
        status.estimatedBytes = scan.bytes
        if ledger.mode != .off {
            status.waitingChanges = scan.changes.count
            status.waitingPhotos = scan.photos.count
        }
        return status
    }

    public func turnOn() async -> ICloudTurnOnResult {
        guard book.pendingDeletion() == nil else { return .deletionPending }
        let engine = engineNow()
        let user: String?
        do {
            user = try await engine.currentUser()
        } catch {
            return .offline
        }
        guard let user else { return .noAccount }
        let account = SyncAccount.hash(user)
        if book.ledger().closetAccount != account {
            // What's kept about another account's copy means nothing in this one.
            try? book.forgetServer()
        }
        updateLedger {
            $0.mode = .on
            $0.closetAccount = account
            $0.everOn = true
            $0.notice = nil
            $0.deletedZones = [:]
        }
        markThisDevice()
        await engine.add(zoneSaves())
        await fetchQueueAndSend()
        return .on
    }

    public func turnOff(deletingCopy: Bool) async -> DeletionOutcome {
        guard deletingCopy else {
            // Keep my iCloud copy: this device stops; other devices carry on.
            updateLedger { $0.mode = .off }
            return .deleted
        }
        guard let account = book.ledger().closetAccount else { return .deleted }
        stagePendingDeletion(reason: .syncTurnedOff, account: account)
        return await runPendingDeletion()
    }

    public func answer(_ choice: ICloudChoice) async {
        let current = try? await engine?.currentUser()
        await apply(.choice(choice, current: current.map(SyncAccount.hash)))
    }

    public func syncNow() async {
        if book.pendingDeletion() != nil {
            _ = await runPendingDeletion()
            return
        }
        guard book.ledger().mode != .off else { return }
        _ = engineNow()
        await checkAccount()
        guard book.ledger().mode == .on else { return }
        await fetchQueueAndSend()
    }

    // MARK: Delete my data (0004 §6)

    /// Deletes the `Closet` and `Me` zones, after writing a `SyncGeneration` that says why. The
    /// request is saved first, content-free, where Delete my data's erase doesn't reach it, so if
    /// iCloud can't be reached it runs at the next connected launch, before anything syncs.
    public func deleteCopy() async -> DeletionOutcome {
        guard mayHaveCopy else { return .deleted }
        if book.pendingDeletion() == nil {
            guard let account = book.ledger().closetAccount else { return .deleted }
            stagePendingDeletion(reason: .deletedEverything, account: account)
        }
        return await runPendingDeletion()
    }

    private func stagePendingDeletion(reason: SyncGeneration.Reason, account: String) {
        let pending = SyncPendingDeletion(zones: [.closet, .me], reason: reason, account: account, requestedAt: now())
        try? book.stage(pendingDeletion: pending)
        updateLedger { $0.mode = .deleting }
    }

    private func runPendingDeletion() async -> DeletionOutcome {
        guard let pending = book.pendingDeletion() else { return .deleted }
        let engine = engineNow()
        let user: String?
        do {
            user = try await engine.currentUser()
        } catch {
            return .pending
        }
        // Only the account that holds the copy can delete it. A different one waits, and the
        // screen says which to sign in to (iOS names it, never our records).
        deletionWaitsForAccount = user != nil && user.map(SyncAccount.hash) != pending.account
        guard let user, SyncAccount.hash(user) == pending.account else { return .pending }

        updateLedger {
            $0.mode = .deleting
            $0.confirmedDeletes = []
            let next = max($0.generation, $0.remoteGeneration?.generation ?? 0) + 1
            $0.outgoingGeneration = SyncGeneration(generation: next, reason: pending.reason, date: now())
        }
        // First the generation, so a device that sees the zones go can read why.
        await engine.add([.save(.control)])
        await engine.add([.save(SyncSchema.generation)])
        do {
            try await engine.sendChanges()
        } catch {
            return .pending
        }
        guard book.ledger().outgoingGeneration == nil else { return .pending }

        await engine.add(pending.zones.map { .delete($0) })
        do {
            try await engine.sendChanges()
        } catch {
            return .pending
        }
        guard Set(pending.zones).isSubset(of: book.ledger().confirmedDeletes) else { return .pending }

        // Done: iCloud confirmed it. Nothing about the old copy is kept.
        try? book.forgetServer()
        try? book.stage(pendingDeletion: nil)
        updateLedger {
            $0.mode = .off
            $0.everOn = false
            $0.engineState = nil
            $0.confirmedDeletes = []
            $0.lastConfirmedAt = nil
        }
        await engine.stop()
        self.engine = nil
        return .deleted
    }

    // MARK: SyncEngineDelegate

    public func mayUpload() async -> Bool {
        let ledger = book.ledger()
        let account: String?
        switch ledger.mode {
        case .on: account = ledger.closetAccount
        case .deleting: account = book.pendingDeletion()?.account
        case .off, .paused: return false
        }
        guard let account, let engine else { return false }
        let user = try? await engine.currentUser()
        guard let user, SyncAccount.hash(user) == account else {
            // Signed out or a different account since the last event: pause before anything goes.
            if book.ledger().mode == .on { await apply(.account(current: user.map(SyncAccount.hash))) }
            return false
        }
        // The mode may have changed while the account was read.
        let mode = book.ledger().mode
        return mode == .on || mode == .deleting
    }

    public func record(for id: SyncRecordID) -> SyncRecord? {
        let ledger = book.ledger()
        let metas = book.metas()
        let meta = metas[Self.metaKey(id)]
        if id == SyncSchema.generation {
            guard let generation = ledger.outgoingGeneration, let payload = try? JSONEncoder().encode(generation)
            else { return nil }
            return SyncRecord(
                id: id, type: .syncGeneration, payload: payload, payloadVersion: 1, systemFields: meta?.systemFields)
        }
        guard ledger.mode == .on else { return nil }
        if let imageID = SyncSchema.imageName(of: id) {
            // Images are written once: one iCloud already has is never sent again.
            guard meta == nil, let url = photos.url(for: imageID), FileManager.default.fileExists(atPath: url.path),
                id.zone == .closet || ledger.includesBodyData
            else { return nil }
            return SyncRecord(id: id, type: .image, asset: url)
        }
        if id == SyncSchema.body {
            guard ledger.includesBodyData, let row = row(.profile, RecordKind.singleKey),
                let profile = StoredPayload(data: row.payload, version: row.payloadVersion).decode(Profile.self),
                let payload = try? RecordPayload.encode(SyncBodyData.split(profile).body)
            else { return nil }
            return SyncRecord(
                id: id, type: .body, payload: payload, payloadVersion: RecordPayload.currentVersion,
                systemFields: meta?.systemFields)
        }
        guard let (kind, key) = SyncSchema.parse(id.name), let type = SyncSchema.types[kind] else { return nil }
        // Never overwrite a record a newer version wrote.
        guard book.held()[Self.metaKey(id)] == nil else { return nil }
        guard let row = row(kind, key) else {
            // Gone from this device since both sides last agreed: a tombstone, content-free.
            guard let meta, !meta.isTombstone, meta.ancestor != nil else { return nil }
            return SyncRecord(
                id: id, type: type, payloadVersion: knownPayloadVersion, isTombstone: true,
                systemFields: meta.systemFields)
        }
        let payload = Self.localPayload(kind, row)
        // Already what iCloud has (a change queued before a fetch brought the same version).
        if let meta, meta.systemFields != nil, !meta.isTombstone, let ancestor = meta.ancestor,
            SyncCodec.byKind[kind]?.same(payload, ancestor) == true
        {
            return nil
        }
        guard payload.data.count <= SyncSchema.maximumPayloadBytes else {
            tooLarge.insert(id.name)
            return nil
        }
        tooLarge.remove(id.name)
        return SyncRecord(
            id: id, type: type, payload: payload.data, payloadVersion: payload.version,
            systemFields: meta?.systemFields)
    }

    public func handle(_ event: SyncEvent) async {
        switch event {
        case .stateUpdate(let state):
            updateLedger { $0.engineState = state }
        case .accountChange(let change):
            switch change {
            case .signOut: await apply(.account(current: nil))
            case .signIn(let user), .switchAccounts(let user): await apply(.account(current: SyncAccount.hash(user)))
            }
            await requeueAfterAccountChange()
        case .zonesDeleted(let zones):
            await zonesDeleted(zones)
        case .fetchedRecords(let modified, let deleted):
            await applyFetched(modified, deleted: deleted)
        case .sentZones(let saved, let deleted, let failed):
            sentZones(saved: saved, deleted: deleted, failed: failed)
        case .sentRecords(let saved, let failed, let deleted, let failedDeletes):
            await sentRecords(saved: saved, failed: failed, deleted: deleted, failedDeletes: failedDeletes)
        case .didFetchChanges:
            await decideDeletedZones()
        }
    }

    /// The engine clears what's pending when the account changes (Apple: "it resets its internal
    /// state"), including at its first start. Whatever still applies to this account goes back.
    private func requeueAfterAccountChange() async {
        let ledger = book.ledger()
        switch ledger.mode {
        case .on:
            await engine?.add(zoneSaves())
            await queueLocalChanges()
        case .deleting:
            guard let pending = book.pendingDeletion() else { return }
            if ledger.outgoingGeneration != nil {
                await engine?.add([.save(.control)])
                await engine?.add([.save(SyncSchema.generation)])
            } else {
                await engine?.add(pending.zones.map { .delete($0) })
            }
        case .off, .paused:
            break
        }
    }

    // MARK: Sending

    /// Fetch first, so what's merged here goes up merged; then queue what differs, then send.
    private func fetchQueueAndSend() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
            await queueLocalChanges()
            try await engine.sendChanges()
            updateLedger { $0.offline = false }
        } catch {
            updateLedger { $0.offline = true }
            return
        }
        guard book.ledger().zoneMissing else { return }
        // A zone wasn't there. Read why before making it again: another device may have deleted
        // it on purpose, and making it again would undo that.
        updateLedger { $0.zoneMissing = false }
        do {
            try await engine.fetchChanges()
            guard book.ledger().mode == .on else { return }
            await engine.add(zoneSaves())
            await queueLocalChanges()
            try await engine.sendChanges()
        } catch {
            updateLedger { $0.offline = true }
        }
    }

    /// Hands the engine every record that differs from what iCloud has.
    private func queueLocalChanges() async {
        let ledger = book.ledger()
        guard ledger.mode == .on, let engine else { return }
        let scan = scanLocal(ledger: ledger)
        if !scan.nowReferenced.isEmpty {
            var metas = book.metas()
            for key in scan.nowReferenced { metas[key]?.wasReferenced = true }
            try? book.stage(metas: metas.filter { scan.nowReferenced.contains($0.key) })
            try? book.save()
        }
        let changes =
            scan.changes.map(SyncPendingChange.save) + scan.photos.map(SyncPendingChange.save)
            + scan.unusedPhotos.map(SyncPendingChange.delete)
        if !changes.isEmpty { await engine.add(changes) }
    }

    private func zoneSaves() -> [SyncZoneChange] {
        var zones: [SyncZone] = [.closet, .control]
        if book.ledger().includesBodyData { zones.append(.me) }
        return zones.map { .save($0) }
    }

    private func sentZones(saved: [SyncZone], deleted: [SyncZone], failed: [SyncZone: SyncFailure]) {
        updateLedger { ledger in
            ledger.confirmedDeletes.formUnion(deleted)
            for (zone, failure) in failed {
                switch failure {
                // Deleting a zone that isn't there leaves it as gone as deleting it.
                case .zoneNotFound, .unknownItem: ledger.confirmedDeletes.insert(zone)
                case .quotaExceeded: ledger.quotaFull = true
                default: ledger.offline = true
                }
            }
        }
    }

    private func sentRecords(
        saved: [SyncRecord], failed: [SyncFailedSave], deleted: [SyncRecordID],
        failedDeletes: [SyncRecordID: SyncFailure]
    ) async {
        var metas = book.metas()
        var changedMetas: [String: SyncRecordMeta] = [:]
        var removed: [String] = []
        var ledger = book.ledger()
        for record in saved {
            let key = Self.metaKey(record.id)
            if record.id == SyncSchema.generation {
                if let sent = ledger.outgoingGeneration {
                    ledger.generation = max(ledger.generation, sent.generation)
                }
                ledger.outgoingGeneration = nil
            }
            var meta = metas[key] ?? SyncRecordMeta()
            meta.systemFields = record.systemFields
            meta.changeTag = record.changeTag
            meta.isTombstone = record.isTombstone
            if record.type == .image {
                meta.wasReferenced = true
            } else {
                meta.ancestor = record.payload.map { StoredPayload(data: $0, version: record.payloadVersion) }
            }
            metas[key] = meta
            changedMetas[key] = meta
        }
        if !saved.isEmpty || !deleted.isEmpty {
            ledger.lastConfirmedAt = now()
            ledger.quotaFull = false
            ledger.offline = false
        }
        for id in deleted { removed.append(Self.metaKey(id)) }
        for (id, failure) in failedDeletes where failure == .unknownItem { removed.append(Self.metaKey(id)) }

        var mergeAgain: [SyncRecord] = []
        var deletedZones: [SyncZone: SyncZoneDeletionReason] = [:]
        for failedSave in failed {
            let key = Self.metaKey(failedSave.record.id)
            switch failedSave.failure {
            case .serverRecordChanged(let server):
                if let server { mergeAgain.append(server) }
            case .quotaExceeded:
                ledger.quotaFull = true
            case .zoneNotFound:
                ledger.zoneMissing = true
            case .userDeletedZone:
                deletedZones[failedSave.record.id.zone] = .purged
            case .encryptedDataReset:
                deletedZones[failedSave.record.id.zone] = .encryptedDataReset
            case .unknownItem:
                // Gone from the server: the next send makes it as new.
                if var meta = metas[key] {
                    meta.systemFields = nil
                    meta.changeTag = nil
                    changedMetas[key] = meta
                }
            case .tooLarge:
                tooLarge.insert(failedSave.record.id.name)
            case .transient, .other:
                ledger.offline = true
            }
        }
        try? book.stage(ledger: ledger)
        try? book.stage(metas: changedMetas, removing: removed)
        try? book.save()
        copyMayExist.withLock { $0 = ledger.everOn || book.pendingDeletion() != nil }

        if !mergeAgain.isEmpty {
            // The server had a newer version: merge it in, then send what differs from it.
            await applyFetched(mergeAgain, deleted: [])
        }
        if !deletedZones.isEmpty { await zonesDeleted(deletedZones) }
        if !mergeAgain.isEmpty || failed.contains(where: { $0.failure == .unknownItem }) {
            await queueLocalChanges()
        }
    }

    // MARK: Receiving

    private func applyFetched(_ modified: [SyncRecord], deleted: [SyncRecordID]) async {
        var ledger = book.ledger()
        let metas = book.metas()
        var held = book.held()
        var changedMetas: [String: SyncRecordMeta] = [:]
        var removedMetas: [String] = []
        var heldChanges: [String: SyncHeldRecord] = [:]
        var heldRemoved: [String] = []
        var byKind: [RecordKind: [SyncIncoming]] = [:]
        var body: SyncRecord?

        for record in modified {
            let key = Self.metaKey(record.id)
            let meta = metas[key]
            // The same change delivered twice changes nothing.
            if let tag = record.changeTag, meta?.changeTag == tag { continue }
            switch record.type {
            case .syncGeneration:
                if let payload = record.payload,
                    let generation = try? JSONDecoder().decode(SyncGeneration.self, from: payload),
                    generation.generation > (ledger.remoteGeneration?.generation ?? 0)
                {
                    ledger.remoteGeneration = generation
                }
                changedMetas[key] = SyncRecordMeta(systemFields: record.systemFields, changeTag: record.changeTag)
            case .image:
                guard record.id.zone == .closet || ledger.includesBodyData,
                    let imageID = SyncSchema.imageName(of: record.id)
                else { continue }
                if !photos.exists(imageID), let asset = record.asset { storeImage(asset, as: imageID) }
                var updated = meta ?? SyncRecordMeta()
                updated.systemFields = record.systemFields
                updated.changeTag = record.changeTag
                changedMetas[key] = updated
            case .body:
                guard ledger.includesBodyData else { continue }
                body = record
            default:
                guard let (kind, rowKey) = SyncSchema.parse(record.id.name) else { continue }
                if !record.isTombstone && record.payloadVersion > knownPayloadVersion {
                    // From a newer version of the app: kept as it came, never overwritten.
                    heldChanges[key] = SyncHeldRecord(
                        payload: record.payload, payloadVersion: record.payloadVersion, isTombstone: false)
                    var updated = meta ?? SyncRecordMeta()
                    updated.systemFields = record.systemFields
                    updated.changeTag = record.changeTag
                    changedMetas[key] = updated
                    continue
                }
                if held[key] != nil {
                    heldRemoved.append(key)
                    held[key] = nil
                }
                byKind[kind, default: []].append(SyncIncoming(key: rowKey, metaKey: key, record: record, meta: meta))
            }
        }
        for id in deleted {
            // Only images are ever deleted outright; content records become tombstones.
            removedMetas.append(Self.metaKey(id))
        }

        // Each kind is written by whoever owns it, in one save.
        var conflicts: [String: StoredSyncConflict] = [:]
        var released: [(photos: [PhotoReference], forGood: Bool)] = []
        let date = now()
        for (kind, incoming) in byKind {
            let results: [SyncApplied]
            do {
                results = try await write(kind) { context in
                    try SyncApply.apply(incoming, kind: kind, in: context, now: date)
                }
            } catch {
                continue  // Nothing changed for this kind; the state stays behind, so it comes again.
            }
            for result in results {
                changedMetas[result.metaKey] = result.meta
                if let conflict = result.conflict { conflicts[result.metaKey] = conflict }
                if !result.released.isEmpty { released.append((result.released, kind == .garment)) }
            }
        }
        if let body, let meta = applyBody(body, existing: metas[Self.metaKey(body.id)]) {
            changedMetas[Self.metaKey(body.id)] = meta
        }
        try? book.stage(ledger: ledger)
        try? book.stage(metas: changedMetas, removing: removedMetas)
        try? book.stage(held: heldChanges, removing: heldRemoved)
        if !conflicts.isEmpty { try? book.stage(conflicts: conflicts) }
        try? book.save()
        for release in released {
            await storage.imageFiles?.release(release.photos, deletedForGood: release.forGood)
        }
    }

    /// The body record (`Me` zone, only when decision 2 allows): her measurements and fit go
    /// back into the profile; the rest of the profile stays as it is.
    private func applyBody(_ record: SyncRecord, existing: SyncRecordMeta?) -> SyncRecordMeta? {
        guard let payload = record.payload,
            let incoming = StoredPayload(data: payload, version: record.payloadVersion).decode(SyncBodyData.self),
            let row = row(.profile, RecordKind.singleKey),
            let profile = StoredPayload(data: row.payload, version: row.payloadVersion).decode(Profile.self)
        else { return nil }
        let local = SyncBodyData.split(profile).body
        let ancestor = existing?.ancestor?.decode(SyncBodyData.self)
        let (merged, _) = SyncMerge.whole(ancestor: ancestor, local: local, server: incoming)
        if merged != local, let data = try? RecordPayload.encode(merged.applied(to: profile)) {
            try? saveChanges(in: book.context) {
                row.payload = data
                row.payloadVersion = RecordPayload.currentVersion
                row.savedAt = now()
            }
        }
        return SyncRecordMeta(
            systemFields: record.systemFields, changeTag: record.changeTag,
            ancestor: StoredPayload(data: payload, version: record.payloadVersion))
    }

    /// Writes a kind through the store actor that owns it when that actor keeps values in
    /// memory, so her edits and these never interleave; otherwise in sync's own context.
    private func write<T: Sendable>(_ kind: RecordKind, _ body: @Sendable (ModelContext) throws -> T) async throws -> T
    {
        let owner: (any SyncWritableStore)? =
            switch kind {
            case .garment: storage.closet
            case .look: storage.looks
            case .suitcase: storage.suitcases
            case .picture: storage.pictures
            default: nil
            }
        if let owner { return try await owner.applySynced(body) }
        return try body(book.context)
    }

    /// Records held from a newer version that this build can read now (after an update).
    private func applyHeldRecords() async {
        let readable = book.held().filter { $0.value.payloadVersion <= knownPayloadVersion }
        guard !readable.isEmpty else { return }
        let metas = book.metas()
        var records: [SyncRecord] = []
        for (key, held) in readable {
            guard let id = Self.recordID(metaKey: key), let (kind, _) = SyncSchema.parse(id.name),
                let type = SyncSchema.types[kind]
            else { continue }
            records.append(
                SyncRecord(
                    id: id, type: type, payload: held.payload, payloadVersion: held.payloadVersion,
                    isTombstone: held.isTombstone, systemFields: metas[key]?.systemFields))
        }
        await applyFetched(records, deleted: [])
    }

    private func storeImage(_ asset: URL, as imageID: String) {
        guard let destination = photos.url(for: imageID) else { return }
        do {
            try BackupLocation.prepare(photos.directory, backedUp: true)
            let data = try Data(contentsOf: asset)
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
        } catch {
            // Not stored: the piece shows its photo as missing until it comes again.
        }
    }

    // MARK: Account and zone events

    private func zonesDeleted(_ zones: [SyncZone: SyncZoneDeletionReason]) async {
        guard book.ledger().mode == .on || book.ledger().mode == .paused(.signedOut) else { return }
        if zones.values.contains(.encryptedDataReset) {
            updateLedger { $0.notice = .reuploadedAfterReset }
            await apply(.zoneDeleted(.encryptedDataReset, remote: nil))
            return
        }
        // Why it was deleted is read at the end of the fetch, once the `Control` zone came in.
        updateLedger { $0.deletedZones.merge(zones) { _, new in new } }
    }

    private func decideDeletedZones() async {
        let ledger = book.ledger()
        guard !ledger.deletedZones.isEmpty else { return }
        updateLedger { $0.deletedZones = [:] }
        if ledger.deletedZones.values.contains(.purged) {
            await apply(.zoneDeleted(.purged, remote: nil))
            return
        }
        let remote = ledger.remoteGeneration.flatMap { $0.generation > ledger.generation ? $0.reason : nil }
        updateLedger { $0.generation = max($0.generation, ledger.remoteGeneration?.generation ?? 0) }
        await apply(.zoneDeleted(.deleted, remote: remote))
    }

    /// Reads the account signed in now and pauses or resumes to match.
    private func checkAccount() async {
        guard let engine, let user = try? await engine.currentUser() else {
            // Offline: nothing changes, and `mayUpload` checks again before anything goes.
            return
        }
        await apply(.account(current: SyncAccount.hash(user)))
    }

    private func apply(_ input: SyncPolicy.Input) async {
        let ledger = book.ledger()
        let (next, actions) = SyncPolicy.next(
            SyncPolicy.State(mode: ledger.mode, closetAccount: ledger.closetAccount), input)
        updateLedger {
            $0.mode = next.mode
            $0.closetAccount = next.closetAccount
        }
        for action in actions {
            switch action {
            case .stop:
                break  // `mayUpload` refuses every batch from now on.
            case .resume:
                await engine?.add(zoneSaves())
                await queueLocalChanges()
            case .reuploadEverything:
                try? book.forgetServer()
                try? book.save()
                updateLedger {
                    $0.deletedZones = [:]
                    $0.quotaFull = false
                }
                await engine?.add(zoneSaves())
                await queueLocalChanges()
            case .forgetServer:
                try? book.forgetServer()
                try? book.save()
            case .eraseThisDevice:
                _ = await eraseThisDevice()
                try? book.eraseAll()
                try? book.save()
                copyMayExist.withLock { $0 = book.pendingDeletion() != nil }
            }
        }
    }

    // MARK: Restored devices

    /// A store restored from a device backup brings a ledger this device's Keychain doesn't know:
    /// drop the engine state and what the server had, so everything is fetched and merged by ID.
    private func startFreshIfRestored() {
        let ledger = book.ledger()
        guard ledger.everOn || ledger.mode != .off else { return }
        if let marker = ledger.deviceMarker, deviceMarker.read() == marker { return }
        try? book.forgetServer()
        try? book.save()
        updateLedger { $0.engineState = nil }
        engine = nil
        markThisDevice()
    }

    private func markThisDevice() {
        if let marker = book.ledger().deviceMarker, deviceMarker.read() == marker { return }
        let marker = UUID().uuidString
        deviceMarker.write(marker)
        updateLedger { $0.deviceMarker = marker }
    }

    /// Decision 2: whether body data syncs in the `Me` zone. Off until App Review 5.1.3(ii) is
    /// answered; there's no switch on screen yet, so only tests turn it on.
    func setIncludesBodyData(_ includes: Bool) async {
        updateLedger { $0.includesBodyData = includes }
        if includes { await engine?.add(zoneSaves()) }
    }

    // MARK: Helpers

    private func engineNow() -> any SyncEngineDriving {
        if let engine { return engine }
        let made = makeEngine(book.ledger().engineState, self)
        engine = made
        return made
    }

    /// Changes the ledger and saves it, with nothing awaited in between.
    private func updateLedger(_ change: (inout SyncLedger) -> Void) {
        var ledger = book.ledger()
        change(&ledger)
        try? book.stage(ledger: ledger)
        try? book.save()
        copyMayExist.withLock { $0 = ledger.everOn || book.pendingDeletion() != nil }
    }

    private func row(_ kind: RecordKind, _ key: String) -> StoredRecord? {
        let kind = kind.rawValue
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.kind == kind && $0.key == key })
        descriptor.fetchLimit = 1
        return try? book.context.fetch(descriptor).first
    }

    /// The payload a row sends: as stored, but the profile without its body data.
    static func localPayload(_ kind: RecordKind, _ row: StoredRecord) -> StoredPayload {
        localPayload(kind, StoredPayload(data: row.payload, version: row.payloadVersion))
    }

    static func localPayload(_ kind: RecordKind, _ payload: StoredPayload) -> StoredPayload {
        guard kind == .profile, let profile = payload.decode(Profile.self),
            let data = try? RecordPayload.encode(SyncBodyData.split(profile).profile)
        else { return payload }
        return StoredPayload(data: data, version: RecordPayload.currentVersion)
    }

    /// Sync's bookkeeping key for a record: its zone and name.
    static func metaKey(_ id: SyncRecordID) -> String { "\(id.zone.rawValue)/\(id.name)" }

    static func recordID(metaKey: String) -> SyncRecordID? {
        guard let slash = metaKey.firstIndex(of: "/"), let zone = SyncZone(rawValue: String(metaKey[..<slash]))
        else { return nil }
        return SyncRecordID(zone: zone, name: String(metaKey[metaKey.index(after: slash)...]))
    }

    // MARK: Looking for local changes

    struct LocalScan {
        /// Records to save: changed, new, or gone (tombstones).
        var changes: [SyncRecordID] = []
        /// Photos iCloud doesn't have yet.
        var photos: [SyncRecordID] = []
        /// Photos this device used and nothing points to any more.
        var unusedPhotos: [SyncRecordID] = []
        /// Bookkeeping keys of photos the records point to now.
        var nowReferenced: Set<String> = []
        /// About what the copy takes in iCloud.
        var bytes: Int64 = 0
    }

    private func scanLocal(ledger: SyncLedger) -> LocalScan {
        var scan = LocalScan()
        guard let rows = try? StoreRow.all(in: book.context) else { return scan }
        let metas = book.metas()
        let held = book.held()
        var present: Set<String> = []
        var closetRows: [StoreRow] = []
        var profile: Profile?

        for row in rows {
            guard let kind = RecordKind(rawValue: row.kind), SyncSchema.types[kind] != nil,
                let id = SyncSchema.id(kind: kind, key: row.key), let codec = SyncCodec.byKind[kind]
            else { continue }
            let key = Self.metaKey(id)
            present.insert(key)
            if kind == .profile {
                profile = StoredPayload(data: row.payload, version: row.payloadVersion).decode(Profile.self)
            } else {
                closetRows.append(row)
            }
            let payload = Self.localPayload(kind, StoredPayload(data: row.payload, version: row.payloadVersion))
            scan.bytes += Int64(payload.data.count)
            if held[key] != nil { continue }
            if let meta = metas[key], meta.systemFields != nil, let ancestor = meta.ancestor, !meta.isTombstone,
                codec.same(payload, ancestor)
            {
                continue
            }
            scan.changes.append(id)
        }
        if ledger.includesBodyData, let profile, let body = try? RecordPayload.encode(SyncBodyData.split(profile).body)
        {
            let meta = metas[Self.metaKey(SyncSchema.body)]
            let same =
                meta?.systemFields != nil
                && meta?.ancestor.flatMap { $0.decode(SyncBodyData.self) } == SyncBodyData.split(profile).body
            if !same { scan.changes.append(SyncSchema.body) }
            scan.bytes += Int64(body.count)
        }
        // Rows gone since both sides last agreed: tombstones.
        for (key, meta) in metas where !present.contains(key) && !meta.isTombstone && meta.ancestor != nil {
            guard let id = Self.recordID(metaKey: key), id.zone == .closet, SyncSchema.parse(id.name) != nil else {
                continue
            }
            scan.changes.append(id)
        }

        // Photos: the ones the synced records point to, in the zone of what points to them.
        var referenced: [SyncRecordID: String] = [:]
        for imageID in BackupContents(closetRows).photoIDs {
            referenced[SyncSchema.imageID(imageID, zone: .closet)] = imageID
        }
        if ledger.includesBodyData, case .stored(let photo) = profile?.tryOnPhoto {
            referenced[SyncSchema.imageID(photo.rawValue, zone: .me)] = photo.rawValue
        }
        for (id, imageID) in referenced {
            guard let url = photos.url(for: imageID),
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { continue }
            scan.bytes += Int64(size)
            let key = Self.metaKey(id)
            if let meta = metas[key] {
                if !meta.wasReferenced { scan.nowReferenced.insert(key) }
            } else {
                scan.photos.append(id)
            }
        }
        for (key, meta) in metas where meta.wasReferenced {
            guard let id = Self.recordID(metaKey: key), SyncSchema.imageName(of: id) != nil, referenced[id] == nil
            else { continue }
            scan.unusedPhotos.append(id)
        }
        scan.changes.sort()
        scan.photos.sort()
        scan.unusedPhotos.sort()
        return scan
    }
}

/// One record from iCloud for a kind's writer.
struct SyncIncoming: Sendable {
    var key: String
    var metaKey: String
    var record: SyncRecord
    var meta: SyncRecordMeta?
}

/// What applying one record did.
struct SyncApplied: Sendable {
    var metaKey: String
    var meta: SyncRecordMeta
    var conflict: StoredSyncConflict?
    /// Photos the record pointed to before it went, to remove if nothing else points to them.
    var released: [PhotoReference] = []
}

/// Applying records from iCloud to one kind's rows, in the writer's context, in one save.
enum SyncApply {
    static func apply(_ incoming: [SyncIncoming], kind: RecordKind, in context: ModelContext, now: Date) throws
        -> [SyncApplied]
    {
        guard let codec = SyncCodec.byKind[kind] else { return [] }
        var results: [SyncApplied] = []
        try saveChanges(in: context) {
            for item in incoming {
                results.append(try apply(item, kind: kind, codec: codec, in: context, now: now))
            }
        }
        return results
    }

    private static func apply(
        _ item: SyncIncoming, kind: RecordKind, codec: SyncCodec, in context: ModelContext, now: Date
    ) throws -> SyncApplied {
        let record = item.record
        let row = try fetch(kind, item.key, in: context)
        var meta = SyncRecordMeta(
            systemFields: record.systemFields, changeTag: record.changeTag, ancestor: nil, isTombstone: false)
        var applied = SyncApplied(metaKey: item.metaKey, meta: meta)
        let ancestor = item.meta?.ancestor

        if record.isTombstone {
            meta.isTombstone = true
            applied.meta = meta
            guard let row else { return applied }
            let local = ICloudSync.localPayload(kind, row)
            if let ancestor, !codec.same(local, ancestor) {
                // Deleted for good there, edited here: the deletion wins, the edit is reported.
                applied.conflict = StoredSyncConflict(
                    kind: kind.rawValue, key: item.key, fields: ["record"], reason: .deletedElsewhere, losing: nil,
                    foundAt: now)
            }
            applied.released = SyncImages.references(
                kind, StoredPayload(data: row.payload, version: row.payloadVersion))
            context.delete(row)
            if kind == .garment {
                try RecordTable<StoredDeletion>(kind: .deletion, now: { now }).stage(
                    [item.key: StoredDeletion(deletedAt: now)], in: context)
            }
            return applied
        }

        guard let data = record.payload else { return applied }
        let server = StoredPayload(data: data, version: record.payloadVersion)
        meta.ancestor = server
        applied.meta = meta

        // A piece deleted for good here stays deleted; the next send carries the tombstone.
        if kind == .garment, try fetch(.deletion, item.key, in: context) != nil { return applied }

        guard let row else {
            if let previous = item.meta, previous.ancestor != nil, !previous.isTombstone {
                // Deleted here, edited there: removal wins, and their version is kept for review.
                if let ancestor, !codec.same(server, ancestor) {
                    applied.conflict = StoredSyncConflict(
                        kind: kind.rawValue, key: item.key, fields: ["record"], reason: .editedElsewhere,
                        losing: server, foundAt: now)
                }
                return applied
            }
            context.insert(
                StoredRecord(
                    kind: kind.rawValue, key: item.key, payloadVersion: server.version, payload: server.data,
                    savedAt: now))
            return applied
        }

        let local = ICloudSync.localPayload(kind, row)
        if codec.same(local, server) { return applied }
        if let ancestor, codec.same(local, ancestor) {
            write(server, to: row, kind: kind, now: now)
            return applied
        }
        // Both changed since they last agreed (or they never agreed): merge, keep what lost.
        if let outcome = codec.merge(ancestor, local, server) {
            let merged = StoredPayload(data: outcome.payload, version: RecordPayload.currentVersion)
            write(merged, to: row, kind: kind, now: now)
            if !outcome.fields.isEmpty {
                applied.conflict = StoredSyncConflict(
                    kind: kind.rawValue, key: item.key, fields: outcome.fields, reason: .bothChanged, losing: local,
                    foundAt: now)
            }
        } else {
            // A version this build can't read: the server's stays, this one is kept for review.
            write(server, to: row, kind: kind, now: now)
            applied.conflict = StoredSyncConflict(
                kind: kind.rawValue, key: item.key, fields: ["record"], reason: .bothChanged, losing: local,
                foundAt: now)
        }
        return applied
    }

    /// Writes a payload into the row; the profile keeps this device's body data.
    private static func write(_ payload: StoredPayload, to row: StoredRecord, kind: RecordKind, now: Date) {
        var payload = payload
        if kind == .profile, let incoming = payload.decode(Profile.self),
            let current = StoredPayload(data: row.payload, version: row.payloadVersion).decode(Profile.self),
            let data = try? RecordPayload.encode(SyncBodyData.split(current).body.applied(to: incoming))
        {
            payload = StoredPayload(data: data, version: RecordPayload.currentVersion)
        }
        row.payload = payload.data
        row.payloadVersion = payload.version
        row.savedAt = now
    }

    private static func fetch(_ kind: RecordKind, _ key: String, in context: ModelContext) throws -> StoredRecord? {
        let kind = kind.rawValue
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.kind == kind && $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum SyncImages {
    /// The photos a record points to, read the way the backups read them.
    static func references(_ kind: RecordKind, _ payload: StoredPayload) -> [PhotoReference] {
        switch kind {
        case .garment: payload.decode(Garment.self)?.imageReferences ?? []
        case .picture: payload.decode(TryOnPicture.self)?.storedImages ?? []
        case .garmentDraft:
            payload.decode(GarmentDraft.self).map { [$0.details.photo, $0.base.photo].compactMap { $0 } } ?? []
        default: []
        }
    }

    /// Photos iCloud sent that the store's records may not point to yet (a photo can arrive before
    /// its piece). The launch sweep keeps them.
    static func downloaded(in rows: [StoreRow]) -> Set<String> {
        var ids: Set<String> = []
        for row in rows where row.kind == RecordKind.syncRecord.rawValue {
            guard let id = ICloudSync.recordID(metaKey: row.key), let imageID = SyncSchema.imageName(of: id) else {
                continue
            }
            ids.insert(imageID)
        }
        return ids
    }
}
