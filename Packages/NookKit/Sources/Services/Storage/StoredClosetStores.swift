import Foundation
import Models
import SwiftData

// The real stores for her closet, looks, suitcases and try-on pictures (Phase 21a).
//
// Each is a `@ModelActor`: it owns a `ModelContext` on the store and hands out value types only,
// as the in-memory stores do, so the screens can't tell them apart (the store contracts check
// it). Each keeps the decoded values in memory after the first read and writes through, so lists
// come back as quickly as from the in-memory stores. Only that actor writes its kind of record,
// so what it keeps can't go stale.

/// Her garments, in the store on the iPhone.
@ModelActor
public actor StoredClosetStore: ClosetStore {
    private var calendar = Calendar.current
    private var cache: [Garment.ID: Garment]?
    private let table = RecordTable<Garment>(kind: .garment)
    /// When a piece was deleted for good, for its marker.
    private var now: @Sendable () -> Date = { .now }

    public init(container: ModelContainer, calendar: Calendar) {
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        modelContainer = container
        self.calendar = calendar
    }

    public func garments() async throws(StoreError) -> [Garment] {
        try loaded().values.sorted { lhs, rhs in
            lhs.addedAt != rhs.addedAt ? lhs.addedAt > rhs.addedAt : lhs.id < rhs.id
        }
    }

    public func garment(_ id: Garment.ID) async throws(StoreError) -> Garment {
        try existing(id)
    }

    public func save(_ garment: Garment) async throws(StoreError) {
        try write([try StoreValidation.garment(garment)])
    }

    @discardableResult
    public func update(_ id: Garment.ID, _ change: @Sendable (inout Garment) -> Void) async throws(StoreError)
        -> Garment
    {
        var garment = try existing(id)
        change(&garment)
        let saved = try StoreValidation.garment(garment)
        try write([saved])
        return saved
    }

    public func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        let calendar = calendar
        try changeEach(ids) { $0.wornOn = WearRules.recording(date, in: $0.wornOn, calendar: calendar) }
    }

    public func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) {
        let calendar = calendar
        try changeEach(ids) { $0.wornOn = WearRules.removing(date, from: $0.wornOn, calendar: calendar) }
    }

    public func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError) {
        try changeEach(ids) { $0.laundry = state }
    }

    public func delete(_ id: Garment.ID, at date: Date) async throws(StoreError) {
        try changeEach([id]) { $0.deletedAt = date }
    }

    public func restore(_ id: Garment.ID) async throws(StoreError) {
        try changeEach([id]) { $0.deletedAt = nil }
    }

    public func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID] {
        let expired = try loaded().values.filter { $0.purgeDate.map { $0 <= date } ?? false }.map(\.id).sorted()
        guard !expired.isEmpty else { return [] }
        try remove(expired)
        return expired
    }

    public func deletePermanently(_ id: Garment.ID) async throws(StoreError) {
        guard try existing(id).isDeleted else { throw .notFound }
        try remove([id])
    }

    /// Delete my data: every piece, Recently deleted included, and the deletion markers.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
        try RecordTable<StoredDeletion>(kind: .deletion).removeAll(in: modelContext)
        cache = [:]
    }

    // MARK: Helpers

    private func loaded() throws(StoreError) -> [Garment.ID: Garment] {
        if let cache { return cache }
        let values = try table.all(in: modelContext).values
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        cache = byID
        return byID
    }

    private func existing(_ id: Garment.ID) throws(StoreError) -> Garment {
        guard let garment = try loaded()[id] else { throw .notFound }
        return garment
    }

    private func write(_ garments: [Garment]) throws(StoreError) {
        var byID = try loaded()
        try table.write(
            Dictionary(garments.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { _, last in last }), in: modelContext)
        for garment in garments { byID[garment.id] = garment }
        cache = byID
    }

    /// Removes pieces for good, leaving a deletion marker for each in the same save, so a
    /// restore never brings one back (Phase 21b).
    private func remove(_ ids: [Garment.ID]) throws(StoreError) {
        var byID = try loaded()
        let date = now()
        let markers = Dictionary(
            ids.map { ($0.rawValue, StoredDeletion(deletedAt: date)) }, uniquingKeysWith: { _, last in last })
        try table.write([:], removing: ids.map(\.rawValue), in: modelContext) { context in
            try RecordTable<StoredDeletion>(kind: .deletion).stage(markers, in: context)
        }
        for id in ids { byID[id] = nil }
        cache = byID
    }

    /// Applies a change to every ID in one save, or to none of them if any ID is unknown.
    private func changeEach(_ ids: [Garment.ID], _ change: (inout Garment) -> Void) throws(StoreError) {
        let byID = try loaded()
        var changed: [Garment] = []
        for id in ids {
            guard var garment = byID[id] else { throw .notFound }
            change(&garment)
            changed.append(garment)
        }
        try write(changed)
    }
}

/// Her looks, in the store on the iPhone.
@ModelActor
public actor StoredLookStore: LookStore {
    private var calendar = Calendar.current
    private var cache: [Look.ID: Look]?
    private let table = RecordTable<Look>(kind: .look)

    public init(container: ModelContainer, calendar: Calendar) {
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        modelContainer = container
        self.calendar = calendar
    }

    public func looks() async throws(StoreError) -> [Look] {
        try loaded().values.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id < rhs.id
        }
    }

    public func look(_ id: Look.ID) async throws(StoreError) -> Look {
        try existing(id)
    }

    public func save(_ look: Look) async throws(StoreError) {
        try write(try StoreValidation.look(look))
    }

    @discardableResult
    public func update(_ id: Look.ID, _ change: @Sendable (inout Look) -> Void) async throws(StoreError) -> Look {
        var look = try existing(id)
        change(&look)
        let saved = try StoreValidation.look(look)
        try write(saved)
        return saved
    }

    public func delete(_ id: Look.ID) async throws(StoreError) {
        var byID = try loaded()
        guard byID[id] != nil else { throw .notFound }
        try table.write([:], removing: [id.rawValue], in: modelContext)
        byID[id] = nil
        cache = byID
    }

    public func recordWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        var look = try existing(id)
        look.wornOn = WearRules.recording(date, in: look.wornOn, calendar: calendar)
        try write(look)
    }

    public func removeWear(of id: Look.ID, on date: Date) async throws(StoreError) {
        var look = try existing(id)
        look.wornOn = WearRules.removing(date, from: look.wornOn, calendar: calendar)
        try write(look)
    }

    /// Delete my data: every look, saved or not.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
        cache = [:]
    }

    private func loaded() throws(StoreError) -> [Look.ID: Look] {
        if let cache { return cache }
        let values = try table.all(in: modelContext).values
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        cache = byID
        return byID
    }

    private func existing(_ id: Look.ID) throws(StoreError) -> Look {
        guard let look = try loaded()[id] else { throw .notFound }
        return look
    }

    private func write(_ look: Look) throws(StoreError) {
        var byID = try loaded()
        try table.write([look.id.rawValue: look], in: modelContext)
        byID[look.id] = look
        cache = byID
    }
}

/// Her suitcases, in the store on the iPhone.
@ModelActor
public actor StoredSuitcaseStore: SuitcaseStore {
    private var cache: [Suitcase.ID: Suitcase]?
    private let table = RecordTable<Suitcase>(kind: .suitcase)
    private var makeID: @Sendable () -> Suitcase.ID = { Suitcase.ID.random() }

    /// - Parameter makeID: makes the ID for a new suitcase. Tests pass a fixed one.
    public init(container: ModelContainer, makeID: @escaping @Sendable () -> Suitcase.ID = { Suitcase.ID.random() }) {
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        modelContainer = container
        self.makeID = makeID
    }

    public func suitcases() async throws(StoreError) -> [Suitcase] {
        try loaded().values.sorted { $0.id < $1.id }
    }

    public func suitcase(_ id: Suitcase.ID) async throws(StoreError) -> Suitcase {
        try existing(id)
    }

    public func create(name: String, icon: SuitcaseIcon, at date: Date) async throws(StoreError) -> Suitcase {
        let suitcase = Suitcase(id: makeID(), name: try checkedName(name, renaming: nil), icon: icon, createdAt: date)
        try write(suitcase)
        return suitcase
    }

    @discardableResult
    public func update(_ id: Suitcase.ID, _ change: @Sendable (inout Suitcase) -> Void) async throws(StoreError)
        -> Suitcase
    {
        var suitcase = try existing(id)
        change(&suitcase)
        suitcase.name = try checkedName(suitcase.name, renaming: id)
        try write(suitcase)
        return suitcase
    }

    public func add(_ garmentIDs: [Garment.ID], to id: Suitcase.ID) async throws(StoreError) {
        var suitcase = try existing(id)
        suitcase.garmentIDs.formUnion(garmentIDs)
        try write(suitcase)
    }

    public func remove(_ garmentIDs: [Garment.ID], from id: Suitcase.ID) async throws(StoreError) {
        var suitcase = try existing(id)
        suitcase.garmentIDs.subtract(garmentIDs)
        try write(suitcase)
    }

    public func markUsed(_ id: Suitcase.ID, at date: Date) async throws(StoreError) {
        var suitcase = try existing(id)
        suitcase.lastUsedAt = date
        try write(suitcase)
    }

    public func delete(_ id: Suitcase.ID) async throws(StoreError) {
        var byID = try loaded()
        guard byID[id] != nil else { throw .notFound }
        try table.write([:], removing: [id.rawValue], in: modelContext)
        byID[id] = nil
        cache = byID
    }

    public func restore(_ suitcase: Suitcase) async throws(StoreError) {
        var restored = suitcase
        restored.name = try checkedName(suitcase.name, renaming: suitcase.id)
        try write(restored)
    }

    /// Delete my data: every suitcase, archived ones included.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
        cache = [:]
    }

    private func loaded() throws(StoreError) -> [Suitcase.ID: Suitcase] {
        if let cache { return cache }
        let values = try table.all(in: modelContext).values
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        cache = byID
        return byID
    }

    private func existing(_ id: Suitcase.ID) throws(StoreError) -> Suitcase {
        guard let suitcase = try loaded()[id] else { throw .notFound }
        return suitcase
    }

    private func checkedName(_ name: String, renaming: Suitcase.ID?) throws(StoreError) -> String {
        try StoreValidation.suitcaseName(name, among: Array(try loaded().values), renaming: renaming)
    }

    private func write(_ suitcase: Suitcase) throws(StoreError) {
        var byID = try loaded()
        try table.write([suitcase.id.rawValue: suitcase], in: modelContext)
        byID[suitcase.id] = suitcase
        cache = byID
    }
}

/// Her try-on pictures' records, in the store on the iPhone. A simulated picture has no image
/// file; real ones get their files in Phase 22b.
@ModelActor
public actor StoredTryOnPictureStore: TryOnPictureStore {
    private var cache: [TryOnPicture.ID: TryOnPicture]?
    private let table = RecordTable<TryOnPicture>(kind: .picture)

    public func pictures() async throws(StoreError) -> [TryOnPicture] {
        TryOnLinks.newestFirst(Array(try loaded().values))
    }

    public func picture(_ id: TryOnPicture.ID) async throws(StoreError) -> TryOnPicture {
        guard let picture = try loaded()[id] else { throw .notFound }
        return picture
    }

    public func save(_ picture: TryOnPicture) async throws(StoreError) {
        var byID = try loaded()
        try table.write([picture.id.rawValue: picture], in: modelContext)
        byID[picture.id] = picture
        cache = byID
    }

    public func delete(_ id: TryOnPicture.ID) async throws(StoreError) {
        var byID = try loaded()
        guard byID[id] != nil else { throw .notFound }
        try table.write([:], removing: [id.rawValue], in: modelContext)
        byID[id] = nil
        cache = byID
    }

    /// Delete my data: every picture.
    public func eraseAll() async throws(StoreError) {
        try table.removeAll(in: modelContext)
        cache = [:]
    }

    private func loaded() throws(StoreError) -> [TryOnPicture.ID: TryOnPicture] {
        if let cache { return cache }
        let values = try table.all(in: modelContext).values
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        cache = byID
        return byID
    }
}
