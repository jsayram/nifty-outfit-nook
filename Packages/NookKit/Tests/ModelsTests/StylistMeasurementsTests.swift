import Foundation
import Models
import Testing

/// D10 (F1c): her measurements and weight go to the cloud stylist in whole centimetres and
/// kilograms, only under a consent that names them (`stylist-2`), never under `stylist-1`.
struct StylistMeasurementsTests {
    static let now = Date(timeIntervalSince1970: 1_792_000_000)

    static let profile = BodyMeasurements(
        height: Length(63, .inches), waist: Length(71.2, .centimeters), bust: Length(34.5, .inches),
        hips: Length(97, .centimeters), inseam: Length(29.1, .inches), weight: Weight(128, .pounds))

    static func context(_ measurements: StyleCall.Measurements?) -> StylingContext {
        let date = now
        let pieces = [
            Garment(id: .init("g-top"), name: "Top", category: .top, colors: [.cream], addedAt: date),
            Garment(id: .init("g-bottom"), name: "Trousers", category: .bottom, colors: [.olive], addedAt: date),
            Garment(id: .init("g-shoes"), name: "Loafers", category: .shoes, colors: [.brown], addedAt: date),
        ]
        return StylingContext(
            request: StyleRequest(id: "req-1", occasion: .office, createdAt: date), eligibleGarments: pieces, now: date,
            calendar: Calendar(identifier: .gregorian), measurements: measurements)
    }

    @Test func herValuesAreRoundedToWholeCentimetresAndKilograms() throws {
        let m = try #require(StyleCall.Measurements(Self.profile))
        // 63 in = 160.02 cm, 34.5 in = 87.63 cm, 29.1 in = 73.914 cm, 128 lb = 58.06 kg.
        let expected = StyleCall.Measurements(
            heightCm: 160, bustCm: 88, waistCm: 71, hipsCm: 97, inseamCm: 74, weightKg: 58)
        #expect(m == expected)
    }

    @Test func nothingFilledInIsNone() {
        #expect(StyleCall.Measurements(BodyMeasurements()) == nil)
    }

    @Test func theAppsOwnLimitsRoundIntoTheContractsRanges() throws {
        // Measurement entry accepts 36 to 96 in of height and 50 to 700 lb: both ends still fit.
        let low = try #require(
            StyleCall.Measurements(
                BodyMeasurements(
                    height: Length(36, .inches), waist: Length(15, .inches), bust: Length(20, .inches),
                    hips: Length(20, .inches), inseam: Length(15, .inches), weight: Weight(50, .pounds))))
        let lowest = StyleCall.Measurements(
            heightCm: 91, bustCm: 51, waistCm: 38, hipsCm: 51, inseamCm: 38, weightKg: 23)
        #expect(low == lowest)
        let high = try #require(
            StyleCall.Measurements(
                BodyMeasurements(
                    height: Length(96, .inches), waist: Length(70, .inches), bust: Length(70, .inches),
                    hips: Length(80, .inches), inseam: Length(45, .inches), weight: Weight(700, .pounds))))
        let highest = StyleCall.Measurements(
            heightCm: 244, bustCm: 178, waistCm: 178, hipsCm: 203, inseamCm: 114, weightKg: 318)
        #expect(high == highest)
    }

    @Test func aValueOutsideTheContractIsLeftOutNotSent() throws {
        let m = try #require(
            StyleCall.Measurements(
                BodyMeasurements(
                    height: Length(500, .centimeters), waist: Length(.nan, .inches),
                    weight: Weight(60, .kilograms))))
        #expect(m == StyleCall.Measurements(weightKg: 60))
    }

    @Test func underStylist2TheOutfitRequestCarriesThem() throws {
        let measurements = StyleCall.Measurements(Self.profile)
        let call = StyleCall.outfit(from: Self.context(measurements), consentVersion: "stylist-2")
        #expect(call.measurements == measurements)
        #expect(call.measurements != nil)
    }

    @Test func underStylist1TheyNeverGo() {
        let measurements = StyleCall.Measurements(Self.profile)
        #expect(StyleCall.outfit(from: Self.context(measurements), consentVersion: "stylist-1").measurements == nil)
        #expect(StyleCall.outfit(from: Self.context(measurements), consentVersion: "stylist-0").measurements == nil)
        // Not even when the version is changed after the call was built.
        var call = StyleCall.outfit(from: Self.context(measurements), consentVersion: "stylist-2")
        call.consentVersion = "stylist-1"
        #expect(call.measurements == nil)
    }

    @Test func anAskStylistQuestionCarriesThemUnderStylist2Only() {
        let context = Self.context(nil)
        let look = Look(
            id: "look-1", version: .simple,
            pieces: context.eligibleGarments.map { LookPiece(id: .random(), content: .garment($0.id)) },
            occasion: .office, createdAt: Self.now)
        let measurements = StyleCall.Measurements(Self.profile)
        func request(_ consent: String) -> AskStylistRequest {
            AskStylistRequest(
                thread: .random(), turn: .random(), text: "Is this OK?", look: look, pieces: context.eligibleGarments,
                earlier: [], consentVersion: consent, measurements: measurements)
        }
        #expect(request("stylist-2").call.measurements == measurements)
        #expect(request("stylist-1").call.measurements == nil)
    }

    @Test func aJobKeptFromBeforeTheFieldStillDecodes() throws {
        // A context saved by an earlier build has no measurements key: it decodes with none.
        let saved = try JSONEncoder().encode(Self.context(nil))
        var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object.removeValue(forKey: "measurements")
        let decoded = try JSONDecoder().decode(
            StylingContext.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.measurements == nil)
    }
}
