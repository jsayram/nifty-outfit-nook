import CryptoKit
import Foundation
import Synchronization

// The cloud stylist (Phase 27a). The app asks the backend's POST /v1/style for outfits and never
// names a provider or a model: the server chooses them. What leaves the phone is a bounded
// snapshot of the pieces she can use today (plain descriptors, never photos, notes, brands or
// sizes), her choices for this request and Phase 29's weather summary, and only after she said
// yes to the consent text (`StylistConsent`).

/// Her yes to sending styling requests to the stylist's provider. The version names the consent
/// text she read; the backend refuses a request whose version doesn't cover where it would send
/// it (PRD 11.3: a new recipient needs new consent).
///
/// Data tier: **Personal**. Kept on the iPhone only; erased by Delete my data.
public struct StylistConsent: Codable, Hashable, Sendable {
    /// The consent text in this app version: Anthropic, naming her height, measurements and
    /// weight (D10, 29 October 2026). `stylist-1` was version A, which promised they never go; a
    /// yes to it is no longer current, so she's asked again.
    public static let currentVersion = "stylist-2"

    public var version: String
    public var agreedAt: Date

    public init(version: String = StylistConsent.currentVersion, agreedAt: Date) {
        self.version = version
        self.agreedAt = agreedAt
    }

    public var isCurrent: Bool { version == Self.currentVersion }

    /// The consent texts that name her height, measurements and weight (D10). Under any other a
    /// request never carries them, and the backend refuses one that does.
    public static let versionsNamingMeasurements: Set<String> = ["stylist-2"]

    public static func namesMeasurements(_ version: String) -> Bool {
        versionsNamingMeasurements.contains(version)
    }
}

/// Where her stylist consent is kept.
public protocol StylistConsentStore: ErasableStore {
    func current() -> StylistConsent?
    /// `nil` withdraws it.
    func save(_ consent: StylistConsent?)
}

/// Consent in memory: previews, tests and the debug sample closet.
public final class InMemoryStylistConsentStore: StylistConsentStore {
    private let state: Mutex<StylistConsent?>

    public init(_ consent: StylistConsent? = nil) {
        state = Mutex(consent)
    }

    public func current() -> StylistConsent? { state.withLock { $0 } }
    public func save(_ consent: StylistConsent?) { state.withLock { $0 = consent } }
    public func eraseAll() async throws(StoreError) { state.withLock { $0 = nil } }
}

/// One request to the cloud stylist, in the app's own terms. `Networking` turns it into the
/// contract's body and decides which of a garment's fields may leave (only plain descriptors).
public struct StyleCall: Sendable, Equatable {
    public enum Mode: String, Sendable { case full, ask }

    public struct Outfit: Sendable, Equatable {
        public var occasion: Occasion
        public var occasionNote: String?
        public var indoors: Bool
        /// Only Phase 29's summary: never a place, a coordinate or a time.
        public var weather: WeatherSummary?
        public var comfort: Comfort?
        public var color: ColorWish?
        public var ideaAllowed: Bool
        public var startingPieceID: Garment.ID?
        /// Main-piece combinations worn recently or already shown for this request.
        public var avoid: [[Garment.ID]]

        public init(
            occasion: Occasion, occasionNote: String? = nil, indoors: Bool = false, weather: WeatherSummary? = nil,
            comfort: Comfort? = nil, color: ColorWish? = nil, ideaAllowed: Bool, startingPieceID: Garment.ID? = nil,
            avoid: [[Garment.ID]] = []
        ) {
            self.occasion = occasion
            self.occasionNote = occasionNote
            self.indoors = indoors
            self.weather = weather
            self.comfort = comfort
            self.color = color
            self.ideaAllowed = ideaAllowed
            self.startingPieceID = startingPieceID
            self.avoid = avoid
        }
    }

    public struct Turn: Sendable, Equatable {
        public enum From: String, Sendable { case her, stylist }
        public var from: From
        public var text: String

        public init(from: From, text: String) {
            self.from = from
            self.text = text
        }
    }

    public struct Question: Sendable, Equatable {
        public var look: [Garment.ID]
        public var occasion: Occasion?
        public var text: String
        public var earlier: [Turn]

        public init(look: [Garment.ID], occasion: Occasion? = nil, text: String, earlier: [Turn] = []) {
            self.look = look
            self.occasion = occasion
            self.text = text
            self.earlier = earlier
        }
    }

    /// Her measurements and weight in whole centimetres and kilograms (D10), as the stylist may
    /// see them. Only the numbers she filled in, each inside the contract's range; never a photo.
    ///
    /// Data tier: **Sensitive**. Goes only inside a request whose consent names it.
    public struct Measurements: Hashable, Sendable, Codable {
        public var heightCm: Int?
        public var bustCm: Int?
        public var waistCm: Int?
        public var hipsCm: Int?
        public var inseamCm: Int?
        public var weightKg: Int?

        /// The contract's ranges (`StylistMeasurements`). The app's own limits round into them; a
        /// value outside is left out rather than refused with the whole request.
        static let heightRange = 91...244
        static let bustRange = 50...178
        static let waistRange = 38...178
        static let hipsRange = 50...204
        static let inseamRange = 38...115
        static let weightRange = 22...318

        public init(
            heightCm: Int? = nil, bustCm: Int? = nil, waistCm: Int? = nil, hipsCm: Int? = nil, inseamCm: Int? = nil,
            weightKg: Int? = nil
        ) {
            self.heightCm = heightCm
            self.bustCm = bustCm
            self.waistCm = waistCm
            self.hipsCm = hipsCm
            self.inseamCm = inseamCm
            self.weightKg = weightKg
        }

        /// Her profile's values, rounded to whole units. `nil` when none is filled in.
        public init?(_ body: BodyMeasurements) {
            self.init(
                heightCm: Self.centimetres(body.height, in: Self.heightRange),
                bustCm: Self.centimetres(body.bust, in: Self.bustRange),
                waistCm: Self.centimetres(body.waist, in: Self.waistRange),
                hipsCm: Self.centimetres(body.hips, in: Self.hipsRange),
                inseamCm: Self.centimetres(body.inseam, in: Self.inseamRange),
                weightKg: Self.kilograms(body.weight, in: Self.weightRange))
            if isEmpty { return nil }
        }

        public var isEmpty: Bool {
            heightCm == nil && bustCm == nil && waistCm == nil && hipsCm == nil && inseamCm == nil && weightKg == nil
        }

        static func centimetres(_ length: Length?, in range: ClosedRange<Int>) -> Int? {
            guard let length else { return nil }
            let value = length.unit == .centimeters ? length.value : length.value * 2.54
            return whole(value, in: range)
        }

        static func kilograms(_ weight: Weight?, in range: ClosedRange<Int>) -> Int? {
            guard let weight else { return nil }
            let value = weight.unit == .kilograms ? weight.value : weight.value / 2.204_622_6
            return whole(value, in: range)
        }

        private static func whole(_ value: Double, in range: ClosedRange<Int>) -> Int? {
            guard value.isFinite else { return nil }
            let rounded = value.rounded()
            guard rounded >= Double(range.lowerBound), rounded <= Double(range.upperBound) else { return nil }
            return Int(rounded)
        }
    }

    public var mode: Mode
    public var contextRevision: String
    public var consentVersion: String
    public var pieces: [Garment]
    public var outfit: Outfit?
    public var question: Question?
    /// D10: only when `consentVersion` names them (`StylistConsent.namesMeasurements`); under any
    /// other consent this is always `nil`, whatever was passed, even if the version changes later.
    public var measurements: Measurements? {
        StylistConsent.namesMeasurements(consentVersion) ? givenMeasurements : nil
    }
    private var givenMeasurements: Measurements?

    public init(
        mode: Mode, contextRevision: String, consentVersion: String, pieces: [Garment], outfit: Outfit?,
        question: Question?, measurements: Measurements? = nil
    ) {
        self.mode = mode
        self.contextRevision = contextRevision
        self.consentVersion = consentVersion
        self.pieces = pieces
        self.outfit = outfit
        self.question = question
        givenMeasurements = measurements?.isEmpty == false ? measurements : nil
    }

    /// At most this many pieces go in one request (the contract's limit).
    public static let maximumPieces = 150
    /// At most this many combinations to avoid (the contract's limit).
    public static let maximumAvoid = 30

    /// The request for one outfit from a styling context built on the phone.
    public static func outfit(from context: StylingContext, consentVersion: String) -> StyleCall {
        let request = context.request
        let pieces = bounded(context.eligibleGarments, keeping: request.startingPieceID)
        let ids = Set(pieces.map(\.id))
        let combinations = Array(context.recentCombinations.keys) + Array(context.shownCombinations)
        let avoid = combinations.map { $0.sorted() }.filter { $0.allSatisfy(ids.contains) && !$0.isEmpty }
            .sorted { $0.map(\.rawValue).joined() < $1.map(\.rawValue).joined() }
        let outfit = Outfit(
            occasion: request.occasion,
            occasionNote: request.occasion == .other ? request.occasionNote : nil,
            indoors: request.weatherChoice == .indoors,
            weather: request.weatherToUse?.summary,
            comfort: context.effectiveComfort,
            color: request.color,
            ideaAllowed: request.allowsNewPieceIdea,
            startingPieceID: request.startingPieceID,
            avoid: Array(avoid.prefix(maximumAvoid)))
        return StyleCall(
            mode: .full, contextRevision: revision(of: pieces), consentVersion: consentVersion, pieces: pieces,
            outfit: outfit, question: nil, measurements: context.measurements)
    }

    /// The pieces to send, sorted by ID: all of them, or the starting piece and the most recently
    /// worn or added when there are more than the limit.
    static func bounded(_ garments: [Garment], keeping start: Garment.ID?) -> [Garment] {
        guard garments.count > maximumPieces else { return garments.sorted { $0.id < $1.id } }
        let ranked = garments.sorted { ($0.lastWorn ?? $0.addedAt) > ($1.lastWorn ?? $1.addedAt) }
        var kept = Array(ranked.prefix(maximumPieces))
        if let start, !kept.contains(where: { $0.id == start }), let piece = garments.first(where: { $0.id == start }) {
            kept[kept.count - 1] = piece
        }
        return kept.sorted { $0.id < $1.id }
    }

    /// A short revision of the pieces sent, so the server can tell snapshots apart. Names no piece.
    static func revision(of pieces: [Garment]) -> String {
        let text = pieces.map { "\($0.id)|\($0.category)|\($0.colors.map(\.rawValue))|\($0.name)" }.joined(
            separator: "\n")
        let digest = SHA256.hash(data: Data(text.utf8))
        return "rev_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// What the cloud stylist answered, checked by the backend and decoded by `Networking`.
public enum StyleAnswer: Sendable, Equatable {
    public struct Version: Sendable, Equatable {
        public var version: LookVersion
        public var pieces: [Garment.ID]
        public var idea: PieceIdea?
        /// The stylist's one-line reason, already checked on the server. May be empty.
        public var why: String

        public init(version: LookVersion, pieces: [Garment.ID], idea: PieceIdea? = nil, why: String) {
            self.version = version
            self.pieces = pieces
            self.idea = idea
            self.why = why
        }
    }

    /// One outfit in up to three versions, with any version that couldn't be made and why.
    case looks([Version], missing: [MissingVersion], fromCache: Bool)
    /// No outfit can be made from these pieces.
    case insufficient([GarmentCategory], fromCache: Bool)
    /// Ask stylist's answer, with the pieces it mentions.
    case answer(String, pieces: [Garment.ID], fromCache: Bool)
}

/// A stylist whose requests are paid jobs (27c): each job passes its own Idempotency-Key, so a
/// job resumed after a relaunch sends the same request with the same key and is never run or
/// charged twice. `CloudStylist` is one; Stage A's stylist on the phone isn't.
public protocol KeyedStylist: Stylist {
    /// The consent text she agreed to, or `needsConsent`.
    func consentVersion() throws(StylistError) -> String
    func style(_ context: StylingContext, consentVersion: String, idempotencyKey: String)
        async throws(StylistError) -> StyleOutcome
    func ask(_ request: AskStylistRequest, idempotencyKey: String) async throws(StylistError) -> StylistReply
}

/// Ask stylist's answer: its words and the pieces it mentions (only pieces that were sent).
public struct StylistReply: Hashable, Sendable {
    public var text: String
    public var pieces: [Garment.ID]

    public init(text: String, pieces: [Garment.ID]) {
        self.text = text
        self.pieces = pieces
    }
}

/// The stylist behind Style Me once the cloud is on: one paid action per request, through the
/// 24b gateway, with a new idempotency key each time she asks (retries of that one request reuse
/// it inside the client).
public struct CloudStylist: KeyedStylist {
    private let paid: any PaidActionService
    private let consent: any StylistConsentStore
    private let makeKey: @Sendable () -> String

    public init(
        paid: any PaidActionService, consent: any StylistConsentStore,
        makeKey: @escaping @Sendable () -> String = { IdempotencyKey.make() }
    ) {
        self.paid = paid
        self.consent = consent
        self.makeKey = makeKey
    }

    public func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        try await style(context, consentVersion: try consentVersion(), idempotencyKey: makeKey())
    }

    /// The consent text she agreed to, or `needsConsent`: no consent, no call, and nothing leaves
    /// the phone.
    public func consentVersion() throws(StylistError) -> String {
        guard let agreed = consent.current(), agreed.isCurrent else { throw .needsConsent }
        return agreed.version
    }

    /// 27c: one styling job's request, with the job's own key. The same context, consent version
    /// and key always send the same body, so asking again (a retry, or after a relaunch) gets the
    /// server's record instead of a second run.
    public func style(_ context: StylingContext, consentVersion: String, idempotencyKey: String)
        async throws(StylistError) -> StyleOutcome
    {
        let call = StyleCall.outfit(from: context, consentVersion: consentVersion)
        let (answer, actionID) = try await send(call, idempotencyKey: idempotencyKey)
        guard let answer else { throw .notCompleted }
        return try Self.outcome(answer, for: context, sentIDs: Set(call.pieces.map(\.id)), actionID: actionID)
    }

    /// 27c: an Ask stylist question, with its job's key. Only the pieces that were sent may be
    /// mentioned.
    public func ask(_ request: AskStylistRequest, idempotencyKey: String) async throws(StylistError) -> StylistReply {
        let call = request.call
        guard case .answer(let text, let pieces, _) = try await send(call, idempotencyKey: idempotencyKey).answer,
            !text.isEmpty
        else { throw .notCompleted }
        let sent = Set(call.pieces.map(\.id))
        return StylistReply(text: text, pieces: pieces.filter(sent.contains))
    }

    private func send(_ call: StyleCall, idempotencyKey: String) async throws(StylistError) -> (
        answer: StyleAnswer?, actionID: String
    ) {
        let receipt: PaidActionReceipt
        do {
            receipt = try await paid.run(.style(call), idempotencyKey: idempotencyKey)
        } catch {
            throw Self.error(for: error)
        }
        if Task.isCancelled { throw .cancelled }
        return (receipt.style, receipt.id)
    }

    /// The backend's checked answer as the app's outcome. Every piece must be one that was sent;
    /// anything else means the answer can't be trusted, so it didn't finish.
    /// - Parameter actionID: Release: the server's ID for the action that made it, which becomes
    ///   the result's ID, so Report a problem can name the action (`AIReportTarget`). A random ID
    ///   when there's none.
    static func outcome(
        _ answer: StyleAnswer, for context: StylingContext, sentIDs: Set<Garment.ID>, actionID: String? = nil
    )
        throws(StylistError)
        -> StyleOutcome
    {
        let request = context.request
        switch answer {
        case .insufficient(let missing, _):
            return .insufficient(InsufficientWardrobe(source: request.source, missing: missing))
        case .answer:
            throw .notCompleted
        case .looks(let versions, let missing, let fromCache):
            guard let simpleVersion = versions.first(where: { $0.version == .simple }),
                versions.allSatisfy({ $0.pieces.allSatisfy(sentIDs.contains) })
            else { throw .notCompleted }
            let categories = Dictionary(
                context.eligibleGarments.map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
            let resultID = actionID.map { StyleResult.ID($0) } ?? .random()
            let intent = StyleIntent(request)
            let simpleIDs = Set(simpleVersion.pieces)
            let looks = versions.map { version in
                let ordered = version.pieces.sorted {
                    (categories[$0] ?? .accessory, $0) < (categories[$1] ?? .accessory, $1)
                }
                var pieces = ordered.map { id in
                    LookPiece(
                        id: .random(), content: .garment(id),
                        isSameAsSimple: version.version == .simple || simpleIDs.contains(id))
                }
                if let idea = version.idea { pieces.append(LookPiece(id: .random(), content: .idea(idea))) }
                return Look(
                    id: .random(), resultID: resultID, version: version.version, pieces: pieces,
                    occasion: request.occasion, source: request.source, createdAt: context.now,
                    why: version.why.isEmpty ? nil : version.why, intent: intent)
            }
            var notes: [ResultNote] = []
            let main = WearRules.mainPieces(of: looks[0], categories: categories)
            if let worn = context.recentCombinations[main] { notes.append(.wornRecently(lastWorn: worn)) }
            if request.source.isSuitcase && request.preferences.pieceMode == .mineAndOneIdea {
                notes.append(.noNewPieceInSuitcase)
            }
            if request.weatherChoice == .useToday && request.weather == nil { notes.append(.weatherUnavailable) }
            if let color = request.color, color.strength == .required,
                !context.eligibleGarments.contains(where: { simpleIDs.contains($0.id) && color.fits($0) })
            {
                notes.append(.requiredColorNotMet(color.family))
            }
            if fromCache { notes.append(.answeredAgain) }
            let result = StyleResult(
                id: resultID, requestID: request.id, versions: looks, notes: notes, createdAt: context.now)
            return missing.isEmpty ? .complete(result) : .partial(result, missing: missing)
        }
    }

    static func error(for problem: CloudLimitProblem) -> StylistError {
        switch problem {
        case .account(.offline): .offline
        case .account(.timedOut): .timedOut
        case .account(.cancelled): .cancelled
        case .didNotFinish: .notCompleted
        case .needsConsent: .needsConsent
        default: .limited(problem)
        }
    }
}

extension StyleCall {
    /// An Ask stylist question about one look, with the earlier turns of that conversation
    /// (Phase 27a builds the request; the screen is still a stand-in).
    public static func question(
        _ text: String, about look: Look, pieces: [Garment], earlier: [Turn], consentVersion: String,
        measurements: Measurements? = nil
    ) -> StyleCall {
        let sent = pieces.sorted { $0.id < $1.id }
        return StyleCall(
            mode: .ask, contextRevision: revision(of: sent), consentVersion: consentVersion, pieces: sent, outfit: nil,
            question: Question(
                look: look.garmentIDs.filter { id in sent.contains { $0.id == id } }, occasion: look.occasion,
                text: text, earlier: Array(earlier.suffix(6))),
            measurements: measurements)
    }

    /// A small made-up request, for the debug limits screen and tests: three plain pieces, no
    /// names of hers. `full` asks for an outfit; `ask` asks a question (a quick request).
    public static func sample(_ mode: Mode, note: String = "sample") -> StyleCall {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let pieces = [
            Garment(id: .init("g-sample-top"), name: "Top", category: .top, colors: [.cream], addedAt: date),
            Garment(id: .init("g-sample-bottom"), name: "Trousers", category: .bottom, colors: [.olive], addedAt: date),
            Garment(id: .init("g-sample-shoes"), name: "Loafers", category: .shoes, colors: [.brown], addedAt: date),
        ]
        switch mode {
        case .full:
            return StyleCall(
                mode: .full, contextRevision: revision(of: pieces), consentVersion: StylistConsent.currentVersion,
                pieces: pieces,
                outfit: Outfit(
                    occasion: .other, occasionNote: note, indoors: true, weather: nil, comfort: nil, color: nil,
                    ideaAllowed: false, startingPieceID: nil, avoid: []),
                question: nil)
        case .ask:
            return StyleCall(
                mode: .ask, contextRevision: revision(of: pieces), consentVersion: StylistConsent.currentVersion,
                pieces: pieces, outfit: nil,
                question: Question(
                    look: pieces.map(\.id), occasion: .office, text: "Is this OK? (\(note))", earlier: []))
        }
    }
}
