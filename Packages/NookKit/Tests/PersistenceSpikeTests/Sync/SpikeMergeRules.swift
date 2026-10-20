import Foundation
import Models

// Phase 20a persistence spike: PRD 11.7's conflict rules as pure functions, so they can be tested
// without a network, a device or an iCloud account.
//
// A merge is three-way: the version both devices last agreed on (the ancestor), this device's
// version and the server's. A field only one side changed takes that change. A field both sides
// changed the same way is fine. A field both sides changed differently is a conflict:
//
// - Removal and restriction win, so nothing becomes eligible again by accident: Recently
//   deleted, archived, no longer owned and unavailable beat the other side, and dirty beats
//   clean. The other side's value is kept as a conflict for her to review.
// - Anything else keeps the server's value, which is whichever device reached the server first,
//   never a device clock, and keeps this device's value as a competing revision for review.
// - Wear days are a set: both sides' additions and removals apply.
// - A piece deleted for good stays deleted. Edits to it from a stale device are dropped and
//   reported.

/// A value this device lost in a merge, kept so she can review it.
struct SpikeConflict: Codable, Hashable, Sendable {
    var recordName: String
    var field: String
    /// The value the merge kept.
    var kept: String
    /// The value that didn't win.
    var competing: String
}

struct SpikeMergeResult: Equatable, Sendable {
    var garment: Garment
    var conflicts: [SpikeConflict]
}

enum SpikeMergeRules {
    static func merge(ancestor: Garment?, local: Garment, server: Garment) -> SpikeMergeResult {
        // With no ancestor (both devices made the same ID, which IDs from UUIDs rule out), the
        // server's version is the base and every difference is a conflict.
        let base = ancestor ?? server
        var merged = server
        var conflicts: [SpikeConflict] = []
        let name = local.id.rawValue

        func field<Value: Equatable>(
            _ key: String, _ path: WritableKeyPath<Garment, Value>, restrictive: ((Value, Value) -> Value)? = nil
        ) {
            let mine = local[keyPath: path]
            let theirs = server[keyPath: path]
            let old = base[keyPath: path]
            if mine == theirs || mine == old { return }  // the server's value stands
            if theirs == old {
                merged[keyPath: path] = mine
                return
            }
            let kept = restrictive?(mine, theirs) ?? theirs
            merged[keyPath: path] = kept
            conflicts.append(
                SpikeConflict(
                    recordName: name, field: key, kept: describe(kept),
                    competing: describe(kept == mine ? theirs : mine)))
        }

        field("name", \.name)
        field("category", \.category)
        field("colors", \.colors)
        field("colorNote", \.colorNote)
        field("fit", \.fit)
        field("dressiness", \.dressiness)
        field("warmth", \.warmth)
        field("seasons", \.seasons)
        field("occasions", \.occasions)
        field("brand", \.brand)
        field("sizeLabel", \.sizeLabel)
        field("notes", \.notes)
        field("photo", \.photo)
        field("cutout", \.cutout)
        field("deletedAt", \.deletedAt) { mine, theirs in
            // Both changed: if either says deleted, it stays deleted (the earlier date).
            switch (mine, theirs) {
            case (let a?, let b?): min(a, b)
            case (let a?, nil): a
            case (nil, let b): b
            }
        }
        field("isArchived", \.isArchived) { $0 || $1 }
        field("ownership", \.ownership) { mine, theirs in
            mine == .noLongerOwned || theirs == .noLongerOwned ? .noLongerOwned : theirs
        }
        field("laundry", \.laundry) { mine, theirs in mine == .dirty || theirs == .dirty ? .dirty : .clean }
        field("availability", \.availability) { mine, theirs in
            if case .unavailable = theirs { return theirs }
            if case .unavailable = mine { return mine }
            return theirs
        }
        merged.wornOn = mergeSet(ancestor: base.wornOn, local: local.wornOn, server: server.wornOn).sorted()
        return SpikeMergeResult(garment: merged, conflicts: conflicts)
    }

    /// Suitcase membership: both sides' additions and removals apply (PRD 11.7, "merge
    /// independent membership edits").
    static func mergeMembership(ancestor: Set<Garment.ID>, local: Set<Garment.ID>, server: Set<Garment.ID>)
        -> Set<Garment.ID>
    {
        Set(mergeSet(ancestor: Array(ancestor), local: Array(local), server: Array(server)))
    }

    private static func mergeSet<Element: Hashable>(ancestor: [Element], local: [Element], server: [Element])
        -> [Element]
    {
        let old = Set(ancestor)
        let mine = Set(local)
        let theirs = Set(server)
        let added = mine.subtracting(old).union(theirs.subtracting(old))
        let removed = old.subtracting(mine).union(old.subtracting(theirs))
        return Array(old.union(added).subtracting(removed))
    }

    private static func describe<Value>(_ value: Value) -> String {
        String(describing: value)
    }
}
