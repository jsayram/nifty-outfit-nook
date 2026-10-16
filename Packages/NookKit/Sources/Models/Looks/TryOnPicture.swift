import Foundation

/// A try-on picture of one look (RD-06, RD-08): the only image of her wearing clothes, made only
/// when she taps Try it on. Every one is labelled Simulated (RD-04.2).
///
/// Data tier: **Sensitive** (DATA_MAP.md, "Try-on pictures"). A real one is a picture of her, so
/// it stays on the phone and in her iCloud, and the app hides it in the app switcher. Stage A only
/// has the simulated picture, drawn on the phone from the look's pieces with no person in it;
/// generated pictures wait for Phase 33's gates.
///
/// A picture keeps the look as it was when it was made (`captured`, PRD §9.2.1 step 6). The look
/// can change or leave Saved Looks later, and the picture stays as it was until she deletes it
/// (PRD §7.5, §9.2.4: no automatic purge of retained pictures).
public struct TryOnPicture: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<TryOnPicture>

    public let id: ID
    /// The look it was made from.
    public var lookID: Look.ID
    /// The look when the picture was made.
    public var captured: CapturedLook
    public var image: TryOnImage
    public var createdAt: Date

    public init(id: ID, lookID: Look.ID, captured: CapturedLook, image: TryOnImage, createdAt: Date) {
        self.id = id
        self.lookID = lookID
        self.captured = captured
        self.image = image
        self.createdAt = createdAt
    }

    /// A picture of `look` as it is now.
    public init(id: ID, of look: Look, image: TryOnImage, createdAt: Date) {
        self.init(id: id, lookID: look.id, captured: CapturedLook(look), image: image, createdAt: createdAt)
    }
}

/// A look as it was when a try-on picture was made: what the picture shows, and what search on
/// the Pictures tab finds it by once the look has changed or gone.
public struct CapturedLook: Hashable, Sendable, Codable {
    public var pieces: [LookPiece]
    /// The look's name then, if it had one.
    public var name: String?
    public var occasion: Occasion?

    public init(pieces: [LookPiece], name: String? = nil, occasion: Occasion? = nil) {
        self.pieces = pieces
        self.name = name
        self.occasion = occasion
    }

    public init(_ look: Look) {
        self.init(pieces: look.pieces, name: look.name, occasion: look.occasion)
    }
}

/// What a try-on picture's image is.
public enum TryOnImage: Hashable, Sendable, Codable {
    /// Stage A: drawn on the phone from the captured pieces on a plain backdrop. No person, no
    /// photo of her, nothing sent anywhere.
    case simulated
    /// A generated picture in the app's picture store (Phase 33). Still labelled Simulated.
    case generated(PhotoReference)
}
