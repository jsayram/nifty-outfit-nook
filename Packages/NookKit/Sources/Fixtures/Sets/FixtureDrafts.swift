import Foundation
import Models

/// The unsaved drafts `-fixtures <set>:draft=<state>` puts in the draft store at launch, as if
/// the app had been closed in the middle of Add a piece or Edit (Phase 7b).
public enum FixtureDrafts {
    /// The words the add draft was described with. UI tests type the same words before they
    /// close the app, so the relaunch shows what they left.
    public static let addDescription = "Sage green cardigan with gold buttons, soft and cozy"

    /// The draft for `state`, saved five minutes before `now`. `nil` when the set has no piece
    /// to edit (the edit draft needs the demo's navy dress pants).
    public static func draft(_ state: FixtureDraftState, in data: FixtureData, now: Date) -> GarmentDraft? {
        let savedAt = now.addingTimeInterval(-5 * 60)
        switch state {
        case .add:
            var details = GarmentDetails.blank
            for suggestion in WordMatchDescriptionReader.suggestions(for: addDescription) {
                suggestion.apply(to: &details)
            }
            return GarmentDraft(
                target: .newPiece, step: .details, details: details, base: .blank, description: addDescription,
                savedAt: savedAt)
        case .look:
            // A Make your own look draft lives in its own store (`lookDraft(in:now:)`).
            return nil
        case .edit:
            guard let trousers = data.garments.first(where: { $0.id == "g-navy-trousers" }) else { return nil }
            let base = GarmentDetails(trousers)
            var details = base
            details.name = "Navy work trousers"
            return GarmentDraft(
                target: .garment(trousers.id), step: .details, details: details, base: base, savedAt: savedAt)
        }
    }

    /// The name of the look draft `-fixtures demo:draft=look` leaves. UI tests look for it.
    public static let lookDraftName = "Pink for Friday"

    /// A half-built Make your own look, saved five minutes before `now`: the pink shirt and the
    /// navy dress pants. `nil` when the set doesn't have them (only the demo does).
    public static func lookDraft(in data: FixtureData, now: Date) -> LookDraft? {
        let wanted: [Garment.ID] = ["g-pink-blouse", "g-navy-trousers"]
        guard wanted.allSatisfy({ id in data.garments.contains { $0.id == id } }) else { return nil }
        return LookDraft(name: lookDraftName, garmentIDs: wanted, savedAt: now.addingTimeInterval(-5 * 60))
    }
}
