import Foundation
import Models
import NookTestSupport
import Testing

@testable import Networking

/// The cloud stylist (Phase 27a) end to end on the phone's side: `CloudStylist`, the real client
/// with the App Attest stand-in, and the fake backend's stylist. Looks use only her own pieces and
/// carry a why line; a repeat request comes back from the result cache without another job; no
/// consent means nothing is sent; a failing provider is a calm "didn't finish".
@Suite("Cloud stylist")
struct CloudStylistTests {
    let backend = FakeBackend()
    let auth = FakeAuthProvider(subject: "lily")
    let policy = RetryPolicy(requestTimeout: .seconds(60))
    /// The client's clock, which a wait between retries jumps ahead on instead of really waiting,
    /// so these tests neither take real seconds nor have a timeout that a slow machine could hit.
    let clock = ManualClock()
    static let now = Date(timeIntervalSince1970: 1_792_000_000)

    func paid() async throws -> GatewayPaidActionService {
        let clock = clock
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy, clock: clock, sleep: { try await clock.skip($0) })
        try await auth.signInWithApple()
        _ = try await GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0").whoAmI()
        let session = AttestationSession(attester: FakeDeviceAttester(), store: MemoryAttestKeyStore(), client: client)
        return GatewayPaidActionService(client: client, attestation: session)
    }

    static func garment(
        _ id: String, _ category: GarmentCategory, _ colors: [ColorName], dressiness: Dressiness = .smart,
        name: String
    ) -> Garment {
        Garment(
            id: .init(id), name: name, category: category, colors: colors, dressiness: dressiness,
            brand: "Secret Brand", sizeLabel: "XS", notes: "a private note", addedAt: now)
    }

    static let closet = [
        garment("g-blouse", .top, [.cream], name: "Cream blouse"),
        garment("g-tee", .top, [.white], dressiness: .casual, name: "White tee"),
        garment("g-silk", .top, [.burgundy], dressiness: .dressy, name: "Silk top"),
        garment("g-trousers", .bottom, [.olive], name: "Olive trousers"),
        garment("g-jeans", .bottom, [.denim], dressiness: .casual, name: "Dark jeans"),
        garment("g-blazer", .layer, [.navy], dressiness: .dressy, name: "Navy blazer"),
        garment("g-loafers", .shoes, [.brown], name: "Brown loafers"),
        garment("g-flats", .shoes, [.black], name: "Black flats"),
    ]

    static func context(comfort: Comfort? = nil) -> StylingContext {
        let request = StyleRequest(
            id: "req-1", occasion: .office,
            weather: WeatherSnapshot(
                condition: .rain, temperatureCelsius: 13.6, observedAt: now, lowCelsius: 11.2, highCelsius: 16.4,
                precipitationChance: 0.68),
            comfort: comfort, createdAt: now)
        return StylingContext(
            request: request, eligibleGarments: closet, now: now, calendar: Calendar(identifier: .gregorian))
    }

    func stylist(_ paid: GatewayPaidActionService, consent: StylistConsent? = StylistConsent(agreedAt: now))
        -> CloudStylist
    {
        CloudStylist(paid: paid, consent: InMemoryStylistConsentStore(consent))
    }

    @Test func looksUseOnlyHerPiecesAndCarryAWhyLine() async throws {
        let outcome = try await stylist(paid()).style(Self.context())
        guard case .complete(let result) = outcome else {
            Issue.record("Expected three versions, got \(outcome)")
            return
        }
        #expect(result.versions.map(\.version) == [.simple, .dressedUp, .somethingNew])
        let hers = Set(Self.closet.map(\.id))
        for look in result.versions {
            #expect(look.garmentIDs.allSatisfy(hers.contains))
            #expect((look.why ?? "").count > 10)
            #expect(look.intent == StyleIntent(Self.context().request))
        }
        #expect(ResultCheck.problems(in: result, for: Self.context()).isEmpty)
        #expect(backend.paidJobsRun == 1)
    }

    @Test func aRepeatRequestComesFromTheResultCacheWithoutAnotherJob() async throws {
        let service = try await paid()
        let stylist = stylist(service)
        _ = try await stylist.style(Self.context())
        let again = try await stylist.style(Self.context())
        #expect(backend.paidJobsRun == 1)
        #expect(again.result?.notes.contains(.answeredAgain) == true)
        let usage = try await service.usage()
        #expect(usage.allowance(.styleFull)?.usedToday == 1)
        // Another choice is another request.
        _ = try await stylist.style(Self.context(comfort: .fitted))
        #expect(backend.paidJobsRun == 2)
    }

    @Test func withoutConsentNothingIsSent() async throws {
        let service = try await paid()
        let before = backend.requestCount
        await #expect(throws: StylistError.needsConsent) {
            try await stylist(service, consent: nil).style(Self.context())
        }
        // Consent to older words doesn't count either.
        await #expect(throws: StylistError.needsConsent) {
            try await stylist(service, consent: StylistConsent(version: "stylist-0", agreedAt: Self.now))
                .style(Self.context())
        }
        #expect(backend.requestCount == before)
    }

    @Test func theServerRefusesConsentThatDoesNotCoverItsProvider() async throws {
        let service = try await paid()
        var call = StyleCall.outfit(from: Self.context(), consentVersion: "stylist-0")
        call.consentVersion = "stylist-0"
        await #expect(throws: CloudLimitProblem.needsConsent) {
            try await service.run(.style(call), idempotencyKey: IdempotencyKey.make())
        }
        #expect(backend.paidJobsRun == 0)
    }

    @Test func aFailingProviderIsACalmDidNotFinish() async throws {
        let service = try await paid()
        backend.setStylist(.fails)
        await #expect(throws: StylistError.notCompleted) {
            try await stylist(service).style(Self.context())
        }
        let usage = try await service.usage()
        #expect(usage.allowance(.styleFull)?.usedToday == 0)
    }

    @Test func onlyPlainDescriptorsAndTheWeatherSummaryLeaveThePhone() throws {
        let call = StyleCall.outfit(from: Self.context(), consentVersion: StylistConsent.currentVersion)
        let data = try APIV1.encoder().encode(APIV1.StyleRequest(call))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pieces = try #require(object["closet"] as? [[String: Any]])
        for piece in pieces {
            #expect(
                Set(piece.keys).isSubset(of: [
                    "id", "category", "kind", "colors", "colorNote", "fit", "dressiness", "warmth", "name",
                    "otherNames",
                ]))
        }
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["Secret Brand", "private note", "\"XS\""] { #expect(!text.contains(secret)) }
        let outfit = try #require(object["outfit"] as? [String: Any])
        let weather = try #require(outfit["weather"] as? [String: Any])
        #expect(
            Set(weather.keys) == [
                "condition", "temperatureCelsius", "lowCelsius", "highCelsius", "precipitationPercent", "isNight",
            ])
        #expect(weather["temperatureCelsius"] as? Int == 14)
        #expect(weather["precipitationPercent"] as? Int == 70)
    }

    // MARK: D10, F1c: measurements and weight under stylist-2

    static let measurements = StyleCall.Measurements(heightCm: 160, waistCm: 71, hipsCm: 97, inseamCm: 74, weightKg: 58)

    static func measuredContext() -> StylingContext {
        var context = context()
        context.measurements = measurements
        return context
    }

    @Test func underStylist2HerMeasurementsReachTheStylistAndNothingElseOfHerBody() async throws {
        let outcome = try await stylist(paid()).style(Self.measuredContext())
        #expect(outcome.result != nil)
        let sent = try #require(backend.styleRequests.last)
        #expect(sent.consentVersion == "stylist-2")
        #expect(
            sent.measurements
                == APIV1.StylistMeasurements(
                    StyleCall.Measurements(heightCm: 160, waistCm: 71, hipsCm: 97, inseamCm: 74, weightKg: 58)))
        // In the body: whole numbers under the contract's keys, and no field that could hold a
        // photo or a face anywhere.
        let data = try APIV1.encoder().encode(sent)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let numbers = try #require(object["measurements"] as? [String: Any])
        #expect(Set(numbers.keys) == ["heightCm", "waistCm", "hipsCm", "inseamCm", "weightKg"])
        #expect(numbers.values.allSatisfy { $0 is Int })
        func keys(_ value: Any) -> [String] {
            if let dictionary = value as? [String: Any] {
                return dictionary.keys + dictionary.values.flatMap(keys)
            }
            return (value as? [Any])?.flatMap(keys) ?? []
        }
        let all = keys(object).map { $0.lowercased() }
        for word in ["photo", "image", "picture", "face", "person", "data"] {
            #expect(!all.contains { $0.contains(word) }, "\(word)")
        }
    }

    @Test func underStylist1TheRequestCarriesNoMeasurements() async throws {
        let consent = StylistConsent(version: "stylist-1", agreedAt: Self.now)
        // stylist-1 isn't current, so the app asks again and sends nothing ...
        await #expect(throws: StylistError.needsConsent) {
            try await stylist(paid(), consent: consent).style(Self.measuredContext())
        }
        // ... and a body built under it never has the field.
        let call = StyleCall.outfit(from: Self.measuredContext(), consentVersion: "stylist-1")
        let data = try APIV1.encoder().encode(APIV1.StyleRequest(call))
        #expect(!String(decoding: data, as: UTF8.self).contains("measurements"))
        #expect(backend.styleRequests.isEmpty)
    }

    @Test func withoutMeasurementsTheBodyHasNoField() async throws {
        _ = try await stylist(paid()).style(Self.context())
        #expect(backend.styleRequests.last?.measurements == nil)
    }

    @Test func theFakeRefusesMeasurementsUnderAConsentThatDoesntNameThem() throws {
        let golden = try ContractTests.data("v1/examples/style-measurements.request.json")
        let request = try JSONDecoder().decode(APIV1.StyleRequest.self, from: golden)
        let object = try #require(JSONSerialization.jsonObject(with: golden) as? [String: Any])
        #expect(FakeStylist.consentCoversMeasurements(request, object: object))
        var older = request
        older.consentVersion = "stylist-1"
        #expect(!FakeStylist.consentCoversMeasurements(older, object: object))
        // stylist-1 without them is still fine.
        var without = object
        without.removeValue(forKey: "measurements")
        #expect(FakeStylist.consentCoversMeasurements(older, object: without))
    }

    @Test(arguments: [
        "style.request.measurements_decimal.json", "style.request.measurements_in_pounds.json",
        "style.request.measurements_out_of_range.json", "style.request.measurements_photo.json",
    ])
    func theFakeRefusesTheContractsInvalidMeasurements(file: String) throws {
        let body = try ContractTests.data("v1/examples/invalid/\(file)")
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let decoded = try? JSONDecoder().decode(APIV1.StyleRequest.self, from: body)
        #expect(decoded.map { FakeStylist.isValid(object, decoded: $0) } != true, "\(file)")
    }
}
