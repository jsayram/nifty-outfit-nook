import Foundation
import Models

/// The words for one kind of piece inside Swap's sentences: "tops", "every top", "this top",
/// "the top". Shoes are a pair, so they read "every pair of shoes" and "these shoes".
struct SwapKindWords {
    /// "tops", for "Your tops that go with this look".
    let plural: String
    /// "every top", for "That's every top in Main closet".
    let every: String
    /// "this top", for "Use this top".
    let this: String
    /// "Only the top changes. Everything else stays."
    let onlyThisChanges: String

    init(_ category: GarmentCategory) {
        switch category {
        case .top:
            plural = String(localized: "tops", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every top", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "this top", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the top changes. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        case .bottom:
            plural = String(localized: "bottoms", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every bottom", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "this bottom", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the bottom changes. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        case .dress:
            plural = String(localized: "dresses", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every dress", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "this dress", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the dress changes. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        case .layer:
            plural = String(localized: "layers", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every layer", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "this layer", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the layer changes. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        case .shoes:
            plural = String(localized: "shoes", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every pair of shoes", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "these shoes", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the shoes change. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        case .bag:
            plural = String(localized: "bags", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every bag", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "this bag", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the bag changes. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        case .accessory:
            plural = String(localized: "accessories", bundle: .module, comment: "Swap: kind of piece, plural")
            every = String(localized: "every accessory", bundle: .module, comment: "Swap: That's every …")
            this = String(localized: "this accessory", bundle: .module, comment: "Swap: Use …")
            onlyThisChanges = String(
                localized: "Only the accessory changes. Everything else stays.", bundle: .module,
                comment: "Swap: under the buttons once she picked an option (FR-09)")
        }
    }
}

/// Every line on Swap a piece (LR-07, LR-08), from the kind being swapped and the source's name.
struct SwapText {
    let category: GarmentCategory
    /// "Main closet", or the suitcase's name.
    let sourceName: String

    private var words: SwapKindWords { SwapKindWords(category) }

    /// LR-07: the line above the options.
    var explanation: String {
        let plural = words.plural
        return String(
            localized: "Your \(plural) that go with this look", bundle: .module,
            comment: "Swap: the line above the options (LR-07), with the kind of piece")
    }

    /// LR-07.3: at the end of the list.
    var everyOne: String {
        let every = words.every
        return String(
            localized: "That’s \(every) in \(sourceName).", bundle: .module,
            comment: "Swap: the end of the options (LR-07.3): every top, then the source's name")
    }

    /// When nothing goes with the look: there are no good matches to show three at a time.
    var noneThatGo: String {
        let plural = words.plural
        return String(
            localized: "None of your other \(plural) in \(sourceName) go with this look.", bundle: .module,
            comment: "Swap: no good matches, with the kind of piece and the source's name")
    }

    /// When there's nothing else of this kind she can wear from the source.
    var nothingElse: String {
        let plural = words.plural
        return String(
            localized: "No other \(plural) in \(sourceName) can be worn today.", bundle: .module,
            comment: "Swap: no options at all, with the kind of piece and the source's name")
    }

    /// LR-07.3: "See all tops".
    var seeAll: String {
        let plural = words.plural
        return String(localized: "See all \(plural)", bundle: .module, comment: "Swap: button at the end (LR-07.3)")
    }

    /// The See all sheet's title.
    var seeAllTitle: String {
        let chip = category.chipTitle
        return String(localized: "All \(chip)", bundle: .module, comment: "Swap: See all sheet title, as in All Tops")
    }

    var seeAllLead: String {
        String(
            localized:
                "Everything you can wear today from \(sourceName). Pieces marked May not match don’t go with the rest of the look as well.",
            bundle: .module, comment: "Swap: under the See all title, with the source's name")
    }

    /// "Use this top".
    var use: String {
        let this = words.this
        return String(localized: "Use \(this)", bundle: .module, comment: "Swap: commits the swap, as in Use this top")
    }

    /// Under the buttons: what the swap changes, or how to start.
    func hint(isPreviewing: Bool) -> String {
        if isPreviewing { return words.onlyThisChanges }
        return String(
            localized: "Tap one to see it in the look.", bundle: .module,
            comment: "Swap: under the buttons before she picks an option")
    }

    /// A piece's kind on its own, for the Which piece chips and the tagline: "Top", "Shoes".
    static func pieceTitle(_ category: GarmentCategory) -> String {
        category == .shoes ? category.chipTitle : category.singularTitle
    }

    static var mayNotMatch: String {
        String(
            localized: "May not match", bundle: .module, comment: "Swap: mark on a weaker match in See all (LR-07.3)")
    }

    static var wornTogether: String {
        String(
            localized: "Worn together lately", bundle: .module,
            comment: "Swap: mark in See all on a piece that would repeat an outfit she wore recently (LR-10)")
    }

    static var inTheLook: String {
        String(localized: "In the look", bundle: .module, comment: "Swap: mark on the piece the look has now")
    }

    /// "Top now: Cute pink shirt" or "Trying Cream knit sweater".
    static func tagline(current: String, kind: GarmentCategory, previewing: String?) -> String {
        if let previewing {
            return String(
                localized: "Trying \(previewing)", bundle: .module, comment: "Swap: under the look while she tries one")
        }
        let kindTitle = pieceTitle(kind)
        return String(
            localized: "\(kindTitle) now: \(current)", bundle: .module,
            comment: "Swap: under the look, the kind of piece and the piece in it now")
    }

    // MARK: Remove

    static var remove: String {
        String(localized: "Remove this piece", bundle: .module, comment: "Swap: button (LR-08)")
    }

    /// Why Remove this piece is off.
    static func whyNoRemove(_ problem: LookProblem) -> String {
        switch problem {
        case .tooFewPieces:
            String(
                localized: "A look needs at least 2 pieces, so this one can only be swapped.", bundle: .module,
                comment: "Swap: why Remove this piece is off")
        case .needsMainPieces:
            String(
                localized: "A look needs a top and a bottom, or a dress, so this one can only be swapped.",
                bundle: .module, comment: "Swap: why Remove this piece is off")
        case .tooManyPieces, .twoOfAKind, .notUsable:
            String(
                localized: "This piece can only be swapped.", bundle: .module,
                comment: "Swap: why Remove this piece is off, in general")
        }
    }

    // MARK: Find one

    static var findOneLead: String {
        String(localized: "Not in your closet?", bundle: .module, comment: "Swap: before Find one (LR-07.4)")
    }

    // MARK: Toasts

    static func swapped(_ name: String) -> String {
        String(localized: "Swapped in \(name)", bundle: .module, comment: "Toast after a swap, with the new piece")
    }

    static func removed(_ name: String) -> String {
        String(localized: "Took out \(name)", bundle: .module, comment: "Toast after Remove this piece")
    }

    static var undone: String {
        String(localized: "Back to how it was", bundle: .module, comment: "Toast after undoing a swap or removal")
    }
}
