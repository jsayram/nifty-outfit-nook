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
        case .edit:
            guard let trousers = data.garments.first(where: { $0.id == "g-navy-trousers" }) else { return nil }
            let base = GarmentDetails(trousers)
            var details = base
            details.name = "Navy work trousers"
            return GarmentDraft(
                target: .garment(trousers.id), step: .details, details: details, base: base, savedAt: savedAt)
        }
    }
}
