import Foundation
import Models
import Testing

@testable import Features

/// The stand-in results: the request in words, and as JSON in Debug builds (the 10a checkpoint).
@MainActor
struct StyleRequestSummaryTests {
    private let us = ClosetTestTime.locale

    private func summary(_ change: (inout StyleRequestDraft) -> Void = { _ in }) async throws -> StyleRequestSummary {
        let model = await loadedStyleMe()
        model.update(change)
        let request = try #require(model.makeRequest(id: "r-1", now: ClosetTestTime.now))
        let text = model.text(locale: us)
        return StyleRequestSummary(
            request: request, sourceName: text.sourceName, startingPieceName: model.startingPiece?.name,
            occasionValue: text.occasionValue, locale: us)
    }

    private func values(_ summary: StyleRequestSummary) -> [String: String] {
        Dictionary(uniqueKeysWithValues: summary.rows.map { ($0.identifier, $0.value) })
    }

    @Test func theDefaultsInWords() async throws {
        let summary = try await summary()
        #expect(
            summary.rows.map(\.label) == [
                "Source", "Occasion", "Starting piece", "Weather", "Comfort", "Colour", "Preferences", "New-piece idea",
            ])
        #expect(
            values(summary) == [
                "source": "Main closet", "occasion": "Office", "startingPiece": "None", "weather": "58° and rain",
                "comfort": "Usual fit", "color": "Any", "preferences": "Mine + one idea",
                "newPieceIdea": "Allowed in Something new",
            ])
    }

    @Test func everyChoiceInWords() async throws {
        let summary = try await summary { draft in
            draft.source = .suitcase("s-weekend")
            draft.startingPieceID = "g-navy-trousers"
            draft.occasion = .other
            draft.occasionNote = "Museum visit"
            draft.weatherChoice = .ignore
            draft.comfort = .relaxed
            draft.color = ColorWish(.navy, strength: .required, scope: .bottom)
        }
        #expect(
            values(summary) == [
                "source": "Weekend · Suitcase only", "occasion": "Other: Museum visit",
                "startingPiece": "Navy dress pants", "weather": "Ignored", "comfort": "Relaxed",
                "color": "Navy · bottom · required", "preferences": "Mine + one idea",
                "newPieceIdea": "Not in this request",
            ])
    }

    /// The JSON is the request itself: it decodes back to the same value, with readable keys.
    @Test func theJSONIsTheRequest() async throws {
        let summary = try await summary { draft in
            draft.comfort = .fitted
            draft.color = ColorWish(.pink, scope: .top)
        }
        let json = summary.json
        for key in [
            "\"comfort\" : \"fitted\"", "\"occasion\" : \"office\"", "\"weatherChoice\" : \"useToday\"",
            "\"pieceMode\" : \"mineAndOneIdea\"", "\"family\" : \"pink\"", "\"scope\" : \"top\"",
        ] {
            #expect(json.contains(key), "No \(key) in \(json)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StyleRequest.self, from: Data(json.utf8))
        #expect(decoded == summary.request)
    }

    /// No names go into the request itself: the suitcase and the piece are IDs only (DATA_MAP.md).
    @Test func theRequestHoldsNoNames() async throws {
        let summary = try await summary { draft in
            draft.source = .suitcase("s-jose")
            draft.startingPieceID = "g-navy-trousers"
        }
        #expect(!summary.json.contains("Jose"))
        #expect(!summary.json.contains("Navy dress pants"))
        #expect(!summary.json.contains("Lily"))
    }
}
