import Foundation
import Models
import Testing

@testable import Services

/// Payload version 1, as Phase 21a writes it, for every kind of record. Every later build must
/// still read these: a change to a value type's JSON that breaks one of them needs a new payload
/// version with an upgrade in `RecordPayload` (and a fixture of its own here). Never edit these
/// strings to make a test pass.
struct RecordPayloadTests {
    static let garmentV1 =
        #"{"addedAt":794664000,"availability":{"available":{}},"brand":"Demo Brand A","category":"bottom","colors":["navy"],"cutout":{"aspectRatio":0.421875,"image":{"sample":{"_0":"wardrobe:cutout:g-navy-trousers"}},"quality":{"coverage":0.28030120735028435,"instanceCount":1,"largestInstanceShare":1,"softEdgeRatio":0.03722755830620638,"subjectBounds":{"height":0.9153976311336718,"width":0.49887133182844245,"x":0.25395033860045146,"y":0.028764805414551606},"touchedEdges":0}},"dressiness":2,"fit":"regular","id":"g-navy-trousers","isArchived":false,"laundry":"clean","name":"Navy dress pants","notes":"","occasions":["dateNight","office","event"],"ownership":{"owned":{}},"photo":{"sample":{"_0":"wardrobe:photo:g-navy-trousers"}},"seasons":["winter","fall","summer","spring"],"warmth":1,"wornOn":[796392000,813240000]}"#
    static let lookV1 =
        #"{"createdAt":812980800,"id":"o-brunch-idea","isSaved":true,"name":"Brunch with a new layer","occasion":"brunch","pieces":[{"content":{"garment":{"_0":"g-pink-blouse"}},"id":"o-brunch-idea-g-pink-blouse","isSameAsSimple":true},{"content":{"garment":{"_0":"g-olive-trousers"}},"id":"o-brunch-idea-g-olive-trousers","isSameAsSimple":true},{"content":{"garment":{"_0":"g-tan-loafers"}},"id":"o-brunch-idea-g-tan-loafers","isSameAsSimple":true},{"content":{"idea":{"_0":{"category":"layer","colors":["cream"],"name":"Cropped cream cardigan"}}},"id":"o-brunch-idea-idea","isSameAsSimple":false}],"resultID":"r-o-brunch-idea","savedAt":812980800,"source":{"mainCloset":{}},"version":"somethingNew","wornOn":[]}"#
    static let suitcaseV1 =
        #"{"createdAt":811080000,"garmentIDs":["g-navy-cardigan","g-nude-flats","g-lace-top","g-navy-trousers","g-pink-blouse"],"icon":"rolling","id":"s-jose","isArchived":false,"lastUsedAt":813585600,"name":"Jose's house"}"#
    static let pictureV1 =
        #"{"captured":{"name":"Interview navy and pink","occasion":"office","pieces":[{"content":{"garment":{"_0":"g-navy-cardigan"}},"id":"o-interview-g-navy-cardigan","isSameAsSimple":true},{"content":{"garment":{"_0":"g-pink-blouse"}},"id":"o-interview-g-pink-blouse","isSameAsSimple":true},{"content":{"garment":{"_0":"g-navy-trousers"}},"id":"o-interview-g-navy-trousers","isSameAsSimple":true},{"content":{"garment":{"_0":"g-nude-flats"}},"id":"o-interview-g-nude-flats","isSameAsSimple":true}]},"createdAt":810388800,"id":"p-interview","image":{"simulated":{}},"lookID":"o-interview"}"#
    static let profileV1 =
        #"{"avoidedColors":["orange"],"fitPieces":[{"brand":"Example Denim Co.","category":"bottom","garmentID":"g-wide-jeans","id":"f-jeans","result":"fitsWell","sizeLabel":"S"}],"likedColors":["navy","pink","olive","brick"],"measurements":{"height":{"unit":"centimeters","value":150},"waist":{"unit":"inches","value":26},"weight":{"unit":"kilograms","value":50}},"preferences":{"pieceMode":"mineAndOneIdea","repeatWindow":"oneWeek","tracksLaundry":false},"remembered":{"occasion":"dateNight","source":{"suitcase":{"_0":"s-jose"}}},"signName":"Lily","tryOnPhoto":{"sample":{"_0":"tryon"}},"units":"metric","usualFit":"comfortable"}"#
    static let garmentDraftV1 =
        #"{"base":{"brand":"","colorNote":"","colors":[],"dressiness":1,"name":"Navy dress pants","notes":"","occasions":[],"photo":{"noPhoto":{}},"seasons":["spring","summer","winter","fall"],"sizeLabel":"","warmth":1},"description":"navy trousers","details":{"brand":"","colorNote":"","colors":[],"dressiness":1,"name":"Navy work trousers","notes":"","occasions":[],"photo":{"noPhoto":{}},"seasons":["spring","winter","summer","fall"],"sizeLabel":"","warmth":1},"savedAt":813672000,"step":"details","target":{"garment":{"_0":"g-navy-trousers"}}}"#
    static let lookDraftV1 =
        #"{"garmentIDs":["g-pink-shirt"],"name":"Pink for Friday","savedAt":813672000,"source":{"mainCloset":{}}}"#
    static let feedbackDraftV1 = #"{"includesDetails":true,"kind":"idea","message":"The hamper is lovely"}"#
    static let onboardingV1 = #"{"isCompleted":true,"startingCloset":"empty"}"#
    static let toursV1 = #"{"seenVersions":{"home":2},"showsTipsOnNewScreens":false}"#

    // Payload version 2 (Phase 21c): garments and garment drafts gain `otherNames` and `subKind`.
    static let garmentV2 =
        #"{"addedAt":813672000,"availability":{"available":{}},"category":"layer","colors":["green"],"colorNote":"Sage","dressiness":0,"id":"g-sage","isArchived":false,"laundry":"clean","name":"Sage cardigan","notes":"","occasions":[],"otherNames":["Green cardigan","Cozy one"],"ownership":{"owned":{}},"photo":{"noPhoto":{}},"seasons":["fall","winter"],"subKind":"cardigan","warmth":2,"wornOn":[]}"#
    static let garmentDraftV2 =
        #"{"base":{"brand":"","colorNote":"","colors":[],"dressiness":1,"name":"","notes":"","occasions":[],"otherNames":[],"photo":{"noPhoto":{}},"seasons":["spring","summer","winter","fall"],"sizeLabel":"","warmth":1},"description":"","details":{"brand":"","category":"layer","colorNote":"","colors":[],"dressiness":1,"name":"Sage cardigan","notes":"","occasions":[],"otherNames":["Cozy one"],"photo":{"noPhoto":{}},"seasons":["spring","winter","summer","fall"],"sizeLabel":"","subKind":"cardigan","warmth":1},"savedAt":813672000,"step":"details","target":{"newPiece":{}}}"#

    private func decoded<Value: Codable & Equatable>(_ type: Value.Type, _ json: String) throws -> Value {
        let value = try RecordPayload.decode(type, from: Data(json.utf8), version: 1)
        // And it writes back to something that reads as the same value.
        #expect(try RecordPayload.decode(type, from: try RecordPayload.encode(value), version: 1) == value)
        return value
    }

    @Test func version1PayloadsStillDecode() throws {
        let garment = try decoded(Garment.self, Self.garmentV1)
        #expect(garment.id == "g-navy-trousers")
        #expect(garment.cutout != nil)
        #expect(!garment.wornOn.isEmpty)
        #expect(try decoded(Look.self, Self.lookV1).isSaved)
        #expect(try decoded(Suitcase.self, Self.suitcaseV1).name == "Jose's house")
        #expect(try decoded(TryOnPicture.self, Self.pictureV1).captured.name == "Interview navy and pink")
        let profile = try decoded(Profile.self, Self.profileV1)
        #expect(profile.signName == "Lily")
        #expect(profile.measurements.weight == Weight(50, .kilograms))
        #expect(profile.remembered == RememberedChoices(source: .suitcase("s-jose"), occasion: .dateNight))
        #expect(try decoded(GarmentDraft.self, Self.garmentDraftV1).target == .garment("g-navy-trousers"))
        #expect(try decoded(LookDraft.self, Self.lookDraftV1).name == "Pink for Friday")
        #expect(try decoded(FeedbackDraft.self, Self.feedbackDraftV1).message == "The hamper is lovely")
        #expect(try decoded(StoredOnboarding.self, Self.onboardingV1).startingCloset == .empty)
        #expect(try decoded(StoredTours.self, Self.toursV1).seenVersions == ["home": 2])
    }

    /// Version 1 garments and garment drafts read with no other names and no type.
    @Test func version1GarmentsHaveNoOtherNamesOrType() throws {
        let garment = try decoded(Garment.self, Self.garmentV1)
        #expect(garment.otherNames.isEmpty && garment.subKind == nil)
        let draft = try decoded(GarmentDraft.self, Self.garmentDraftV1)
        #expect(draft.details.otherNames.isEmpty && draft.details.subKind == nil)
        #expect(draft.base.otherNames.isEmpty && draft.base.subKind == nil)
    }

    @Test func version2PayloadsDecode() throws {
        #expect(RecordPayload.currentVersion == 2)
        let garment = try RecordPayload.decode(Garment.self, from: Data(Self.garmentV2.utf8), version: 2)
        #expect(garment.otherNames == ["Green cardigan", "Cozy one"])
        #expect(garment.subKind == .cardigan)
        #expect(try RecordPayload.decode(Garment.self, from: try RecordPayload.encode(garment), version: 2) == garment)
        let draft = try RecordPayload.decode(GarmentDraft.self, from: Data(Self.garmentDraftV2.utf8), version: 2)
        #expect(draft.details.otherNames == ["Cozy one"] && draft.details.subKind == .cardigan)
        #expect(draft.base.otherNames.isEmpty && draft.base.subKind == nil)
    }

    /// A payload from a newer build is refused, never misread.
    @Test func aNewerPayloadVersionIsRefused() {
        #expect(throws: RecordPayload.PayloadError.unknownVersion(3)) {
            try RecordPayload.decode(FeedbackDraft.self, from: Data(Self.feedbackDraftV1.utf8), version: 3)
        }
        #expect(throws: RecordPayload.PayloadError.unknownVersion(0)) {
            try RecordPayload.decode(FeedbackDraft.self, from: Data(Self.feedbackDraftV1.utf8), version: 0)
        }
    }
}
