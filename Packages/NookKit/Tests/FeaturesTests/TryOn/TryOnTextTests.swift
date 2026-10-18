import Foundation
import Models
import Testing

@testable import Features

/// The words for the two kinds of try-on picture (real-photo audit, 17 October 2026): a picture
/// of the person in her try-on photo wearing the look, and one drawn from the pieces alone. Each
/// says what it shows, never "no person" over a picture of a woman, and both stay Simulated.
@MainActor
struct TryOnTextTests {
    private let pieces = [
        LookBundlePiece(id: "1", name: "Black tee", category: .top, colors: [.black]),
        LookBundlePiece(id: "2", name: "Wide-leg jeans", category: .bottom, colors: [.denim]),
    ]

    private func content(photo: PhotoReference?) -> LookBundleContent {
        var content = LookBundleContent(id: "o-casual", pieces: pieces)
        content.tryOnPhoto = photo
        return content
    }

    private let english = Locale(identifier: "en_US")

    @Test func aPictureOfAPersonSaysWhoIsInIt() {
        let spoken = TryOnText.spokenPicture(
            of: content(photo: .sample("wardrobe:tryon:casual")), lookName: "Casual", locale: english)
        #expect(
            spoken
                == "Simulated try-on picture of Casual: the person in your try-on photo wearing Black tee and Wide-leg jeans."
        )
        let note = TryOnText.aboutSimulated(showsPerson: true)
        #expect(note.contains("the person in your try-on photo"))
        #expect(note.hasPrefix("This picture is simulated"))
    }

    @Test func aDrawnPictureSaysNoOneIsInIt() {
        let spoken = TryOnText.spokenPicture(of: content(photo: nil), lookName: "Casual", locale: english)
        #expect(
            spoken
                == "Simulated try-on picture of Casual: Black tee, Wide-leg jeans. The pieces only, with no one wearing them."
        )
        let note = TryOnText.aboutSimulated(showsPerson: false)
        #expect(note.contains("pieces alone"))
        #expect(!note.contains("person"))
    }

    /// Every try-on line covers both kinds, keeps "simulated" where it describes the picture, and
    /// none promises a picture with no one in it.
    @Test func theSheetTourAndHelpCoverBothKinds() throws {
        let tour = try #require(TryOnTour.definition.steps.first?.message)
        let help = try #require(HelpContent.topics.first { $0.id == "swap" }?.note)
        for line in [TryOnSheetText.simulatedHere, tour, help] {
            #expect(line.localizedCaseInsensitiveContains("the person in your try-on photo"), "\(line)")
            #expect(line.contains("pieces on their own"), "\(line)")
            #expect(!line.localizedCaseInsensitiveContains("no person"), "\(line)")
        }
        #expect(TryOnSheetText.simulatedHere.contains("simulated"))
        #expect(tour.contains("the style, not the exact fit"))
        for note in [true, false].map(TryOnText.aboutSimulated(showsPerson:)) {
            #expect(note.contains("Pictures show the style, not the exact fit."))
        }
    }
}
