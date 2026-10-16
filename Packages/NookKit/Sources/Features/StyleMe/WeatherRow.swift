import DesignSystem
import Models
import SwiftUI

/// Style Me's Weather row (LR-04): "Weather · 58° and rain" with "Your looks are picked for
/// today's weather." under it. Tapping it opens a small sheet with the three choices. The
/// choice belongs to this request only, so the screen that owns it starts on Use today's weather
/// each time.
struct WeatherRow: View {
    @Binding var choice: WeatherChoice
    let reading: WeatherReading

    @State private var isChoosing = false

    private var content: WeatherRowContent { WeatherRowContent(choice: choice, reading: reading) }

    var body: some View {
        Button {
            isChoosing = true
        } label: {
            NookRow(
                String(localized: "Weather", bundle: .module, comment: "Style Me row title"),
                subtitle: content.explanation,
                // While it loads, the value says so rather than going blank.
                value: content.value ?? content.todayDetail,
                systemImage: content.systemImage,
                accessory: .chevron
            )
        }
        .buttonStyle(.nookRow)
        .accessibilityIdentifier("styleMe.weather")
        .accessibilityHint(
            Text("Choose how the weather is used.", bundle: .module, comment: "VoiceOver hint for the Weather row")
        )
        .nookSheet(
            isPresented: $isChoosing,
            title: String(localized: "Weather", bundle: .module, comment: "Weather sheet title"),
            subtitle: String(
                localized: "This choice is for this request only.", bundle: .module,
                comment: "Weather sheet: the choice doesn't stick"),
            detents: [.medium, .large]
        ) {
            WeatherChoiceList(choice: $choice, content: content) { isChoosing = false }
        }
    }
}

/// The three choices in the Weather sheet. The chosen one has a check mark and the selected
/// trait, so it isn't shown by colour alone. Picking one closes the sheet.
struct WeatherChoiceList: View {
    @Binding var choice: WeatherChoice
    let content: WeatherRowContent
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            ForEach(WeatherChoice.allCases, id: \.self) { option in
                let isSelected = option == choice
                Button {
                    choice = option
                    close()
                } label: {
                    HStack(spacing: NookSpacing.small) {
                        NookRow(option.title, subtitle: detail(for: option), systemImage: systemImage(for: option))
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.nook.accent)
                            .opacity(isSelected ? 1 : 0)
                            .padding(.trailing, NookSpacing.medium)
                            .accessibilityHidden(true)
                    }
                    .background {
                        if isSelected {
                            NookRadius.shape(NookRadius.group).fill(Color.nook.tint)
                        }
                    }
                }
                .buttonStyle(.nookRow)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(option.identifier)
            }
        }
    }

    private func detail(for option: WeatherChoice) -> String {
        switch option {
        case .useToday: content.todayDetail
        case .indoors:
            String(localized: "For a day inside, whatever it’s like out.", bundle: .module, comment: "Weather sheet")
        case .ignore:
            String(localized: "Your looks won’t use the weather.", bundle: .module, comment: "Weather sheet")
        }
    }

    private func systemImage(for option: WeatherChoice) -> String {
        WeatherRowContent(choice: option, reading: content.reading).systemImage
    }
}
