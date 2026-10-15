import Foundation

/// Which source she's browsing from, given the one she chose last (FR-67, PRD §7.7).
///
/// Home's suitcase and the selection on Suitcases show the remembered source while it's still
/// there. If that suitcase has been deleted or archived, browsing goes back to the main closet
/// (PRD §7.7: "return browsing and the configured default to Main Closet"). This is for showing
/// only: Style Me starts from the remembered source as it is, so a missing suitcase there asks
/// her to choose again instead of quietly styling from everything (FR-67).
public enum SourceChoice {
    /// The remembered source, or the main closet when its suitcase is gone or archived.
    public static func shown(_ remembered: WardrobeSource, among suitcases: [Suitcase]) -> WardrobeSource {
        isAvailable(remembered, among: suitcases) ? remembered : .mainCloset
    }

    /// True for the main closet, and for a suitcase that exists and isn't archived.
    public static func isAvailable(_ source: WardrobeSource, among suitcases: [Suitcase]) -> Bool {
        guard let id = source.suitcaseID else { return true }
        return suitcases.contains { $0.id == id && !$0.isArchived }
    }

    /// The pieces of her closet in a source: every piece in her closet for the main closet, or
    /// the suitcase's pieces that are still in her closet. A piece she no longer has, or one in
    /// Recently deleted, keeps its suitcase link in the data but never shows (LR-16.1).
    public static func pieces(in source: WardrobeSource, garments: [Garment], suitcases: [Suitcase]) -> [Garment] {
        guard let id = source.suitcaseID else { return garments.filter(\.isInCloset) }
        guard let suitcase = suitcases.first(where: { $0.id == id }) else { return [] }
        return garments.filter { $0.isInCloset && suitcase.contains($0.id) }
    }
}
