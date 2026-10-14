import DesignSystem
import Models
import SwiftUI

/// Style Me until Phase 10a builds the whole request screen (RD-02). It has the one row that
/// exists already, Weather (LR-04), above the usual "still being built" note. Nothing here
/// sends a request.
struct StyleMeStubScreen: View {
    @Environment(\.services) private var services
    /// For this request only: a new Style Me starts on Use today's weather (LR-04.2).
    @State private var weatherChoice: WeatherChoice = .useToday
    @State private var reading: WeatherReading = .loading

    var body: some View {
        ScrollView {
            VStack(spacing: NookSpacing.groupGap) {
                WeatherRow(choice: $weatherChoice, reading: reading)
                NookEmptyState(
                    String(localized: "Style Me", bundle: .module, comment: "Screen title"),
                    message: String(
                        localized: "The rest of Style Me is still being built.", bundle: .module,
                        comment: "Shown on Style Me under the rows that exist so far"),
                    systemImage: "sparkles"
                )
            }
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.vertical, NookSpacing.xxLarge)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
        .navigationTitle(HomeDestination.styleMe(choosingOccasion: false).title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("stub.styleMe")
        .task { await loadWeather() }
    }

    private func loadWeather() async {
        guard let services else {
            reading = .unavailable
            return
        }
        do {
            reading = .loaded(try await services.weather.currentWeather())
        } catch {
            reading = .unavailable
        }
    }
}

#Preview {
    NavigationStack {
        StyleMeStubScreen()
    }
}
