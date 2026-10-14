import DesignSystem
import Models
import SwiftUI

/// What the window shows: today's weather, night after dark, or a plain sky when the weather
/// isn't known (RD-01, RD-01.4).
nonisolated enum RoomWindow: String, CaseIterable, Hashable, Sendable {
    case sun
    case cloudy
    case rain
    case snow
    case night
    /// Still loading, or the weather couldn't be read. The window doesn't guess.
    case plain

    /// Night wins over the condition, as in the mockups: after dark it's the night window
    /// whatever the weather.
    init(weather: WeatherSnapshot?) {
        guard let weather else {
            self = .plain
            return
        }
        if weather.isNight {
            self = .night
            return
        }
        switch weather.condition {
        case .sun: self = .sun
        case .cloudy: self = .cloudy
        case .rain: self = .rain
        case .snow: self = .snow
        }
    }

    var art: RoomArt {
        switch self {
        case .sun: .windowSun
        case .cloudy: .windowCloudy
        case .rain: .windowRain
        case .snow: .windowSnow
        case .night: .windowNight
        case .plain: .windowPlain
        }
    }

    /// The desk lamp glows at night (`.glow` in `home.html`).
    var lightsTheLamp: Bool { self == .night }

    /// What VoiceOver says for the window, so the weather in the room isn't only visual. `nil`
    /// for the plain window, which has nothing to say.
    var accessibilityLabel: String? {
        switch self {
        case .sun: String(localized: "Window: Sunny", bundle: .module, comment: "VoiceOver label for the window")
        case .cloudy: String(localized: "Window: Cloudy", bundle: .module, comment: "VoiceOver label for the window")
        case .rain: String(localized: "Window: Rain", bundle: .module, comment: "VoiceOver label for the window")
        case .snow: String(localized: "Window: Snow", bundle: .module, comment: "VoiceOver label for the window")
        case .night:
            String(
                localized: "Window: Night", bundle: .module,
                comment: "VoiceOver label for the window when it's dark outside")
        case .plain: nil
        }
    }
}

/// The desk lamp's warm pool of light: on at night, and always on in dark appearance, where the
/// room is at night anyway (`.glow` and `dark.css` in the mockups). Decorative.
struct LampGlow: View {
    let isNight: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var strength: Double? {
        if colorScheme == .dark { return 0.32 }
        return isNight ? 0.55 : nil
    }

    var body: some View {
        if let strength {
            let light = Color(red: 1, green: 228 / 255, blue: 150 / 255)
            RadialGradient(
                colors: [light.opacity(strength), light.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: 60
            )
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
