import DesignSystem
import Foundation
import Models
import SwiftUI

/// A request she has just sent, in words: what the stand-in results screen shows until Phase 10b
/// builds Your looks. Names come from the screen that made it, since the request itself holds
/// only IDs (it never carries a suitcase's name, DATA_MAP.md).
struct StyleRequestSummary: Hashable, Identifiable {
    let request: StyleRequest
    let sourceName: String
    let startingPieceName: String?
    let occasionValue: String
    var locale: Locale = .current

    var id: StyleRequest.ID { request.id }

    struct Row: Hashable {
        let label: String
        let value: String
        let identifier: String
    }

    /// Every choice in the request, one row each, in the order of the Style Me screen.
    var rows: [Row] {
        let weather = WeatherRowContent(
            choice: request.weatherChoice,
            reading: request.weather.map(WeatherReading.loaded) ?? .unavailable,
            locale: locale)
        let colorValue = StyleMeText.colorValue(request.color, locale: locale)
        return [
            Row(
                label: String(localized: "Source", bundle: .module, comment: "Style Me row caption"),
                value: request.source.isSuitcase ? "\(sourceName) · \(StyleMeText.suitcaseOnly)" : sourceName,
                identifier: "source"),
            Row(
                label: String(localized: "Occasion", bundle: .module, comment: "Style Me row caption"),
                value: occasionValue, identifier: "occasion"),
            Row(
                label: String(localized: "Starting piece", bundle: .module, comment: "Style Me row caption"),
                value: startingPieceName
                    ?? String(localized: "None", bundle: .module, comment: "Style Me: no starting piece"),
                identifier: "startingPiece"),
            Row(
                label: String(localized: "Weather", bundle: .module, comment: "Style Me row title"),
                value: weather.value ?? weather.todayDetail, identifier: "weather"),
            Row(
                label: String(localized: "Comfort", bundle: .module, comment: "Style Me row"),
                value: request.comfort?.title
                    ?? String(
                        localized: "Usual fit", bundle: .module, comment: "Style Me Comfort: her usual fit from Profile"
                    ),
                identifier: "comfort"),
            Row(
                label: String(localized: "Colour", bundle: .module, comment: "Style Me row"),
                value: colorValue, identifier: "color"),
            Row(
                label: String(localized: "Preferences", bundle: .module, comment: "Style Me row (LR-03)"),
                value: request.preferences.pieceMode.title, identifier: "preferences"),
            Row(
                label: String(localized: "New-piece idea", bundle: .module, comment: "Request summary row (LR-05b)"),
                value: request.allowsNewPieceIdea
                    ? String(
                        localized: "Allowed in Something new", bundle: .module,
                        comment: "Request summary: an unowned piece may appear")
                    : String(
                        localized: "Not in this request", bundle: .module,
                        comment: "Request summary: no unowned piece"),
                identifier: "newPieceIdea"),
        ]
    }

    /// The request as the app would hand it on, for checking by eye. Shown on screen in Debug
    /// builds only, and never logged: it can hold today's comfort (Sensitive).
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(request) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The stand-in for Your looks (Phase 10b): the request that Style me produced, in words, so a
/// run can be checked. Debug builds add the request as JSON.
struct StyleRequestSummaryScreen: View {
    let summary: StyleRequestSummary

    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        Group {
            if isStillImage {
                content
            } else {
                ScrollView { content }
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
        .navigationTitle(Text("Your looks", bundle: .module, comment: "Screen title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: NookSpacing.groupGap) {
            NookBanner(
                String(
                    localized: "Your request is ready. Your looks come in the next build.", bundle: .module,
                    comment: "Stand-in results screen until Phase 10b"),
                systemImage: "sparkles", tone: .neutral
            )
            .accessibilityIdentifier("styleMe.results")
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                NookSectionHeader(String(localized: "Your request", bundle: .module, comment: "Style Me section"))
                ForEach(summary.rows, id: \.self) { row in
                    NookRow(row.label, value: row.value)
                        .accessibilityIdentifier("summary.\(row.identifier)")
                }
            }
            #if DEBUG
                requestPreview
            #endif
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.vertical, NookSpacing.large)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    #if DEBUG
        /// The request as JSON, for checking what gets produced (the 10a checkpoint). Debug only.
        private var requestPreview: some View {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                NookSectionHeader(
                    String(localized: "Request preview", bundle: .module, comment: "Debug section on the stand-in"),
                    detail: String(localized: "Debug builds only", bundle: .module, comment: "Debug section detail"))
                Text(verbatim: summary.json)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.nook.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nookCard(.strong, padding: NookSpacing.medium)
                    .accessibilityIdentifier("styleMe.requestJSON")
            }
        }
    #endif
}
