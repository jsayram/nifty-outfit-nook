import Foundation
import Models
import NookTestSupport

/// Builds test records with short IDs.
enum Make {
    static func garment(
        _ id: Garment.ID,
        _ category: GarmentCategory,
        colors: [ColorName] = [],
        occasions: Set<Occasion> = [.office],
        dressiness: Dressiness = .smart,
        ownership: Ownership = .owned,
        laundry: LaundryState = .clean
    ) -> Garment {
        Garment(
            id: id,
            name: "Piece \(id)",
            category: category,
            colors: colors,
            dressiness: dressiness,
            occasions: occasions,
            ownership: ownership,
            laundry: laundry,
            addedAt: TestTime.day(-30)
        )
    }

    static func look(
        _ id: Look.ID,
        version: LookVersion? = .simple,
        garments: [Garment.ID],
        idea: PieceIdea? = nil,
        sameAsSimple: Set<Garment.ID>? = nil,
        wornOn: [Date] = []
    ) -> Look {
        var pieces = garments.map { garmentID in
            LookPiece(
                id: LookPiece.ID("\(id)-\(garmentID)"),
                content: .garment(garmentID),
                isSameAsSimple: sameAsSimple?.contains(garmentID) ?? (version != nil)
            )
        }
        if let idea { pieces.append(LookPiece(id: LookPiece.ID("\(id)-idea"), content: .idea(idea))) }
        return Look(id: id, version: version, pieces: pieces, wornOn: wornOn, createdAt: TestTime.now)
    }

    static func request(
        source: WardrobeSource = .mainCloset,
        occasion: Occasion = .office,
        pieceMode: PieceMode = .mineAndOneIdea,
        repeatWindow: RepeatWindow = .oneWeek,
        tracksLaundry: Bool = false,
        startingPieceID: Garment.ID? = nil
    ) -> StyleRequest {
        StyleRequest(
            id: "req-1",
            source: source,
            occasion: occasion,
            preferences: Preferences(pieceMode: pieceMode, repeatWindow: repeatWindow, tracksLaundry: tracksLaundry),
            startingPieceID: startingPieceID,
            createdAt: TestTime.now
        )
    }
}
