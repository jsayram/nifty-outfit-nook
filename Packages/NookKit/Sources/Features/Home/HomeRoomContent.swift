import Foundation
import Models

/// What the room shows that comes from her data: the name on the sign, the source on the
/// suitcase, and the hamper. Everything else in the room is fixed art.
nonisolated struct HomeRoomContent: Hashable, Sendable {
    /// The name on the sign as stored, or `nil` until the profile has loaded.
    var signName: String?
    var source: SourcePlate
    /// `nil` until the closet and profile have loaded.
    var hamper: HamperState?
    /// The occasion on the calendar. `nil` until Style Me remembers one (Phase 10a).
    var occasion: Occasion?

    init(
        signName: String? = nil,
        source: SourcePlate = SourcePlate(),
        hamper: HamperState? = nil,
        occasion: Occasion? = nil
    ) {
        self.signName = signName
        self.source = source
        self.hamper = hamper
        self.occasion = occasion
    }
}

/// The suitcase's two plates: "Source · Main closet" and "17 pieces · Whole closet" (RD-01.3).
nonisolated struct SourcePlate: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case mainCloset
        case suitcase(name: String)
    }

    var kind: Kind
    /// How many pieces the source holds, or `nil` while loading or when it couldn't be counted.
    var pieceCount: Int?

    init(kind: Kind = .mainCloset, pieceCount: Int? = nil) {
        self.kind = kind
        self.pieceCount = pieceCount
    }

    var isSuitcase: Bool {
        if case .suitcase = kind { return true }
        return false
    }

    /// "Main closet", or the suitcase's name.
    var name: String {
        switch kind {
        case .mainCloset: String(localized: "Main closet", bundle: .module, comment: "Source plate: the whole closet")
        case .suitcase(let name): name
        }
    }

    /// "17 pieces", "1 piece" or "Empty". `nil` while there's no count.
    var countText: String? {
        guard let pieceCount else { return nil }
        if pieceCount == 0 {
            return String(localized: "Empty", bundle: .module, comment: "Source plate: the source has no pieces")
        }
        return String(
            localized: "\(pieceCount) pieces", bundle: .module, comment: "Source plate: how many pieces the source has")
    }

    /// "Whole closet" or "Suitcase only".
    var scopeText: String {
        isSuitcase
            ? String(
                localized: "Suitcase only", bundle: .module, comment: "Source plate: styling uses this suitcase only")
            : String(localized: "Whole closet", bundle: .module, comment: "Source plate: styling uses the whole closet")
    }
}

extension HamperState {
    /// The hamper plate's second line: "Off", "All clean" or "2 to wash" (RD-11).
    nonisolated var plateText: String {
        switch self {
        case .off:
            String(localized: "Off", bundle: .module, comment: "Hamper plate: laundry tracking is off")
        case .allClean:
            String(localized: "All clean", bundle: .module, comment: "Hamper plate: nothing to wash")
        case .toWash(let count):
            String(localized: "\(count) to wash", bundle: .module, comment: "Hamper plate: how many pieces are dirty")
        }
    }
}

/// The name shown on the wall sign (RD-03).
nonisolated enum SignName {
    /// What the sign says: her name, or a neutral word when she hasn't set one, so the sign is
    /// never blank (RD-03.2).
    static func shown(_ stored: String) -> String {
        let name = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    static var fallback: String {
        String(
            localized: "Hello", bundle: .module,
            comment: "Name sign when no name is set. A neutral greeting, not a name.")
    }

    static func isFallback(_ stored: String) -> Bool {
        stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
