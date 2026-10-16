import Foundation

// What every store checks before it keeps a record. The rules are the pure functions in
// `NameRules`, `GarmentRules` and `MeasurementRules`; these put them together the way a store
// needs them and turn their problems into `StoreError`. Stage A's in-memory stores call them, and
// Stage B's real stores call the same ones, so a record refused by one is refused by the other.
// The store contract tests check it (`StoreContracts` in NookTestSupport).

/// The checks a store runs on save. Each returns the record as it should be kept (names trimmed)
/// or throws the `StoreError` the store should throw.
public enum StoreValidation {
    /// A garment: its name (`NameRules.garmentName`) and its other text fields (`GarmentRules`).
    public static func garment(_ garment: Garment) throws(StoreError) -> Garment {
        var garment = garment
        do {
            garment.name = try NameRules.garmentName(garment.name)
        } catch {
            throw .invalidName(error)
        }
        let problems = GarmentRules.problems(in: garment)
        if !problems.isEmpty { throw .invalidDetails(problems) }
        return garment
    }

    /// A look. A named look needs a valid name; unnamed looks (unsaved results) are fine.
    public static func look(_ look: Look) throws(StoreError) -> Look {
        guard let name = look.name else { return look }
        var look = look
        do {
            look.name = try NameRules.lookName(name)
        } catch {
            throw .invalidName(error)
        }
        return look
    }

    /// A suitcase's name, which must be unique among `others` (`NameRules.suitcaseName`).
    /// `renaming` is the suitcase being changed, so its own name doesn't count as taken.
    public static func suitcaseName(
        _ name: String, among others: [Suitcase], renaming: Suitcase.ID?
    ) throws(StoreError) -> String {
        do {
            return try NameRules.suitcaseName(name, among: others, renaming: renaming)
        } catch {
            throw .invalidName(error)
        }
    }

    /// The profile: the sign name, each fitting piece and the measurements.
    public static func profile(_ profile: Profile) throws(StoreError) -> Profile {
        var profile = profile
        do {
            profile.signName = try NameRules.signName(profile.signName)
            profile.fitPieces = try profile.fitPieces.map { piece throws(NameProblem) in
                try MeasurementRules.checkedFitPiece(piece)
            }
        } catch {
            throw .invalidName(error)
        }
        let problems = MeasurementRules.problems(in: profile.measurements)
        guard problems.isEmpty else { throw .invalidMeasurements(problems) }
        return profile
    }
}
