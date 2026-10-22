import CryptoKit
import Foundation
import Synchronization

// Phase 33a: real try-on pictures, with her face kept on the phone (closet THREAT_MODEL.md, D1).
// Before anything leaves the phone, Apple Vision traces her and her head, the head is filled with
// flat grey and the room is swapped for a plain studio backdrop. Only that faceless photo and the
// garment photos go to the backend, which asks FLUX.3 for the dressed picture. Back on the phone,
// her real head goes back on. See docs/try-on-pictures.md, "Real pictures (33a)".

/// Her yes to sending try-on photos to the image provider (D1). The version names the consent
/// text she read; the backend refuses a request whose version doesn't cover where it would send
/// the photos (PRD 11.3: a new recipient needs new consent).
///
/// Data tier: **Personal**. Kept on the iPhone only; erased by Delete my data.
public struct TryOnConsent: Codable, Hashable, Sendable {
    /// The consent text in this app version: Black Forest Labs, who may keep the photos and use
    /// them to improve their models (closet compliance/IN_APP_PRIVACY_TEXT.md, Phase 33a).
    public static let currentVersion = "tryon-1"

    public var version: String
    public var agreedAt: Date

    public init(version: String = TryOnConsent.currentVersion, agreedAt: Date) {
        self.version = version
        self.agreedAt = agreedAt
    }

    public var isCurrent: Bool { version == Self.currentVersion }
}

/// Where her try-on consent is kept.
public protocol TryOnConsentStore: ErasableStore {
    func current() -> TryOnConsent?
    /// `nil` withdraws it.
    func save(_ consent: TryOnConsent?)
}

/// Consent in memory: previews, tests and the debug sample closet.
public final class InMemoryTryOnConsentStore: TryOnConsentStore {
    private let state: Mutex<TryOnConsent?>

    public init(_ consent: TryOnConsent? = nil) {
        state = Mutex(consent)
    }

    public func current() -> TryOnConsent? { state.withLock { $0 } }
    public func save(_ consent: TryOnConsent?) { state.withLock { $0 = consent } }
    public func eraseAll() async throws(StoreError) { state.withLock { $0 = nil } }
}

/// One garment photo exactly as it left the phone.
public struct SentGarment: Hashable, Sendable, Codable {
    public var garmentID: Garment.ID
    public var category: GarmentCategory
    public var subKind: GarmentSubKind?
    /// The JPEG that was sent, kept on the phone so "See what was sent" shows exactly it.
    public var image: PhotoReference

    public init(garmentID: Garment.ID, category: GarmentCategory, subKind: GarmentSubKind?, image: PhotoReference) {
        self.garmentID = garmentID
        self.category = category
        self.subKind = subKind
        self.image = image
    }
}

/// What left the phone for one try-on picture: the faceless photo on the studio backdrop and the
/// garment photos, kept as the exact bytes that were sent ("See what was sent", Phase 33a).
///
/// Data tier: **Sensitive** (her body, without her face). Stays on the phone with the picture.
public struct TryOnSent: Hashable, Sendable, Codable {
    public var person: PhotoReference
    public var garments: [SentGarment]

    public init(person: PhotoReference, garments: [SentGarment]) {
        self.person = person
        self.garments = garments
    }

    public var imageReferences: [PhotoReference] { [person] + garments.map(\.image) }
}

/// Where her head and body were in the prepared photo, in its pixels (origin top left), so the
/// phone can put her head back where the dressed picture has her neck and shoulders.
public struct TryOnGeometry: Hashable, Sendable, Codable {
    public struct Point: Hashable, Sendable, Codable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public var width: Int
    public var height: Int
    /// Her face's box: x, y, width, height.
    public var face: [Double]
    public var neck: Point?
    public var leftShoulder: Point?
    public var rightShoulder: Point?

    public init(
        width: Int, height: Int, face: [Double], neck: Point? = nil, leftShoulder: Point? = nil,
        rightShoulder: Point? = nil
    ) {
        self.width = width
        self.height = height
        self.face = face
        self.neck = neck
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
    }
}

/// The files only the phone needs to put her head back: her photo on the studio backdrop with her
/// real head, her outline and the grey head shape. Never sent. Removed once the picture is made.
public struct TryOnWorkFiles: Hashable, Sendable, Codable {
    public var studio: PhotoReference
    public var matte: PhotoReference
    public var head: PhotoReference

    public init(studio: PhotoReference, matte: PhotoReference, head: PhotoReference) {
        self.studio = studio
        self.matte = matte
        self.head = head
    }

    public var imageReferences: [PhotoReference] { [studio, matte, head] }
}

/// A try-on ready to send: checked on the phone (one person, her face found and fully covered by
/// the grey shape, the room replaced), with the files kept so a job resumed after a relaunch sends
/// exactly the same request with the same key.
public struct TryOnUpload: Hashable, Sendable, Codable {
    public var sent: TryOnSent
    public var work: TryOnWorkFiles?
    public var geometry: TryOnGeometry
    /// Names this request's version, never its content.
    public var contextRevision: String

    public init(sent: TryOnSent, work: TryOnWorkFiles?, geometry: TryOnGeometry, contextRevision: String) {
        self.sent = sent
        self.work = work
        self.geometry = geometry
        self.contextRevision = contextRevision
    }

    public var imageReferences: [PhotoReference] { sent.imageReferences + (work?.imageReferences ?? []) }
}

/// The request to the backend, with the bytes that leave the phone. Only the faceless photo and
/// the garment photos, plus each garment's ID, category and kind (the prompt is built on the
/// server from those alone).
public struct TryOnCall: Sendable, Equatable {
    public struct Garment: Sendable, Equatable {
        public var id: Models.Garment.ID
        public var category: GarmentCategory
        public var subKind: GarmentSubKind?
        public var jpeg: Data

        public init(id: Models.Garment.ID, category: GarmentCategory, subKind: GarmentSubKind?, jpeg: Data) {
            self.id = id
            self.category = category
            self.subKind = subKind
            self.jpeg = jpeg
        }
    }

    public var contextRevision: String
    public var consentVersion: String
    /// The faceless photo on the studio backdrop, JPEG.
    public var person: Data
    public var garments: [Garment]

    public init(contextRevision: String, consentVersion: String, person: Data, garments: [Garment]) {
        self.contextRevision = contextRevision
        self.consentVersion = consentVersion
        self.person = person
        self.garments = garments
    }

    /// At most this many garment photos in one picture (the provider takes ten images in all).
    public static let maximumGarments = 9
    /// The largest faceless photo the backend takes (contract limits.tryOn).
    public static let personMaxBytes = 1_500_000
    /// The largest garment photo the backend takes (contract limits.tryOn).
    public static let garmentMaxBytes = 400_000
    /// The largest garment photo the phone sends: smaller than the backend's limit, so the faceless
    /// photo and nine garments at their largest still fit in one body.
    public static let garmentSendBytes = 340_000

    /// A short revision of what is sent. Names nothing of hers.
    public static func revision(person: Data, garments: [Data]) -> String {
        var hasher = SHA256()
        hasher.update(data: person)
        for garment in garments { hasher.update(data: garment) }
        return "rev_" + hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// A tiny made-up request for the debug limits screen and tests: a grey square for the person
    /// and one blue square for a top. No photo of anyone.
    public static func sample(note: String = "sample") -> TryOnCall {
        let person = Data(base64Encoded: samplePersonJPEG, options: .ignoreUnknownCharacters) ?? Data()
        let top = Data(base64Encoded: sampleGarmentJPEG, options: .ignoreUnknownCharacters) ?? Data()
        return TryOnCall(
            contextRevision: "rev_"
                + String(note.unicodeScalars.map { String($0.value, radix: 16) }.joined().prefix(12)),
            consentVersion: TryOnConsent.currentVersion, person: person,
            garments: [Garment(id: .init("g-sample-top"), category: .top, subKind: .blouse, jpeg: top)])
    }

    /// An 8 by 10 grey JPEG.
    static let samplePersonJPEG = """
        /9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQA
        AAABAAAACKADAAQAAAABAAAACgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmA
        CZjs+EJ+/8AAEQgACgAIAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQE
        AAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldY
        WVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk
        5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMR
        BAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdo
        aWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz
        9PX29/j5+v/bAEMABAQEBAQEBgQEBgkGBgYJDAkJCQkMDwwMDAwMDxIPDw8PDw8SEhISEhISEhUVFRUVFRkZGRkZHBwcHBwcHBwc
        HP/bAEMBBAUFBwcHDAcHDB0UEBQdHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHf/dAAQA
        Af/aAAwDAQACEQMRAD8AKKKKAP/Z
        """

    /// An 8 by 8 blue JPEG.
    static let sampleGarmentJPEG = """
        /9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQA
        AAABAAAACKADAAQAAAABAAAACAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmA
        CZjs+EJ+/8AAEQgACAAIAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQE
        AAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldY
        WVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk
        5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMR
        BAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdo
        aWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz
        9PX29/j5+v/bAEMABAQEBAQEBgQEBgkGBgYJDAkJCQkMDwwMDAwMDxIPDw8PDw8SEhISEhISEhUVFRUVFRkZGRkZHBwcHBwcHBwc
        HP/bAEMBBAUFBwcHDAcHDB0UEBQdHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHR0dHf/dAAQA
        Af/aAAwDAQACEQMRAD8A+faKKK/Vj50//9k=
        """
}

/// Why the phone wouldn't send a try-on. Nothing left the phone in every case (fail closed).
public enum TryOnPrepareProblem: Error, Hashable, Sendable {
    /// She hasn't set up a try-on photo.
    case noTryOnPhoto
    /// The photo couldn't be read.
    case photoUnreadable
    /// No person in the photo.
    case noPerson
    /// No face was found, so the phone can't be sure it's hidden.
    case noFace
    /// More than one person or face.
    case severalPeople
    /// The outline of her body isn't clear enough to trust.
    case unclearOutline
    /// The grey didn't fully cover her face, or a face could still be found after it.
    case faceStillVisible
    /// The phone couldn't run its checks (Apple Vision failed).
    case checksUnavailable
    /// None of the look's pieces has a photo to send.
    case noGarmentPhotos
    /// The files couldn't be written (no space).
    case notSaved
}

/// Makes real try-on pictures (Phase 33a): prepares the faceless upload on the phone, has the
/// backend dress it as a paid job, then puts her head back on the phone. `Services` has the one
/// built on Apple Vision and the photo files; tests use their own.
public protocol TryOnPipeline: Sendable {
    /// On the phone, before anything is sent: masks her head, swaps the room for the backdrop,
    /// checks that no face can be found any more, and writes the files. Throws instead of
    /// sending anything when any check fails.
    func prepare(photo: PhotoReference, pieces: [Garment]) async throws(TryOnPrepareProblem) -> TryOnUpload
    /// Sends the upload as one paid action with the job's key, and returns the dressed picture.
    func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String)
        async throws(CloudLimitProblem) -> Data
    /// On the phone: puts her real head back over the grey and writes the finished picture.
    func restore(_ dressed: Data, upload: TryOnUpload) async throws(TryOnError) -> PhotoReference
    /// Removes files written for an upload: the work files always, the sent ones too unless a
    /// picture keeps them.
    func discard(_ upload: TryOnUpload, keepingSent: Bool) async
}

/// A try-on job as it is kept (27c): the look as it was, the upload's files and her consent, so a
/// job resumed after a relaunch sends the same body with the same key.
public struct TryOnJobRequest: Hashable, Sendable, Codable {
    /// The picture's look, saved before the job starts.
    public var look: Look
    public var upload: TryOnUpload
    public var consentVersion: String

    public init(look: Look, upload: TryOnUpload, consentVersion: String) {
        self.look = look
        self.upload = upload
        self.consentVersion = consentVersion
    }
}
