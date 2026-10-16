import Foundation
import Models
import Observation

/// Everything Swap a piece works from, gathered by the screen that opens it. Swap reads no store
/// and sends no request (LR-07.1).
struct SwapSetup {
    /// The look as it is now, maybe already changed by an earlier swap.
    var look: Look
    /// The stylist's Simple version, for the "Same as Simple" marks. `nil` for a look she made.
    var simple: Look?
    /// Every garment she has, by ID.
    var garments: [Garment.ID: Garment]
    /// Her suitcases, for See all's Suitcase filter.
    var suitcases: [Suitcase]
    var situation: SwapSituation
    /// "Main closet", or the suitcase's name.
    var sourceName: String
    /// LR-07.4: "Not in your closet? Find one" only with Mine + one idea. A suitcase never
    /// offers an unowned piece (LR-05b).
    var allowsFindOne: Bool
    /// Seeds the bundle's layout: the ID of the look before any swap, so it lies as it did.
    var layoutSeed: String?
}

/// Swap a piece (LR-07, LR-08): pick a piece of the look, see her own pieces that go with it,
/// three at a time, try one in the look, then use it or keep the one there. Remove this piece
/// takes it out instead. Either way the screen that opened Swap gets the changed look back and
/// offers Undo.
///
/// The options are ranked once per piece, on the phone (`SwapRanking`). Show 3 more only shows
/// more of that list, so it's instant with the large closet too (LR-07.5).
@Observable
final class SwapModel {
    /// How many options show at first, and how many more each Show 3 more adds.
    static let pageSize = 3

    let setup: SwapSetup
    /// The piece being swapped.
    private(set) var pieceID: LookPiece.ID
    private(set) var options: SwapOptions
    /// How many of `options.ranked` are showing.
    private(set) var shownCount = SwapModel.pageSize
    /// The option she's trying in the look, if any.
    private(set) var preview: Garment.ID?

    private let makeLookID: () -> Look.ID
    private let now: () -> Date

    /// - Parameter pieceID: the piece to start on. Defaults to the first main piece.
    init(
        setup: SwapSetup,
        pieceID: LookPiece.ID? = nil,
        makeLookID: @escaping () -> Look.ID = { .random() },
        now: @escaping () -> Date = { .now }
    ) {
        self.setup = setup
        self.makeLookID = makeLookID
        self.now = now
        let pieces = Self.bodyOrder(setup.look, garments: setup.garments)
        let start =
            pieceID ?? pieces.first { piece in
                Self.category(of: piece, in: setup.garments).map(WearRules.mainCategories.contains) ?? false
            }?.id ?? pieces.first?.id ?? LookPiece.ID("")
        self.pieceID = start
        options =
            SwapRanking.options(for: start, in: setup.look, garments: setup.garments, situation: setup.situation)
            ?? SwapOptions(category: .top)
    }

    // MARK: Which piece

    /// The look's pieces, top to bottom, for the Which piece chips.
    var pieces: [LookPiece] {
        Self.bodyOrder(setup.look, garments: setup.garments)
    }

    var piece: LookPiece? {
        setup.look.pieces.first { $0.id == pieceID }
    }

    var category: GarmentCategory { options.category }

    /// The piece's name, for the chips and the tagline.
    func name(of piece: LookPiece) -> String {
        switch piece.content {
        case .garment(let id): setup.garments[id]?.name ?? ""
        case .idea(let idea): idea.name
        }
    }

    func category(of piece: LookPiece) -> GarmentCategory? {
        Self.category(of: piece, in: setup.garments)
    }

    /// Picks another piece to swap. Ranks its options and starts at the first three again.
    func choosePiece(_ id: LookPiece.ID) {
        guard id != pieceID, setup.look.pieces.contains(where: { $0.id == id }) else { return }
        pieceID = id
        options =
            SwapRanking.options(for: id, in: setup.look, garments: setup.garments, situation: setup.situation)
            ?? SwapOptions(category: .top)
        shownCount = Self.pageSize
        preview = nil
    }

    // MARK: Options

    /// The good matches showing now, best first.
    var visibleOptions: [Garment.ID] {
        Array(options.ranked.prefix(shownCount))
    }

    /// True while Show 3 more has more to show.
    var canShowMore: Bool { shownCount < options.ranked.count }

    /// Shows the next three good matches. Ranks nothing and sends nothing (LR-07.1).
    func showMore() {
        guard canShowMore else { return }
        shownCount = min(shownCount + Self.pageSize, options.ranked.count)
    }

    /// True when See all has anything to list.
    var hasSeeAll: Bool { !options.isEmpty }

    /// See all: every piece she can wear of this kind, good matches first, the others marked.
    var seeAllScope: PieceScope {
        var notes: [Garment.ID: String] = [:]
        for id in options.weaker { notes[id] = SwapText.mayNotMatch }
        for id in options.wornRecently.keys { notes[id] = SwapText.wornTogether }
        return PieceScope(garmentIDs: options.all, notes: notes, fixedKind: options.category)
    }

    /// Tries a piece in the look. Choosing the one there already, or tapping the one being tried,
    /// goes back to the look as it is.
    func select(_ id: Garment.ID) {
        if id == preview || id == piece?.garmentID {
            preview = nil
        } else if options.all.contains(id) {
            preview = id
        }
    }

    /// Keep current: back to the look as it is.
    func keepCurrent() {
        preview = nil
    }

    /// The look with the option being tried, or the look as it is. Keeps the look's ID, so the
    /// bundle lies the same way while she tries things.
    var shownLook: Look {
        guard let preview,
            var look = LookEditing.replacing(
                pieceID, with: preview, in: setup.look, simple: setup.simple, newID: setup.look.id,
                at: setup.look.createdAt
            )
        else { return setup.look }
        look.name = setup.look.name
        return look
    }

    // MARK: Committing

    /// Use this top: the changed look, with a new ID. `nil` until she's trying a piece.
    func swapped() -> Look? {
        guard let preview else { return nil }
        return LookEditing.replacing(
            pieceID, with: preview, in: setup.look, simple: setup.simple, newID: makeLookID(), at: now())
    }

    /// Why Remove this piece is off, or `nil` when the rest is still a look.
    var removalProblem: LookProblem? {
        let rest = LookEditing.categories(of: setup.look, without: pieceID, garments: setup.garments)
        return LookRules.shapeProblems(of: rest, onePerKind: false).first
    }

    /// Remove this piece: the look without it, with a new ID. `nil` when that wouldn't be a look.
    func removed() -> Look? {
        guard removalProblem == nil else { return nil }
        return LookEditing.removing(pieceID, from: setup.look, simple: setup.simple, newID: makeLookID(), at: now())
    }

    // MARK: Helpers

    private static func category(of piece: LookPiece, in garments: [Garment.ID: Garment]) -> GarmentCategory? {
        switch piece.content {
        case .garment(let id): garments[id]?.category
        case .idea(let idea): idea.category
        }
    }

    private static func bodyOrder(_ look: Look, garments: [Garment.ID: Garment]) -> [LookPiece] {
        look.pieces.enumerated()
            .sorted { lhs, rhs in
                let left = category(of: lhs.element, in: garments)?.listOrder ?? .max
                let right = category(of: rhs.element, in: garments)?.listOrder ?? .max
                return (left, lhs.offset) < (right, rhs.offset)
            }
            .map(\.element)
    }
}
