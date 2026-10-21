import Foundation
import Models

// The 27a bodies: POST /v1/style's request and answer. Same rules as APIV1.swift: these mirror
// contract.json, and the contract tests round-trip its golden examples through them.

extension APIV1 {
    /// One piece as the stylist may see it: plain descriptors and the names she gave it. Never a
    /// photo, a note, a brand, a size or when she wore it (DATA_MAP "Cloud styling request").
    public struct StylistPiece: Codable, Sendable, Equatable {
        public var id: String
        public var category: String
        public var kind: String?
        public var colors: [String]
        public var colorNote: String?
        public var fit: String?
        public var dressiness: String
        public var warmth: String
        public var name: String?
        public var otherNames: [String]?

        /// The only place a garment becomes something that can leave the phone.
        public init(_ garment: Garment) {
            id = garment.id.rawValue
            category = garment.category.rawValue
            kind = garment.subKind?.rawValue
            colors = Array(garment.colors.prefix(4).map(\.rawValue))
            colorNote = garment.colorNote.flatMap { Self.trimmed($0, to: 60) }
            fit = garment.fit?.rawValue
            dressiness = ["casual", "smart", "dressy"][garment.dressiness.rawValue]
            warmth = ["light", "medium", "warm"][garment.warmth.rawValue]
            name = Self.trimmed(garment.name, to: 60)
            let others = garment.otherNames.compactMap { Self.trimmed($0, to: 40) }.prefix(3)
            otherNames = others.isEmpty ? nil : Array(others)
        }

        static func trimmed(_ text: String, to limit: Int) -> String? {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : String(clean.prefix(limit))
        }
    }

    public struct StylistColorWish: Codable, Sendable, Equatable {
        public var family: String
        public var strength: String
        public var scope: String
    }

    public struct OutfitRequest: Codable, Sendable, Equatable {
        public var occasion: String
        public var occasionNote: String?
        public var setting: String?
        /// Phase 29's summary, serialized as it is: never `WeatherSnapshot`.
        public var weather: WeatherSummary?
        public var comfort: String?
        public var color: StylistColorWish?
        public var ideaAllowed: Bool
        public var startingPieceId: String?
        public var avoid: [[String]]?
    }

    public struct StylistTurn: Codable, Sendable, Equatable {
        public var from: String
        public var text: String
    }

    public struct StylistQuestion: Codable, Sendable, Equatable {
        public var look: [String]
        public var occasion: String?
        public var text: String
        public var earlier: [StylistTurn]?
    }

    public struct StyleRequest: Codable, Sendable, Equatable {
        public var mode: String
        public var contextRevision: String
        public var consentVersion: String
        public var closet: [StylistPiece]
        public var outfit: OutfitRequest?
        public var question: StylistQuestion?

        public init(_ call: StyleCall) {
            mode = call.mode.rawValue
            contextRevision = call.contextRevision
            consentVersion = call.consentVersion
            closet = call.pieces.map(StylistPiece.init)
            outfit = call.outfit.map { o in
                OutfitRequest(
                    occasion: o.occasion.rawValue,
                    occasionNote: o.occasionNote.flatMap { StylistPiece.trimmed($0, to: 40) },
                    setting: o.indoors ? "indoors" : (o.weather == nil ? nil : "outdoors"),
                    weather: o.indoors ? nil : o.weather,
                    comfort: o.comfort?.rawValue,
                    color: o.color.map {
                        StylistColorWish(family: $0.family.rawValue, strength: $0.strength.rawValue, scope: $0.scope.rawValue)
                    },
                    ideaAllowed: o.ideaAllowed,
                    startingPieceId: o.startingPieceID?.rawValue,
                    avoid: o.avoid.isEmpty ? nil : o.avoid.map { $0.map(\.rawValue) })
            }
            question = call.question.map { q in
                StylistQuestion(
                    look: q.look.map(\.rawValue), occasion: q.occasion?.rawValue, text: String(q.text.prefix(500)),
                    earlier: q.earlier.isEmpty
                        ? nil : q.earlier.suffix(6).map { StylistTurn(from: $0.from.rawValue, text: String($0.text.prefix(600))) })
            }
        }
    }

    public struct StylistIdea: Codable, Sendable, Equatable {
        public var name: String
        public var category: String
        public var colors: [String]
    }

    public struct StylistLook: Codable, Sendable, Equatable {
        public var version: String
        public var pieces: [String]
        public var idea: StylistIdea?
        public var why: String
    }

    public struct StylistMissing: Codable, Sendable, Equatable {
        public var version: String
        public var reason: String
    }

    public struct StylistInsufficient: Codable, Sendable, Equatable {
        public var missing: [String]
    }

    public struct StylistAnswerText: Codable, Sendable, Equatable {
        public var text: String
        public var pieces: [String]
    }

    public struct StylistResult: Codable, Sendable, Equatable {
        public var kind: String
        public var looks: [StylistLook]
        public var missing: [StylistMissing]
        public var insufficient: StylistInsufficient?
        public var answer: StylistAnswerText?
        public var confidence: String?
        public var fromCache: Bool
    }

    public struct StyleResponse: Codable, Sendable, Equatable {
        public var action: PaidAction
        public var result: StylistResult
        public var usage: UsageCategory
    }
}

extension APIV1.StylistResult {
    /// The answer in the app's terms, or nil when a value isn't one of the contract's (then the
    /// response counts as invalid and nothing is shown).
    public var styleAnswer: StyleAnswer? {
        switch kind {
        case "insufficient":
            guard let missing = insufficient?.missing.map(GarmentCategory.init(rawValue:)),
                missing.allSatisfy({ $0 != nil })
            else { return nil }
            return .insufficient(missing.compactMap { $0 }, fromCache: fromCache)
        case "answer":
            guard let answer else { return nil }
            return .answer(answer.text, pieces: answer.pieces.map { Garment.ID($0) }, fromCache: fromCache)
        case "complete", "partial":
            var versions: [StyleAnswer.Version] = []
            for look in looks {
                guard let version = LookVersion(rawValue: look.version) else { return nil }
                var idea: PieceIdea?
                if let i = look.idea {
                    guard let category = GarmentCategory(rawValue: i.category) else { return nil }
                    idea = PieceIdea(name: i.name, category: category, colors: i.colors.compactMap(ColorName.init(rawValue:)))
                }
                versions.append(
                    .init(version: version, pieces: look.pieces.map { Garment.ID($0) }, idea: idea, why: look.why))
            }
            var missingVersions: [MissingVersion] = []
            for m in missing {
                guard let version = LookVersion(rawValue: m.version), let reason = MissingVersion.Reason(rawValue: m.reason)
                else { return nil }
                missingVersions.append(MissingVersion(version: version, reason: reason))
            }
            return .looks(versions, missing: missingVersions, fromCache: fromCache)
        default:
            return nil
        }
    }
}
