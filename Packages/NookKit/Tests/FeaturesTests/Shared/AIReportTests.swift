import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// Gives the same bytes for any photo, so a test can see the picture go (or not).
private struct FixedImages: ImageProvider {
    static let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
    func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? { Self.bytes }
}

/// Release (App Review Guideline 1.2): Report a problem on an AI result. A reason first; the
/// result's IDs and no picture unless she ticks it; sent once even if sent again; a failure keeps
/// the report; hiding is her choice; and Not now on signing in sends nothing.
@MainActor
struct AIReportModelTests {
    private let actionID = "act_0f1e2d3c4b5a69788796a5b4c3d2e1f0"

    private func services(_ feedback: ScriptedFeedbackService) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.feedback = feedback
        services.images = FixedImages()
        services.screenshots = ScriptedScreenshots()
        return services
    }

    private var pictureTarget: AIReportTarget {
        AIReportTarget(
            subject: .tryOnPicture, resultID: actionID, actionID: actionID, madeBy: .cloud, madeAt: TestTime.now,
            picture: .stored("photo-1"))
    }

    @Test func aReasonComesFirstThenTheResultsIDsGoWithNoPicture() async throws {
        let feedback = ScriptedFeedbackService()
        let model = AIReportModel(target: pictureTarget, canHide: true)
        #expect(model.offersPicture && !model.includesPicture)
        #expect(await model.send(with: services(feedback), signIn: .notNeeded) == false)
        #expect(model.needsReason)
        #expect(await feedback.reportSubmissions().isEmpty)

        model.reason = .looksWrongOnMe
        model.note = "  The sleeves are wrong.  "
        #expect(await model.send(with: services(feedback), signIn: .notNeeded))
        let sent = try #require(await feedback.reportSubmissions().first)
        #expect(sent.report.reason == .looksWrongOnMe)
        #expect(sent.report.note == "The sleeves are wrong.")
        #expect(sent.report.target.resultID == actionID)
        #expect(sent.report.target.actionID == actionID)
        #expect(sent.report.picture == nil)
        #expect(sent.report.hidden == false)
        guard case .sent(let receipt) = model.phase else {
            Issue.record("not sent: \(model.phase)")
            return
        }
        #expect(receipt.reference == "NK-0000BBBB")
    }

    @Test func thePictureGoesOnlyWhenSheTicksIt() async throws {
        let feedback = ScriptedFeedbackService()
        let model = AIReportModel(target: pictureTarget, canHide: false)
        model.reason = .wrongOrOffensive
        model.includesPicture = true
        #expect(await model.send(with: services(feedback), signIn: .notNeeded))
        let sent = try #require(await feedback.reportSubmissions().first)
        #expect(sent.report.picture?.data == FixedImages.bytes)
        // A look has no picture to include, whatever is set.
        let look = AIReportTarget(
            subject: .look, resultID: "r-1", madeBy: .cloud, madeAt: TestTime.now, picture: .stored("x"))
        #expect(look.picture == nil)
        #expect(!AIReportModel(target: look, canHide: true).offersPicture)
    }

    @Test func aPictureOffersOnlyItsFacelessCopyNeverTheOneWithHerFace() {
        // F1 (D12): the finished picture has her face; the report includes the copy without it.
        let look = Look(id: "l-1", pieces: [], createdAt: TestTime.now)
        var picture = TryOnPicture(
            id: "t-1", of: look, image: .generated(.stored("finished")), createdAt: TestTime.now,
            faceless: .stored("faceless"))
        #expect(AIReportTarget.picture(picture).picture == .stored("faceless"))
        picture.faceless = nil
        #expect(AIReportTarget.picture(picture).picture == nil)
        #expect(!AIReportModel(target: .picture(picture), canHide: true).offersPicture)
    }

    @Test func aFailureKeepsTheReportAndSendingAgainUsesTheSameSubmission() async throws {
        let feedback = ScriptedFeedbackService(results: [.failure(.offline), .success(nil)])
        let model = AIReportModel(target: pictureTarget, canHide: true)
        model.reason = .notMyClothes
        model.hides = true
        #expect(await model.send(with: services(feedback), signIn: .notNeeded) == false)
        #expect(model.problem == .offline)
        #expect(model.phase == .writing)
        #expect(model.reason == .notMyClothes)
        #expect(await model.send(with: services(feedback), signIn: .notNeeded))
        let both = await feedback.reportSubmissions()
        #expect(both.count == 2)
        #expect(both[0].id == both[1].id)
        #expect(both[1].report.hidden)
    }

    @Test func notNowOnSigningInSendsNothing() async {
        let feedback = ScriptedFeedbackService()
        let model = AIReportModel(target: pictureTarget, canHide: true)
        model.reason = .other
        let check = SignInCheck { reason in
            #expect(reason == .report)
            return false
        }
        #expect(await model.send(with: services(feedback), signIn: check) == false)
        #expect(model.phase == .writing)
        #expect(await feedback.reportSubmissions().isEmpty)
    }

    @Test func aLooksReportOffersTheWhyLineAndNamesTheVersion() async throws {
        let feedback = ScriptedFeedbackService()
        let look = Look(
            id: "l-1", resultID: StyleResult.ID(actionID), version: .dressedUp, pieces: [], createdAt: TestTime.now)
        let result = StyleResult(
            id: StyleResult.ID(actionID), requestID: "req-1", versions: [look], createdAt: TestTime.now)
        let model = AIReportModel(target: .look(look, result: result), subjects: [.look, .why], canHide: true)
        #expect(model.subject == .look)
        model.subject = .why
        model.reason = .wrongOrOffensive
        #expect(await model.send(with: services(feedback), signIn: .notNeeded))
        let sent = try #require(await feedback.reportSubmissions().first).report.target
        #expect(sent.subject == .why)
        #expect(sent.lookVersion == .dressedUp)
        #expect(sent.actionID == actionID)
        #expect(sent.madeBy == .cloud)
    }
}

/// Release: hiding a reported stylist result on Your looks.
@MainActor
struct HideReportedResultTests {
    @Test func hidingRemovesTheUnsavedLooksAndTheNextOutfitAvoidsThem() async throws {
        let stylist = ScriptedStylist()
        var services = yourLooksServices(stylist: stylist)
        services.cloudStyling = true
        services.stylistConsent = InMemoryStylistConsentStore(StylistConsent(agreedAt: TestTime.now))
        let model = await styledLooks(services: services)
        let result = try #require(model.result)
        let saved = try #require(result.versions.first)
        _ = try await model.toggleSave(saved, name: "Keep me")
        await model.hideResult()
        #expect(model.status == .failed(.hidden))
        #expect(model.result == nil)
        let ids = Set(try await services.looks.looks().map(\.id))
        #expect(ids.contains(saved.id))
        for look in result.versions.dropFirst() { #expect(!ids.contains(look.id)) }
        // Try a different outfit asks again, for new ideas.
        model.retry()
        await model.settle()
        #expect(await stylist.calls == 2)
        #expect(model.status == .showing)
    }
}
