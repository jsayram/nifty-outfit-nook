import Foundation

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// How the fake backend's stylist behaves (27a), like the backend's NOOK_STYLIST_FAKE.
    public enum FakeStylistBehaviour: String, Sendable, CaseIterable {
        /// Answers with looks from the request's own pieces.
        case normal
        /// The provider fails (overloaded, refused, invalid JSON): 503, "It didn't work this time. It
        /// wasn't counted."
        case fails
        /// 27c: answers like `normal`, but only after `slowAnswer`, like a busy provider, so there's
        /// time to leave the screen, browse and search before the looks are ready.
        case slow

        /// How long `slow` takes. Under the paid-text try timeout (40 seconds), so one try answers.
        public static let slowAnswer: Duration = .seconds(15)
    }

    /// The fake backend's stand-in stylist: the same plain rules as the backend's fake
    /// (convex/stylist/fake.ts), on the request's own pieces, so the app sees contract-shaped looks
    /// made only of what it sent, each with a why line. Not taste, and not the real prompt.
    enum FakeStylist {
        static let consentVersions: Set<String> = ["stylist-1"]

        private static let rank = ["casual": 0, "smart": 1, "dressy": 2]
        private static let warmthRank = ["light": 0, "medium": 1, "warm": 2]

        static func answer(_ request: APIV1.StyleRequest) -> APIV1.StylistResult {
            if request.mode == "ask", let question = request.question {
                return ask(question, closet: request.closet)
            }
            guard let outfit = request.outfit else { return insufficient(["top", "bottom"]) }
            let closet = request.closet
            let has = { (c: String) in closet.contains { $0.category == c } }
            guard has("dress") || (has("top") && has("bottom")) else {
                return insufficient(["top", "bottom"].filter { !has($0) })
            }
            let target = ["office", "event", "dateNight"].contains(outfit.occasion) ? 1 : 0
            let temperature = outfit.setting == "indoors" ? 20 : (outfit.weather?.temperatureCelsius ?? 18)
            let wet =
                outfit.setting != "indoors"
                && (outfit.weather?.condition == .rain || outfit.weather?.condition == .snow)
            let wantWarmth = temperature < 10 ? 2 : temperature < 18 ? 1 : 0
            let avoid = Set((outfit.avoid ?? []).map { $0.sorted().joined(separator: "+") })
            func score(_ p: APIV1.StylistPiece) -> Int {
                -abs((rank[p.dressiness] ?? 0) - target) * 3 - abs((warmthRank[p.warmth] ?? 0) - wantWarmth)
                    + (outfit.color.map { p.colors.contains($0.family) ? 2 : 0 } ?? 0)
            }
            func best(_ category: String, except: Set<String> = []) -> APIV1.StylistPiece? {
                closet.filter { $0.category == category && !except.contains($0.id) }
                    .sorted { (score($0), $1.id) > (score($1), $0.id) }.first
            }
            let start = closet.first { $0.id == outfit.startingPieceId }

            var main: [APIV1.StylistPiece] = []
            if let start, start.category == "dress" {
                main = [start]
            } else if let start, start.category == "top" || start.category == "bottom",
                let other = best(start.category == "top" ? "bottom" : "top")
            {
                main = [start, other]
            }
            if main.isEmpty {
                let tops = closet.filter { $0.category == "top" }.sorted { score($0) > score($1) }
                let bottoms = closet.filter { $0.category == "bottom" }.sorted { score($0) > score($1) }
                let pairs = tops.flatMap { t in bottoms.map { [t, $0] } }
                    .sorted { score($0[0]) + score($0[1]) > score($1[0]) + score($1[1]) }
                main =
                    pairs.first { !avoid.contains($0.map(\.id).sorted().joined(separator: "+")) } ?? pairs.first ?? []
                if main.isEmpty, let dress = best("dress") { main = [dress] }
            }
            var simple = main
            if let shoes = best("shoes", except: Set(simple.map(\.id))) { simple.append(shoes) }
            if let start, !simple.contains(where: { $0.id == start.id }), simple.count < 6 { simple.append(start) }
            if temperature < 14 || wet, !simple.contains(where: { $0.category == "layer" }),
                let layer = best("layer", except: Set(simple.map(\.id)))
            {
                simple.append(layer)
            }

            let occasion =
                outfit.occasion == "dateNight"
                ? "date night" : outfit.occasion == "other" ? "the day" : "the \(outfit.occasion)"
            let weather = outfit.setting == "indoors" ? "indoors" : wet ? "the wet weather" : "today's weather"
            let pair = main.count > 1 ? "\(words(main[0])) and \(words(main[1]))" : words(main[0])
            var looks = [
                APIV1.StylistLook(
                    version: "simple", pieces: simple.map(\.id), idea: nil,
                    why: "The \(pair) keep it easy for \(occasion), and suit \(weather).")
            ]

            let inSimple = Set(simple.map(\.id))
            for piece in simple.sorted(by: { (rank[$0.dressiness] ?? 0) < (rank[$1.dressiness] ?? 0) })
            where piece.id != start?.id {
                let better = closet.filter {
                    $0.category == piece.category && !inSimple.contains($0.id)
                        && (rank[$0.dressiness] ?? 0) > (rank[piece.dressiness] ?? 0)
                }.max { (rank[$0.dressiness] ?? 0) < (rank[$1.dressiness] ?? 0) }
                if let better {
                    looks.append(
                        APIV1.StylistLook(
                            version: "dressedUp", pieces: simple.map { $0.id == piece.id ? better.id : $0.id },
                            idea: nil,
                            why: "The \(words(better)) makes the same outfit a little classier."))
                    break
                }
            }
            if outfit.ideaAllowed, simple.count < 6 {
                let hasLayer = simple.contains { $0.category == "layer" }
                let idea =
                    hasLayer
                    ? APIV1.StylistIdea(name: "Statement belt", category: "accessory", colors: ["tan"])
                    : APIV1.StylistIdea(name: "Rust knit vest", category: "layer", colors: ["orange"])
                looks.append(
                    APIV1.StylistLook(
                        version: "somethingNew", pieces: simple.map(\.id), idea: idea,
                        why: "A \(idea.name.lowercased()) would give the same outfit a new texture."))
            } else if let swap = simple.reversed().first(where: { p in
                p.id != start?.id && closet.contains { $0.category == p.category && !inSimple.contains($0.id) }
            }), let other = closet.first(where: { $0.category == swap.category && !inSimple.contains($0.id) }) {
                looks.append(
                    APIV1.StylistLook(
                        version: "somethingNew", pieces: simple.map { $0.id == swap.id ? other.id : $0.id }, idea: nil,
                        why: "Trying the \(words(other)) takes the same outfit another way with your own pieces."))
            }
            var missing: [APIV1.StylistMissing] = []
            if !looks.contains(where: { $0.version == "dressedUp" }) {
                missing.append(.init(version: "dressedUp", reason: "noDressierPiece"))
            }
            if !looks.contains(where: { $0.version == "somethingNew" }) {
                missing.append(.init(version: "somethingNew", reason: "noOtherOwnedPiece"))
            }
            return APIV1.StylistResult(
                kind: missing.isEmpty ? "complete" : "partial", looks: looks, missing: missing, insufficient: nil,
                answer: nil, confidence: "high", fromCache: false)
        }

        private static func ask(_ question: APIV1.StylistQuestion, closet: [APIV1.StylistPiece]) -> APIV1.StylistResult
        {
            let look = closet.filter { question.look.contains($0.id) }
            let shoes = closet.first { $0.category == "shoes" && !question.look.contains($0.id) }
            let first = look.first.map(words) ?? "look"
            let text =
                shoes.map {
                    "It works as it is. For a change, the \(words($0)) would give the \(first) a different feel."
                }
                ?? "It works as it is. Keep the \(first) as the focus and keep the rest simple."
            return APIV1.StylistResult(
                kind: "answer", looks: [], missing: [], insufficient: nil,
                answer: .init(text: text, pieces: (look.prefix(1) + [shoes].compactMap { $0 }).map(\.id)),
                confidence: "medium", fromCache: false)
        }

        private static func insufficient(_ missing: [String]) -> APIV1.StylistResult {
            APIV1.StylistResult(
                kind: "insufficient", looks: [], missing: [], insufficient: .init(missing: missing), answer: nil,
                confidence: nil, fromCache: false)
        }

        private static func words(_ p: APIV1.StylistPiece) -> String {
            "\(p.colors.first ?? "") \(p.kind ?? p.category)".trimmingCharacters(in: .whitespaces).lowercased()
        }

        /// The fake's checks of a style body beyond decoding: the contract's keys, mode and limits.
        static func isValid(_ object: [String: Any], decoded: APIV1.StyleRequest) -> Bool {
            let top: Set<String> = ["mode", "contextRevision", "consentVersion", "closet", "outfit", "question"]
            let piece: Set<String> = [
                "id", "category", "kind", "colors", "colorNote", "fit", "dressiness", "warmth", "name", "otherNames",
            ]
            guard Set(object.keys).isSubset(of: top), ["full", "ask"].contains(decoded.mode),
                decoded.contextRevision.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil,
                decoded.closet.count <= 150,
                (object["closet"] as? [[String: Any]])?.allSatisfy({ Set($0.keys).isSubset(of: piece) }) == true
            else { return false }
            let ids = Set(decoded.closet.map(\.id))
            guard ids.count == decoded.closet.count else { return false }
            if decoded.mode == "full" {
                guard let outfit = decoded.outfit, decoded.question == nil, !decoded.closet.isEmpty else {
                    return false
                }
                if let start = outfit.startingPieceId, !ids.contains(start) { return false }
                return (outfit.avoid ?? []).allSatisfy { $0.allSatisfy(ids.contains) }
            }
            guard let question = decoded.question, decoded.outfit == nil else { return false }
            return !question.look.isEmpty && question.look.allSatisfy(ids.contains) && question.text.count <= 500
        }
    }
#endif
