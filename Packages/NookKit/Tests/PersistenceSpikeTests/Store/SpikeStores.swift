import Foundation
import Models
import SwiftData

// Phase 20a persistence spike: SwiftData behind the app's store protocols. Each store is a
// `@ModelActor`, so model objects never leave it; screens only ever get value types, as they do
// from the in-memory stores. They run the same contract suites (SpikeStoreContractTests).

typealias GarmentRecord = SpikeSchemaV3.GarmentRecord
typealias ImageAssetRecord = SpikeSchemaV3.ImageAssetRecord

/// Mapping between a garment and its record.
enum GarmentMapping {
    static func photoRef(_ photo: PhotoReference) -> String? {
        switch photo {
        case .noPhoto: nil
        case .sample(let name): "sample:\(name)"
        case .stored(let id): "stored:\(id.rawValue)"
        }
    }

    static func photo(_ ref: String?) -> PhotoReference {
        guard let ref else { return .noPhoto }
        if ref.hasPrefix("sample:") { return .sample(String(ref.dropFirst("sample:".count))) }
        if let id = SpikePhotoRef.storedID(ref) { return .stored(EntityID(id)) }
        return .noPhoto
    }

    static func record(for garment: Garment) throws -> GarmentRecord {
        let record = GarmentRecord(garmentID: garment.id.rawValue, name: garment.name, addedAt: garment.addedAt)
        try apply(garment, to: record)
        return record
    }

    static func apply(_ garment: Garment, to record: GarmentRecord) throws {
        let encoder = JSONEncoder()
        record.name = garment.name
        record.category = garment.category.rawValue
        record.colors = garment.colors.map(\.rawValue)
        record.shadeNote = garment.colorNote
        record.fit = garment.fit?.rawValue
        record.dressiness = garment.dressiness.rawValue
        record.warmth = garment.warmth.rawValue
        record.seasons = garment.seasons.map(\.rawValue).sorted()
        record.occasions = garment.occasions.map(\.rawValue).sorted()
        record.brand = garment.brand
        record.sizeLabel = garment.sizeLabel
        record.notes = garment.notes
        record.photoRef = photoRef(garment.photo)
        record.cutout = try garment.cutout.map { try encoder.encode($0) }
        record.ownership = try encoder.encode(garment.ownership)
        record.laundry = garment.laundry.rawValue
        record.availability = try encoder.encode(garment.availability)
        record.isArchived = garment.isArchived
        record.deletedAt = garment.deletedAt
        record.wornOn = garment.wornOn
        record.addedAt = garment.addedAt
    }

    static func garment(from record: GarmentRecord) throws -> Garment {
        let decoder = JSONDecoder()
        return Garment(
            id: EntityID(record.garmentID),
            name: record.name,
            category: GarmentCategory(rawValue: record.category) ?? .top,
            colors: record.colors.compactMap(ColorName.init(rawValue:)),
            colorNote: record.shadeNote,
            fit: record.fit.flatMap(GarmentFit.init(rawValue:)),
            dressiness: Dressiness(rawValue: record.dressiness) ?? .smart,
            warmth: Warmth(rawValue: record.warmth) ?? .medium,
            seasons: Set(record.seasons.compactMap(Season.init(rawValue:))),
            occasions: Set(record.occasions.compactMap(Occasion.init(rawValue:))),
            brand: record.brand,
            sizeLabel: record.sizeLabel,
            notes: record.notes,
            photo: photo(record.photoRef),
            cutout: try record.cutout.map { try decoder.decode(GarmentCutout.self, from: $0) },
            ownership: try decoder.decode(Ownership.self, from: record.ownership),
            laundry: LaundryState(rawValue: record.laundry) ?? .clean,
            availability: try decoder.decode(Availability.self, from: record.availability),
            isArchived: record.isArchived,
            deletedAt: record.deletedAt,
            wornOn: record.wornOn,
            addedAt: record.addedAt
        )
    }
}

/// Runs a SwiftData call, turning anything it throws into `unavailable`.
func storeCall<T>(_ body: () throws -> T) throws(StoreError) -> T {
    do {
        return try body()
    } catch let error as StoreError {
        throw error
    } catch {
        throw .unavailable
    }
}

@ModelActor
actor SwiftDataClosetStore: ClosetStore {
    private var calendar = Calendar(identifier: .gregorian)

    init(container: ModelContainer, calendar: Calendar) {
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        modelContainer = container
        self.calendar = calendar
    }

    func garments() async throws(StoreError) -> [Garment] {
        try storeCall {
            let records = try modelContext.fetch(
                FetchDescriptor<GarmentRecord>(
                    sortBy: [SortDescriptor(\.addedAt, order: .reverse), SortDescriptor(\.garmentID)]))
            return try records.map(GarmentMapping.garment(from:))
        }
    }

    func garment(_ id: Garment.ID) async throws(StoreError) -> Garment {
        let record = try existing(id)
        return try storeCall { try GarmentMapping.garment(from: record) }
    }

    func save(_ garment: Garment) async throws(StoreError) {
        let checked = try StoreValidation.garment(garment)
        try storeCall {
            if let record = try fetch(checked.id) {
                try GarmentMapping.apply(checked, to: record)
            } else {
                modelContext.insert(try GarmentMapping.record(for: checked))
            }
            try modelContext.save()
        }
    }

    @discardableResult
    func update(_ id: Garment.ID, _ change: @Sendable (inout Garment) -> Void) async throws(StoreError) -> Garment {
        let record = try existing(id)
        var garment = try storeCall { try GarmentMapping.garment(from: record) }
        change(&garment)
        let checked = try StoreValidation.garment(garment)
        try storeCall {
            try GarmentMapping.apply(checked, to: record)
            try modelContext.save()
        }
        return checked
    }

    func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        let calendar = calendar
        try changeEach(ids) { $0.wornOn = WearRules.recording(date, in: $0.wornOn, calendar: calendar) }
    }

    func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        let calendar = calendar
        try changeEach(ids) { $0.wornOn = WearRules.removing(date, from: $0.wornOn, calendar: calendar) }
    }

    func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError) {
        try changeEach(ids) { $0.laundry = state }
    }

    func delete(_ id: Garment.ID, at date: Date) async throws(StoreError) {
        try changeEach([id]) { $0.deletedAt = date }
    }

    func restore(_ id: Garment.ID) async throws(StoreError) {
        try changeEach([id]) { $0.deletedAt = nil }
    }

    func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID] {
        try storeCall {
            let deleted = try modelContext.fetch(
                FetchDescriptor<GarmentRecord>(predicate: #Predicate { $0.deletedAt != nil }))
            let expired = deleted.filter { record in
                record.deletedAt.map { $0.addingTimeInterval(Garment.recentlyDeletedDays * 86_400) <= date } ?? false
            }
            let ids = expired.map { Garment.ID($0.garmentID) }.sorted()
            expired.forEach(modelContext.delete)
            try modelContext.save()
            return ids
        }
    }

    /// Phase 21a's addition to the protocol, so the spike still builds.
    func deletePermanently(_ id: Garment.ID) async throws(StoreError) {
        let record = try existing(id)
        guard record.deletedAt != nil else { throw .notFound }
        try storeCall {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    /// Whether this actor's work runs on the main thread. Spike only.
    func runsOnTheMainThread() -> Bool {
        pthread_main_np() != 0
    }

    /// Inserts many garments in one save. Spike only, to build the large store quickly.
    func insertAll(_ garments: [Garment]) async throws(StoreError) {
        try storeCall {
            for garment in garments { modelContext.insert(try GarmentMapping.record(for: garment)) }
            try modelContext.save()
        }
    }

    func eraseAll() async throws(StoreError) {
        try storeCall {
            try modelContext.delete(model: GarmentRecord.self)
            try modelContext.save()
        }
    }

    // MARK: Helpers

    private func fetch(_ id: Garment.ID) throws -> GarmentRecord? {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<GarmentRecord>(predicate: #Predicate { $0.garmentID == raw })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existing(_ id: Garment.ID) throws(StoreError) -> GarmentRecord {
        guard let record = try storeCall({ try fetch(id) }) else { throw .notFound }
        return record
    }

    /// Changes every garment, or none if any ID is unknown, in one save.
    private func changeEach(_ ids: [Garment.ID], _ change: (inout Garment) -> Void) throws(StoreError) {
        var records: [GarmentRecord] = []
        for id in ids { records.append(try existing(id)) }
        try storeCall {
            for record in records {
                var garment = try GarmentMapping.garment(from: record)
                change(&garment)
                try GarmentMapping.apply(garment, to: record)
            }
            try modelContext.save()
        }
    }
}

@ModelActor
actor SwiftDataLookStore: LookStore {
    private var calendar = Calendar(identifier: .gregorian)

    init(container: ModelContainer, calendar: Calendar) {
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        modelContainer = container
        self.calendar = calendar
    }

    func looks() async throws(StoreError) -> [Look] {
        try storeCall {
            try modelContext.fetch(
                FetchDescriptor<LookRecord>(sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.lookID),
                ])
            )
            .map { try JSONDecoder().decode(Look.self, from: $0.payload) }
        }
    }

    func look(_ id: Look.ID) async throws(StoreError) -> Look {
        let record = try existing(id)
        return try storeCall { try JSONDecoder().decode(Look.self, from: record.payload) }
    }

    func save(_ look: Look) async throws(StoreError) {
        let checked = try StoreValidation.look(look)
        try storeCall {
            try write(checked, to: try fetch(checked.id))
            try modelContext.save()
        }
    }

    @discardableResult
    func update(_ id: Look.ID, _ change: @Sendable (inout Look) -> Void) async throws(StoreError) -> Look {
        var look = try await self.look(id)
        change(&look)
        let checked = try StoreValidation.look(look)
        let record = try existing(id)
        try storeCall {
            try write(checked, to: record)
            try modelContext.save()
        }
        return checked
    }

    func delete(_ id: Look.ID) async throws(StoreError) {
        let record = try existing(id)
        try storeCall {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func recordWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        let calendar = calendar
        try await update(id) { $0.wornOn = WearRules.recording(date, in: $0.wornOn, calendar: calendar) }
    }

    func removeWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        let calendar = calendar
        try await update(id) { $0.wornOn = WearRules.removing(date, from: $0.wornOn, calendar: calendar) }
    }

    func eraseAll() async throws(StoreError) {
        try storeCall {
            try modelContext.delete(model: LookRecord.self)
            try modelContext.save()
        }
    }

    private func write(_ look: Look, to record: LookRecord?) throws {
        let payload = try JSONEncoder().encode(look)
        let pieces = look.garmentIDs.map(\.rawValue)
        if let record {
            record.createdAt = look.createdAt
            record.isSaved = look.isSaved
            record.garmentIDs = pieces
            record.payload = payload
        } else {
            modelContext.insert(
                LookRecord(
                    lookID: look.id.rawValue, createdAt: look.createdAt, isSaved: look.isSaved, garmentIDs: pieces,
                    payload: payload))
        }
    }

    private func fetch(_ id: Look.ID) throws -> LookRecord? {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<LookRecord>(predicate: #Predicate { $0.lookID == raw })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existing(_ id: Look.ID) throws(StoreError) -> LookRecord {
        guard let record = try storeCall({ try fetch(id) }) else { throw .notFound }
        return record
    }
}

@ModelActor
actor SwiftDataSuitcaseStore: SuitcaseStore {
    func suitcases() async throws(StoreError) -> [Suitcase] {
        try storeCall {
            try modelContext.fetch(FetchDescriptor<SuitcaseRecord>(sortBy: [SortDescriptor(\.suitcaseID)]))
                .map { try JSONDecoder().decode(Suitcase.self, from: $0.payload) }
        }
    }

    func suitcase(_ id: Suitcase.ID) async throws(StoreError) -> Suitcase {
        let record = try existing(id)
        return try storeCall { try JSONDecoder().decode(Suitcase.self, from: record.payload) }
    }

    func create(name: String, icon: SuitcaseIcon, at date: Date) async throws(StoreError) -> Suitcase {
        let others = try await suitcases()
        let checked = try StoreValidation.suitcaseName(name, among: others, renaming: nil)
        let suitcase = Suitcase(id: .random(), name: checked, icon: icon, createdAt: date)
        try storeCall {
            try write(suitcase, to: nil)
            try modelContext.save()
        }
        return suitcase
    }

    @discardableResult
    func update(_ id: Suitcase.ID, _ change: @Sendable (inout Suitcase) -> Void) async throws(StoreError) -> Suitcase {
        var suitcase = try await self.suitcase(id)
        change(&suitcase)
        suitcase.name = try StoreValidation.suitcaseName(suitcase.name, among: try await suitcases(), renaming: id)
        let record = try existing(id)
        try storeCall {
            try write(suitcase, to: record)
            try modelContext.save()
        }
        return suitcase
    }

    func add(_ garmentIDs: [Garment.ID], to id: Suitcase.ID) async throws(StoreError) {
        try await update(id) { $0.garmentIDs.formUnion(garmentIDs) }
    }

    func remove(_ garmentIDs: [Garment.ID], from id: Suitcase.ID) async throws(StoreError) {
        try await update(id) { $0.garmentIDs.subtract(garmentIDs) }
    }

    func markUsed(_ id: Suitcase.ID, at date: Date) async throws(StoreError) {
        try await update(id) { $0.lastUsedAt = date }
    }

    func delete(_ id: Suitcase.ID) async throws(StoreError) {
        let record = try existing(id)
        try storeCall {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func restore(_ suitcase: Suitcase) async throws(StoreError) {
        var restored = suitcase
        restored.name = try StoreValidation.suitcaseName(
            suitcase.name, among: try await suitcases(), renaming: suitcase.id)
        try storeCall {
            try write(restored, to: try fetch(suitcase.id))
            try modelContext.save()
        }
    }

    func eraseAll() async throws(StoreError) {
        try storeCall {
            try modelContext.delete(model: SuitcaseRecord.self)
            try modelContext.save()
        }
    }

    private func write(_ suitcase: Suitcase, to record: SuitcaseRecord?) throws {
        let payload = try JSONEncoder().encode(suitcase)
        let pieces = suitcase.garmentIDs.map(\.rawValue).sorted()
        if let record {
            record.name = suitcase.name
            record.garmentIDs = pieces
            record.payload = payload
        } else {
            modelContext.insert(
                SuitcaseRecord(
                    suitcaseID: suitcase.id.rawValue, name: suitcase.name, garmentIDs: pieces, payload: payload))
        }
    }

    private func fetch(_ id: Suitcase.ID) throws -> SuitcaseRecord? {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<SuitcaseRecord>(predicate: #Predicate { $0.suitcaseID == raw })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existing(_ id: Suitcase.ID) throws(StoreError) -> SuitcaseRecord {
        guard let record = try storeCall({ try fetch(id) }) else { throw .notFound }
        return record
    }
}
