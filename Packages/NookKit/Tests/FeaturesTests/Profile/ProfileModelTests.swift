import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Profile and Fit and measurements (Phase 14a): the sign name reaching Home (RD-03.1), the usual
/// Style Me choices, measurements in either unit, the pieces that fit her well and the try-on
/// photo. Measurements here are made up.
@MainActor
struct ProfileModelTests {
    private let now = TestTime.now
    private let us = Locale(identifier: "en_US")

    private func services(_ set: FixtureSet = .demo, behavior: FixtureBehavior = .normal) -> NookServices {
        FixtureServices.make(set: set, behavior: behavior, now: now, calendar: TestTime.calendar)
    }

    private func loaded(_ services: NookServices, locale: Locale? = nil) async -> ProfileModel {
        let model = ProfileModel()
        await model.load(from: services, locale: locale ?? us)
        return model
    }

    // MARK: Name on your sign (RD-03)

    @Test func loadsTheDemoProfile() async {
        let model = await loaded(services())
        #expect(model.phase == .loaded)
        #expect(model.profile.signName == "Lily")
        #expect(model.profile.preferences == Preferences())
        // The demo has the example try-on photo, the person its sample pictures show.
        #expect(model.hasTryOnPhoto)
    }

    @Test func aNewNameReachesTheSignOnHome() async throws {
        // RD-03.1: Home reads the store each time Profile closes, so the sign shows the new name.
        let services = services()
        let model = await loaded(services)
        #expect(await model.saveName("  Rosa ", in: services) == "Rosa")
        #expect(model.profile.signName == "Rosa")
        #expect(try await services.profile.profile().signName == "Rosa")
        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.signName == "Rosa")
        #expect(RoomControl.nameSign.accessibilityLabel(for: home.content) == "Name sign: Rosa")
    }

    @Test func anEmptyNameShowsHello() async {
        // RD-03.2: never a blank plate.
        let services = services()
        let model = await loaded(services)
        #expect(await model.saveName("   ", in: services) == "")
        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.signName == "")
        #expect(SignName.shown(home.content.signName ?? "") == "Hello")
        #expect(ProfileText.signSays(SignName.shown("")) == "Your sign now says Hello.")
        #expect(ProfileText.spokenSign("") == "Name on your sign, no name yet")
    }

    @Test func aNameThatBreaksTheRulesIsNotSaved() async throws {
        let services = services()
        let model = await loaded(services)
        let long = String(repeating: "a", count: NameRules.signNameMaximum + 1)
        #expect(model.nameProblem(long) == .tooLong(maximum: 20))
        #expect(model.nameProblem("Two\nlines") == .controlCharacters)
        #expect(model.nameProblem("") == nil)
        #expect(await model.saveName(long, in: services) == nil)
        #expect(try await services.profile.profile().signName == "Lily")
        #expect(ProfileText.nameProblem(.tooLong(maximum: 20)) == "Use 20 characters or fewer.")
    }

    // MARK: Style Me's usual choices

    @Test func preferencesRepeatsAndUsualFitSave() async throws {
        // LR-03, LR-10, LR-18: saved until she changes them.
        let services = services()
        let model = await loaded(services)
        #expect(await model.setPieceMode(.onlyMine, in: services))
        #expect(await model.setRepeatWindow(.twoWeeks, in: services))
        #expect(await model.setUsualFit(.fitted, in: services))
        let stored = try await services.profile.profile()
        #expect(stored.preferences.pieceMode == .onlyMine)
        #expect(stored.preferences.repeatWindow == .twoWeeks)
        #expect(stored.usualFit == .fitted)
        // Track laundry and the remembered source are left as they were.
        #expect(stored.preferences.tracksLaundry == Preferences().tracksLaundry)
        #expect(stored.remembered == RememberedChoices())
        #expect(model.profile.preferences.repeatWindow.title == "2 weeks")
    }

    @Test func styleMeStartsFromTheSavedPreferences() async {
        let services = services()
        let model = await loaded(services)
        #expect(await model.setPieceMode(.onlyMine, in: services))
        let styleMe = StyleMeModel()
        await styleMe.load(from: services, now: now)
        #expect(styleMe.draft.pieceMode == .onlyMine)
    }

    @Test func aSettingChangedElsewhereIsntOverwritten() async throws {
        // Each change reads the store first, so Track laundry turned on in Laundry stays on.
        let services = services()
        let model = await loaded(services)
        try await services.profile.update { $0.preferences.tracksLaundry = true }
        #expect(await model.setRepeatWindow(.noLimit, in: services))
        #expect(try await services.profile.profile().preferences.tracksLaundry)
    }

    // MARK: Units

    @Test func unitsFollowTheRegionUntilShePicks() async throws {
        let services = services()
        #expect(await loaded(services, locale: us).units == .imperial)
        let model = await loaded(services, locale: Locale(identifier: "de_DE"))
        #expect(model.units == .metric)
        #expect(await model.setUnits(.imperial, in: services))
        #expect(model.units == .imperial)
        #expect(try await services.profile.profile().units == .imperial)
    }

    // MARK: Measurements

    @Test func aMeasurementIsSavedInTheUnitsSheTypedAndShownInEither() async throws {
        let services = services()
        let model = await loaded(services)
        var form = MeasurementForm(field: .waist, measurements: model.profile.measurements, units: .metric, locale: us)
        #expect(!form.hadValue)
        form.text = "68"
        guard case .length(let waist) = try form.value(locale: us) else {
            Issue.record("Waist isn't a length")
            return
        }
        #expect(await model.save(waist, for: .waist, in: services))
        #expect(try await services.profile.profile().measurements.waist == Length(68, .centimeters))
        let metric = MeasurementFormat.shown(.waist, in: model.profile.measurements, units: .metric, locale: us)
        #expect(metric == MeasurementFormat.Shown(text: "68 cm", spoken: "68 centimeters"))
        let imperial = MeasurementFormat.shown(.waist, in: model.profile.measurements, units: .imperial, locale: us)
        #expect(imperial == MeasurementFormat.Shown(text: "27 in", spoken: "27 inches"))
        // Opening it again in inches shows the value converted, to the nearest half inch.
        let reopened = MeasurementForm(
            field: .waist, measurements: model.profile.measurements, units: .imperial, locale: us)
        #expect(reopened.hadValue)
        #expect(reopened.text == "27")
    }

    @Test func heightInFeetAndInches() async throws {
        let services = services()
        let model = await loaded(services)
        var form = MeasurementForm(field: .height, measurements: BodyMeasurements(), units: .imperial, locale: us)
        #expect(form.usesFeetAndInches)
        form.feet = "4"
        form.inches = "11"
        #expect(try form.value(locale: us) == .length(Length(59, .inches)))
        #expect(await model.save(Length(59, .inches), for: .height, in: services))
        let shown = MeasurementFormat.shown(.height, in: model.profile.measurements, units: .imperial, locale: us)
        #expect(shown == MeasurementFormat.Shown(text: "4′ 11″", spoken: "4 feet 11 inches"))
        let reopened = MeasurementForm(
            field: .height, measurements: model.profile.measurements, units: .imperial, locale: us)
        #expect(reopened.feet == "4")
        #expect(reopened.inches == "11")
        #expect(
            MeasurementFormat.shown(.height, in: model.profile.measurements, units: .metric, locale: us)?.text
                == "150 cm")
    }

    @Test func weightAndTheGermanDecimalComma() throws {
        let germany = Locale(identifier: "de_DE")
        let measurements = BodyMeasurements(weight: Weight(130, .pounds))
        let form = MeasurementForm(field: .weight, measurements: measurements, units: .metric, locale: germany)
        #expect(form.text == "59")
        var typed = form
        typed.text = "58,5"
        #expect(try typed.value(locale: germany) == .weight(Weight(58.5, .kilograms)))
        let shown = MeasurementFormat.shown(
            .weight, in: BodyMeasurements(weight: Weight(58.5, .kilograms)), units: .metric, locale: germany)
        #expect(shown?.text == "58,5 kg")
    }

    @Test func invalidValuesAreRefusedWithWordsInHerUnits() throws {
        var form = MeasurementForm(field: .waist, measurements: BodyMeasurements(), units: .imperial, locale: us)
        form.text = "abc"
        #expect(throws: EntryProblem.notANumber) { try form.value(locale: us) }
        #expect(
            FitText.problem(.notANumber, field: .waist, units: .imperial)
                == "Enter a number of inches between 15 and 70, or leave it empty.")
        #expect(
            FitText.problem(.outOfRange, field: .weight, units: .metric)
                == "Enter a number of kilograms between 23 and 317, or leave it empty.")
        // An empty box clears the value rather than saving zero.
        form.text = ""
        #expect(try form.value(locale: us) == .length(nil))
    }

    @Test func theStoreRefusesAnImpossibleValueToo() async throws {
        // The sheet checks first, but the store checks again (defence in depth).
        let services = services()
        let model = await loaded(services)
        #expect(!(await model.save(Length(500, .inches), for: .waist, in: services)))
        #expect(try await services.profile.profile().measurements.waist == nil)
    }

    @Test func clearingAMeasurementLeavesItEmpty() async throws {
        let services = services()
        let model = await loaded(services)
        #expect(await model.save(weight: Weight(130, .pounds), in: services))
        #expect(await model.clear(.weight, in: services))
        #expect(try await services.profile.profile().measurements.isEmpty)
        #expect(MeasurementFormat.shown(.weight, in: model.profile.measurements, units: .imperial, locale: us) == nil)
    }

    // MARK: Pieces that fit you well (LR-13)

    @Test func addRemoveAndUndoAFittingPiece() async throws {
        let services = services()
        let model = await loaded(services)
        let before = model.profile.fitPieces
        let piece = FitPiece(id: "f-new", brand: "Demo Brand", category: .bottom, sizeLabel: "0 Petite")
        #expect(await model.add(piece, in: services))
        #expect(model.profile.fitPieces.last == piece)
        // LR-13.2: brand, size and fit in one line.
        #expect(FitPage.line(for: piece) == "Demo Brand · Bottom · 0 Petite · Fits well")
        let removed = try #require(await model.remove(piece.id, in: services))
        #expect(model.profile.fitPieces == before)
        #expect(await model.restore(removed, in: services))
        #expect(try await services.profile.profile().fitPieces == before + [piece])
    }

    @Test func aFittingPieceNeedsABrandAndASize() {
        #expect(ProfileModel.problems(brand: "Demo Brand", size: "S") == nil)
        #expect(ProfileModel.problems(brand: " ", size: "S")?.brand == .empty)
        #expect(ProfileModel.problems(brand: "Demo", size: "")?.size == .empty)
        let long = String(repeating: "b", count: 41)
        #expect(ProfileModel.problems(brand: long, size: "S")?.brand == .tooLong(maximum: 40))
    }

    // MARK: Your try-on photo (RD-06)

    @Test func theExamplePhotoAndRemovingItKeepsPictures() async throws {
        let services = services()
        let model = await loaded(services)
        let pictures = try await services.pictures.pictures()
        #expect(await model.removePhoto(in: services))
        #expect(!model.hasTryOnPhoto)
        #expect(await model.useExamplePhoto(in: services))
        #expect(model.hasTryOnPhoto)
        #expect(try await services.profile.profile().tryOnPhoto == ProfileModel.exampleTryOnPhoto)
        #expect(await model.removePhoto(in: services))
        #expect(!model.hasTryOnPhoto)
        #expect(try await services.profile.profile().tryOnPhoto == nil)
        // PRD §9.2.1: removing the photo never removes saved try-on pictures.
        #expect(try await services.pictures.pictures() == pictures)
    }

    // MARK: States

    @Test func aStoreThatFailsShowsTheErrorAndSavesNothing() async {
        let services = services(behavior: .storesFail)
        let model = await loaded(services)
        #expect(model.phase == .failed)
        #expect(await model.saveName("Rosa", in: services) == nil)
        #expect(!(await model.setRepeatWindow(.twoWeeks, in: services)))
    }

    @Test func aFreshInstallHasNoNameAndTheDefaults() async {
        let model = await loaded(services(.empty))
        #expect(model.profile.signName == "")
        #expect(model.profile.preferences.repeatWindow == .oneWeek)
        #expect(model.profile.preferences.pieceMode == .mineAndOneIdea)
        #expect(model.profile.measurements.isEmpty)
        #expect(model.profile.fitPieces.isEmpty)
    }
}
