import Foundation
import Models

/// The words on Fit and measurements and its sheets (Phase 14a, `fit.html`, PRD §10.1, LR-13,
/// LR-18).
nonisolated enum FitText {
    static var title: String { ProfileText.fitRow }

    static var lede: String {
        String(
            localized: "Everything here is optional. It stays private, on this iPhone.", bundle: .module,
            comment: "Fit and measurements: under the title")
    }

    // MARK: Usual fit (LR-18)

    static var usualFit: String {
        String(localized: "Usual fit", bundle: .module, comment: "Fit and measurements section")
    }

    static var usualFitNote: String {
        String(
            localized: "How you like clothes to sit. Saved until you change it.", bundle: .module,
            comment: "Under the usual fit choices (LR-18)")
    }

    static var usualFitComfortNote: String {
        String(
            localized: "For one outfit only, pick a Comfort on Style Me.", bundle: .module,
            comment: "Under the usual fit choices: where today-only comfort lives (LR-18)")
    }

    // MARK: Measurements

    static var measurements: String {
        String(localized: "Measurements", bundle: .module, comment: "Fit and measurements section")
    }

    static var units: String {
        String(localized: "Units", bundle: .module, comment: "VoiceOver name of the units switch")
    }

    static func unitsTitle(_ units: MeasurementUnits) -> String {
        switch units {
        case .imperial: String(localized: "in · lb", bundle: .module, comment: "Units choice: inches and pounds")
        case .metric: String(localized: "cm · kg", bundle: .module, comment: "Units choice: centimetres and kilograms")
        }
    }

    static func spokenUnits(_ units: MeasurementUnits) -> String {
        switch units {
        case .imperial:
            String(localized: "Inches and pounds", bundle: .module, comment: "VoiceOver: units choice")
        case .metric:
            String(localized: "Centimetres and kilograms", bundle: .module, comment: "VoiceOver: units choice")
        }
    }

    static func name(_ field: MeasurementField) -> String {
        switch field {
        case .height: String(localized: "Height", bundle: .module, comment: "Measurement")
        case .waist: String(localized: "Waist", bundle: .module, comment: "Measurement")
        case .hips: String(localized: "Hip / seat", bundle: .module, comment: "Measurement")
        case .bust: String(localized: "Bust", bundle: .module, comment: "Measurement")
        case .inseam: String(localized: "Inseam", bundle: .module, comment: "Measurement")
        case .weight: String(localized: "Weight", bundle: .module, comment: "Measurement")
        }
    }

    /// How to measure it, in the sheet (`fit.html`'s measurement help).
    static func help(_ field: MeasurementField) -> String {
        switch field {
        case .height:
            String(localized: "Measured standing, without shoes.", bundle: .module, comment: "Measurement help")
        case .waist:
            String(
                localized: "Measured on your body, at your natural waist.", bundle: .module,
                comment: "Measurement help")
        case .hips:
            String(
                localized: "Measured on your body, at the fullest part.", bundle: .module, comment: "Measurement help")
        case .bust:
            String(
                localized: "Measured on your body, at the fullest part.", bundle: .module, comment: "Measurement help")
        case .inseam:
            String(
                localized: "The inside leg length you like, from a pair of trousers that fits.", bundle: .module,
                comment: "Measurement help")
        case .weight:
            String(
                localized: "An approximate number is fine. It never decides a size on its own.", bundle: .module,
                comment: "Measurement help for weight (PRD §10)")
        }
    }

    static var leaveEmpty: String {
        String(
            localized: "Leave it empty if you don’t know.", bundle: .module,
            comment: "Measurement sheet, after the help")
    }

    static var notAdded: String {
        String(localized: "Not added", bundle: .module, comment: "A measurement with no value")
    }

    static var weightState: String {
        String(localized: "Optional · approximate is fine", bundle: .module, comment: "Under the Weight row")
    }

    static func add(_ name: String) -> String {
        String(localized: "Add \(name)", bundle: .module, comment: "VoiceOver: button that adds a measurement")
    }

    static func edit(_ name: String) -> String {
        String(localized: "Edit \(name)", bundle: .module, comment: "VoiceOver: button that edits a measurement")
    }

    static var addButton: String {
        String(localized: "Add", bundle: .module, comment: "Button on a measurement row with no value")
    }

    static var editButton: String {
        String(localized: "Edit", bundle: .module, comment: "Button on a measurement row with a value")
    }

    static var clear: String {
        String(localized: "Clear", bundle: .module, comment: "Button: empties a measurement")
    }

    static var feet: String {
        String(localized: "Feet", bundle: .module, comment: "Height field: the feet part")
    }

    static var inches: String {
        String(localized: "Inches", bundle: .module, comment: "Height field: the inches part")
    }

    /// The unit after a box: "in", "cm", "lb", "kg", "ft".
    static func unitSymbol(_ field: MeasurementField, _ units: MeasurementUnits) -> String {
        switch (field, units) {
        case (.weight, .imperial): String(localized: "lb", bundle: .module, comment: "Unit after a box: pounds")
        case (.weight, .metric): String(localized: "kg", bundle: .module, comment: "Unit after a box: kilograms")
        case (_, .imperial): String(localized: "in", bundle: .module, comment: "Unit after a box: inches")
        case (_, .metric): String(localized: "cm", bundle: .module, comment: "Unit after a box: centimetres")
        }
    }

    static var feetSymbol: String {
        String(localized: "ft", bundle: .module, comment: "Unit after a box: feet")
    }

    /// The box's name for VoiceOver: "Waist in inches".
    static func spokenBox(_ field: MeasurementField, _ units: MeasurementUnits) -> String {
        let name = name(field)
        return switch (field, units) {
        case (.weight, .imperial):
            String(localized: "\(name) in pounds", bundle: .module, comment: "VoiceOver: a measurement box")
        case (.weight, .metric):
            String(localized: "\(name) in kilograms", bundle: .module, comment: "VoiceOver: a measurement box")
        case (_, .imperial):
            String(localized: "\(name) in inches", bundle: .module, comment: "VoiceOver: a measurement box")
        case (_, .metric):
            String(localized: "\(name) in centimetres", bundle: .module, comment: "VoiceOver: a measurement box")
        }
    }

    /// What's wrong with what she typed, with the range in her units.
    static func problem(_ problem: EntryProblem, field: MeasurementField, units: MeasurementUnits) -> String {
        let range = MeasurementEntry.shownRange(for: field, in: units)
        let low = range.lowerBound
        let high = range.upperBound
        switch problem {
        case .inchesPart:
            return String(
                localized: "Inches go from 0 to 11. Put whole feet in the first box.", bundle: .module,
                comment: "Height: the inches part is 12 or more")
        case .notANumber, .outOfRange:
            if field == .height, units == .imperial {
                return String(
                    localized: "Enter a height between 3 and 8 feet, or leave both boxes empty.", bundle: .module,
                    comment: "Height in feet and inches isn't a number or is out of range")
            }
            return switch (field, units) {
            case (.weight, .imperial):
                String(
                    localized: "Enter a number of pounds between \(low) and \(high), or leave it empty.",
                    bundle: .module, comment: "Weight isn't a number or is out of range")
            case (.weight, .metric):
                String(
                    localized: "Enter a number of kilograms between \(low) and \(high), or leave it empty.",
                    bundle: .module, comment: "Weight isn't a number or is out of range")
            case (_, .imperial):
                String(
                    localized: "Enter a number of inches between \(low) and \(high), or leave it empty.",
                    bundle: .module, comment: "A measurement isn't a number or is out of range")
            case (_, .metric):
                String(
                    localized: "Enter a number of centimetres between \(low) and \(high), or leave it empty.",
                    bundle: .module, comment: "A measurement isn't a number or is out of range")
            }
        }
    }

    static func saved(_ name: String) -> String {
        String(localized: "\(name) saved on this iPhone.", bundle: .module, comment: "Toast after saving a measurement")
    }

    static func cleared(_ name: String) -> String {
        String(
            localized: "\(name) cleared. Nothing is guessed in its place.", bundle: .module,
            comment: "Toast after clearing a measurement (PRD §10.2)")
    }

    static var privacy: String {
        String(
            localized:
                "Private. Saved only on this iPhone, and nothing here is sent anywhere in this test build. Changing it never restyles a saved look.",
            bundle: .module, comment: "Fit and measurements: the privacy line at the bottom")
    }

    // MARK: Pieces that fit you well (LR-13)

    static var piecesSection: String {
        String(localized: "Pieces that fit you well", bundle: .module, comment: "Fit and measurements section (LR-13)")
    }

    static var addPiece: String {
        String(
            localized: "Add a piece that fits you well", bundle: .module, comment: "Button and sheet title (LR-13)")
    }

    static var addPieceLine: String {
        String(
            localized:
                "Pick something you own that fits just right. We’ll use its brand and size to suggest sizes for you.",
            bundle: .module, comment: "Under the pieces that fit section header (LR-13)")
    }

    static var addPieceExample: String {
        String(
            localized: "For example: your favourite jeans or a blazer that fits perfectly.", bundle: .module,
            comment: "Shown only while she has no fitting pieces (LR-13.3)")
    }

    static var piecesUse: String {
        String(
            localized: "Used for fit checks when you’re thinking of buying.", bundle: .module,
            comment: "Under her fitting pieces (LR-13, LR-12)")
    }

    static var brand: String {
        String(localized: "Brand", bundle: .module, comment: "Field label")
    }

    static var brandPrompt: String {
        String(localized: "Old Navy, Zara…", bundle: .module, comment: "Brand field prompt on the fitting piece sheet")
    }

    static var kind: String {
        String(localized: "Kind", bundle: .module, comment: "Field label: the kind of piece")
    }

    static var size: String {
        String(localized: "Size as printed", bundle: .module, comment: "Field label on the fitting piece sheet")
    }

    static var sizePrompt: String {
        String(localized: "0 Petite, S, 26…", bundle: .module, comment: "Size field prompt on the fitting piece sheet")
    }

    static var howItFits: String {
        String(localized: "How it fits", bundle: .module, comment: "Field label on the fitting piece sheet")
    }

    static func remove(_ name: String) -> String {
        String(localized: "Remove \(name)", bundle: .module, comment: "VoiceOver: removes a fitting piece")
    }

    static func removed(_ name: String) -> String {
        String(localized: "Removed \(name).", bundle: .module, comment: "Toast after removing a fitting piece")
    }

    static func added(_ name: String) -> String {
        String(localized: "Added \(name).", bundle: .module, comment: "Toast after adding a fitting piece")
    }

    static var undo: String {
        String(localized: "Undo", bundle: .module, comment: "Toast button")
    }

    static var brandMissing: String {
        String(localized: "Add the brand.", bundle: .module, comment: "Fitting piece sheet: brand is empty")
    }

    static var sizeMissing: String {
        String(localized: "Add the size as printed.", bundle: .module, comment: "Fitting piece sheet: size is empty")
    }

    static func tooLong(_ maximum: Int) -> String {
        String(
            localized: "Use \(maximum) characters or fewer.", bundle: .module,
            comment: "Make your own look: the name is too long")
    }

    // MARK: States

    static var loading: String {
        String(localized: "Opening your profile", bundle: .module, comment: "Profile loading")
    }

    static var failedTitle: String {
        String(localized: "Your profile didn’t load", bundle: .module, comment: "Profile error title")
    }

    static var failedMessage: String {
        String(
            localized: "Nothing was lost. Try again in a moment.", bundle: .module, comment: "Closet error message")
    }

    static var hidden: String {
        String(
            localized: "Hidden while the app is in the background", bundle: .module,
            comment: "Cover over sensitive screens in the app switcher")
    }
}

nonisolated extension FitResult {
    /// "Fits well", "Too long" (PRD §10.1).
    nonisolated var title: String {
        switch self {
        case .fitsWell: String(localized: "Fits well", bundle: .module, comment: "How a piece fits")
        case .tooLong: String(localized: "Too long", bundle: .module, comment: "How a piece fits")
        case .tooShort: String(localized: "Too short", bundle: .module, comment: "How a piece fits")
        case .tooTight: String(localized: "Too tight", bundle: .module, comment: "How a piece fits")
        case .tooLoose: String(localized: "Too loose", bundle: .module, comment: "How a piece fits")
        }
    }
}
