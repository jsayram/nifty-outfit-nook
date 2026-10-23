import Foundation
import Models

// The conflict rules for sync (PRD 11.7, decision 0004 "Merge rules"), proven as pure functions in
// the 20a spike and now per record type.
//
// A merge is three-way: the version both sides last agreed on (the ancestor), this device's and
// the server's. A field only one side changed takes that change; both changed it the same way is
// fine. Both changed it differently:
//
// - Pieces, field by field: removal and restriction win (Recently deleted, archived, no longer
//   owned, unavailable, dirty); anything else keeps the server's value, which is whichever device
//   got there first, never a device clock. Wear days are a set: both sides' additions and
//   removals apply.
// - Suitcases, field by field: memberships are a set, archived wins, the later "last used" stays,
//   and anything else keeps the server's value.
// - Everything else (looks, try-on pictures, the profile, drafts, app state, Ask stylist
//   conversations) as a whole: the server's version stays.
//
// Whatever lost is kept for her to review (`StoredSyncConflict`), never dropped silently.

/// A merged payload, written at this build's payload version, and the fields that conflicted.
struct SyncMergeOutcome: Hashable, Sendable {
    var payload: Data
    /// The fields both sides changed differently, or `["record"]` for a whole-record conflict.
    var fields: [String]
}

/// One kind's comparison and merge, over payloads as stored.
struct SyncCodec: Sendable {
    /// Whether two payloads hold the same value. Compared as values, since JSON from sets and
    /// dictionaries isn't byte-stable between launches. A payload this build can't read is
    /// compared byte for byte.
    let same: @Sendable (_ lhs: StoredPayload, _ rhs: StoredPayload) -> Bool
    /// The three-way merge, or `nil` when a payload can't be read (a newer version).
    let merge:
        @Sendable (_ ancestor: StoredPayload?, _ local: StoredPayload, _ server: StoredPayload) ->
            SyncMergeOutcome?

    static let byKind: [RecordKind: SyncCodec] = [
        .garment: make(Garment.self, merge: SyncMerge.garment),
        .look: make(Look.self),
        .suitcase: make(Suitcase.self, merge: SyncMerge.suitcase),
        .picture: make(TryOnPicture.self),
        .garmentDraft: make(GarmentDraft.self),
        .lookDraft: make(LookDraft.self),
        .profile: make(Profile.self),
        .onboarding: make(StoredOnboarding.self),
        .tours: make(StoredTours.self),
        .stylistThread: make(StylistThread.self),
    ]

    private static func make<Value: Codable & Equatable & Sendable>(
        _ type: Value.Type,
        merge: @escaping @Sendable (Value?, Value, Value) -> (Value, [String]) = SyncMerge.whole
    ) -> SyncCodec {
        SyncCodec(
            same: { lhs, rhs in
                if let left = lhs.decode(Value.self), let right = rhs.decode(Value.self) { return left == right }
                return lhs == rhs
            },
            merge: { ancestor, local, server in
                guard let mine = local.decode(Value.self), let theirs = server.decode(Value.self) else { return nil }
                // An ancestor this build can't read is no ancestor: every difference is a conflict.
                let base = ancestor.flatMap { $0.decode(Value.self) }
                let (merged, fields) = merge(base, mine, theirs)
                guard let payload = try? RecordPayload.encode(merged) else { return nil }
                return SyncMergeOutcome(payload: payload, fields: fields)
            })
    }
}

/// A payload with the version it was written at.
struct StoredPayload: Hashable, Codable, Sendable {
    var data: Data
    var version: Int

    func decode<Value: Decodable>(_ type: Value.Type) -> Value? {
        try? RecordPayload.decode(type, from: data, version: version)
    }
}

enum SyncMerge {
    /// The whole record: one side's change wins if only it changed; both changed, the server's stays.
    static func whole<Value: Equatable>(ancestor: Value?, local: Value, server: Value) -> (Value, [String]) {
        if local == server { return (server, []) }
        if let ancestor, local == ancestor { return (server, []) }
        if let ancestor, server == ancestor { return (local, []) }
        return (server, ["record"])
    }

    static func garment(ancestor: Garment?, local: Garment, server: Garment) -> (Garment, [String]) {
        // With no ancestor (first meeting, or after an account's copy was replaced), the server's
        // version is the base, so every difference is a conflict.
        var fields = FieldMerge(base: ancestor ?? server, local: local, server: server)
        fields.merge("name", \.name)
        fields.merge("otherNames", \.otherNames)
        fields.merge("category", \.category)
        fields.merge("subKind", \.subKind)
        fields.merge("colors", \.colors)
        fields.merge("colorNote", \.colorNote)
        fields.merge("fit", \.fit)
        fields.merge("dressiness", \.dressiness)
        fields.merge("warmth", \.warmth)
        fields.merge("seasons", \.seasons)
        fields.merge("occasions", \.occasions)
        fields.merge("brand", \.brand)
        fields.merge("sizeLabel", \.sizeLabel)
        fields.merge("notes", \.notes)
        fields.merge("photo", \.photo)
        fields.merge("cutout", \.cutout)
        fields.merge("deletedAt", \.deletedAt) { mine, theirs in
            // Both changed: if either says deleted, it stays deleted, from the earlier date.
            switch (mine, theirs) {
            case (let a?, let b?): min(a, b)
            case (let a?, nil): a
            case (nil, let b): b
            }
        }
        fields.merge("isArchived", \.isArchived) { $0 || $1 }
        fields.merge("ownership", \.ownership) { mine, theirs in
            mine == .noLongerOwned || theirs == .noLongerOwned ? .noLongerOwned : theirs
        }
        fields.merge("laundry", \.laundry) { mine, theirs in mine == .dirty || theirs == .dirty ? .dirty : .clean }
        fields.merge("availability", \.availability) { mine, theirs in
            if case .unavailable = theirs { return theirs }
            if case .unavailable = mine { return mine }
            return theirs
        }
        fields.merged.wornOn = mergeSet(
            ancestor: Set(fields.base.wornOn), local: Set(local.wornOn), server: Set(server.wornOn)
        ).sorted()
        return (fields.merged, fields.conflicts)
    }

    static func suitcase(ancestor: Suitcase?, local: Suitcase, server: Suitcase) -> (Suitcase, [String]) {
        var fields = FieldMerge(base: ancestor ?? server, local: local, server: server)
        fields.merge("name", \.name)
        fields.merge("icon", \.icon)
        fields.merge("isArchived", \.isArchived) { $0 || $1 }
        fields.merge("lastUsedAt", \.lastUsedAt) { mine, theirs in
            switch (mine, theirs) {
            case (let a?, let b?): max(a, b)
            default: mine ?? theirs
            }
        }
        // Membership edits from both sides apply (PRD 11.7, "merge independent membership edits").
        fields.merged.garmentIDs = mergeSet(
            ancestor: fields.base.garmentIDs, local: local.garmentIDs, server: server.garmentIDs)
        return (fields.merged, fields.conflicts)
    }

    static func mergeSet<Element: Hashable>(ancestor: Set<Element>, local: Set<Element>, server: Set<Element>)
        -> Set<Element>
    {
        let added = local.subtracting(ancestor).union(server.subtracting(ancestor))
        let removed = ancestor.subtracting(local).union(ancestor.subtracting(server))
        return ancestor.union(added).subtracting(removed)
    }

    /// Field-by-field merging of one value.
    private struct FieldMerge<Value> {
        let base: Value
        let local: Value
        let server: Value
        var merged: Value
        var conflicts: [String] = []

        init(base: Value, local: Value, server: Value) {
            self.base = base
            self.local = local
            self.server = server
            merged = server
        }

        /// `restrictive` picks the winner when both changed it; without one, the server's stays.
        mutating func merge<Field: Equatable>(
            _ name: String, _ path: WritableKeyPath<Value, Field>, restrictive: ((Field, Field) -> Field)? = nil
        ) {
            let mine = local[keyPath: path]
            let theirs = server[keyPath: path]
            if mine == theirs || mine == base[keyPath: path] { return }  // the server's value stands
            if theirs == base[keyPath: path] {
                merged[keyPath: path] = mine
                return
            }
            merged[keyPath: path] = restrictive?(mine, theirs) ?? theirs
            conflicts.append(name)
        }
    }
}
