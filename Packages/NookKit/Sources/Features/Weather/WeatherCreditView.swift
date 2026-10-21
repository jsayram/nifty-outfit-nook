import DesignSystem
import Models
import SwiftUI

/// Apple Weather's credit: its mark and a link to the legal page for the data sources. Apple
/// requires it wherever WeatherKit data shows (PRD 11.5, closet `compliance/PERMISSIONS.md`):
/// Home's window, Style Me's Weather row, and the weather settings.
///
/// The mark comes from the URLs WeatherKit gives (light and dark versions). While it loads, or
/// when there are none, the words "Apple Weather" stand in, so the credit never goes missing.
struct WeatherCreditView: View {
    let credit: WeatherCredit

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        HStack(spacing: NookSpacing.xSmall) {
            mark
                .accessibilityHidden(true)
            Link(destination: credit.legalURL) {
                Text("Data sources", bundle: .module, comment: "Link under the weather to Apple Weather's legal page")
                    .nookTextStyle(.caption)
                    .underline()
                    .foregroundStyle(.nook.textSecondary)
                    .frame(minHeight: NookSpacing.minimumTapTarget)
            }
            .accessibilityLabel(
                Text(
                    "\(credit.serviceName) data sources", bundle: .module,
                    comment: "VoiceOver label for the weather credit link, with the service's name")
            )
            .accessibilityHint(
                Text(
                    "Opens Apple's page about the weather data.", bundle: .module,
                    comment: "VoiceOver hint for the weather credit link"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weather.credit")
    }

    @ViewBuilder private var mark: some View {
        let url = colorScheme == .dark ? credit.markDarkURL : credit.markLightURL
        if let url, !isStillImage {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                nameMark
            }
            .frame(height: 14)
        } else {
            nameMark
        }
    }

    private var nameMark: some View {
        Text(verbatim: credit.serviceName)
            .nookTextStyle(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.nook.textSecondary)
    }
}
