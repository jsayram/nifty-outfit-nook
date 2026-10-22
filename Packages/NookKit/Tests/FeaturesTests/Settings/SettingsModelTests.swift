import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Phase 14b: the Track laundry switch, Send feedback's note, and Delete my data.
@MainActor
struct TrackLaundryTests {
    private func services(laundry: FixtureLaundryState? = nil, behavior: FixtureBehavior = .normal) -> NookServices {
        FixtureServices.make(
            set: .demo, behavior: behavior, laundry: laundry, now: TestTime.now,
            calendar: TestTime.calendar)
    }

    private func loaded(_ services: NookServices) async -> ProfileModel {
        let model = ProfileModel()
        await model.load(from: services, locale: Locale(identifier: "en_US"))
        return model
    }

    @Test func profileCountsTheKeptDirtyMarks() async {
        // The demo has tracking off with two pieces still marked as in the wash (RD-11).
        let model = await loaded(services())
        #expect(!model.profile.preferences.tracksLaundry)
        #expect(model.keptDirtyCount == 2)
        #expect(
            ProfileText.laundryDetail(isOn: false, kept: 2)
                == "Every piece counts as available. Your 2 dirty marks are kept.")
        #expect(ProfileText.laundryDetail(isOn: false, kept: 1).contains("Your 1 dirty mark is kept."))
        #expect(ProfileText.laundryDetail(isOn: false, kept: 0) == "Every piece counts as available.")
        #expect(
            ProfileText.laundryDetail(isOn: true, kept: 2) == "Style Me skips pieces in the wash until they’re clean.")
    }

    @Test func turningItOnBringsTheMarksBackOnHomeAndCloset() async throws {
        // RD-11.2 and RD-11.4: the hamper and Closet's Laundry tile follow at once.
        let services = services()
        let model = await loaded(services)
        #expect(await model.setTracksLaundry(true, in: services))
        #expect(try await services.profile.profile().preferences.tracksLaundry)
        #expect(
            ProfileText.laundryToast(isOn: true, kept: 2) == "Laundry tracking is on. 2 pieces are back in the wash.")

        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.hamper == .toWash(2))
        let closet = ClosetModel()
        await closet.load(from: services, now: TestTime.now)
        #expect(closet.tracksLaundry)
    }

    @Test func turningItOffKeepsEveryDirtyMark() async throws {
        let services = services(laundry: .some)
        let model = await loaded(services)
        #expect(model.profile.preferences.tracksLaundry)
        let dirtyBefore = try await services.closet.garments().filter { $0.laundry == .dirty }.map(\.id)
        #expect(!dirtyBefore.isEmpty)

        #expect(await model.setTracksLaundry(false, in: services))
        #expect(!model.profile.preferences.tracksLaundry)
        #expect(
            ProfileText.laundryToast(isOn: false, kept: model.keptDirtyCount)
                == "Laundry tracking is off. Your 2 dirty marks are kept.")
        // The marks stay in the store; only their effect stops (RD-11).
        let dirtyAfter = try await services.closet.garments().filter { $0.laundry == .dirty }.map(\.id)
        #expect(dirtyAfter == dirtyBefore)

        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.hamper == .off)
        let closet = ClosetModel()
        await closet.load(from: services, now: TestTime.now)
        #expect(!closet.tracksLaundry)
        #expect(!closet.showsLaundryFilter)

        // Every piece counts for Style Me again (RD-11.2).
        let profile = try await services.profile.profile()
        let garments = try await services.closet.garments()
        for id in dirtyBefore {
            let garment = try #require(garments.first { $0.id == id })
            #expect(
                Eligibility.isEligible(
                    garment, members: nil, tracksLaundry: profile.preferences.tracksLaundry, on: TestTime.now))
        }
    }

    @Test func aSwitchThatDoesntSaveStaysAsItWas() async {
        let services = services(behavior: .storesFail)
        let model = ProfileModel()
        model.show(Profile(), locale: Locale(identifier: "en_US"))
        #expect(await !model.setTracksLaundry(true, in: services))
        #expect(!model.profile.preferences.tracksLaundry)
    }
}

@MainActor
struct FeedbackModelTests {
    private let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")

    @Test func theNoteHoldsHerWordsAndNothingElseByDefault() async throws {
        // Even with her whole profile and closet loaded elsewhere in the app, the note is built
        // from the form alone: her words and what it's about.
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let profile = try await services.profile.profile()
        let garments = try await services.closet.garments()

        let model = FeedbackModel(diagnostics: details)
        #expect(!model.includesDetails)
        model.kind = .idea
        model.message = "Could the hamper show what's in the wash?"
        let text = try #require(model.preview)
        #expect(
            text == """
                Nifty Outfit Nook feedback
                About: An idea

                Could the hamper show what's in the wash?
                """)
        // No name, no app details, no closet.
        #expect(!text.contains(profile.signName))
        #expect(!text.contains("iPhone13,2"))
        #expect(!text.contains("0.1"))
        for garment in garments.prefix(10) {
            #expect(!text.contains(garment.name))
        }
    }

    @Test func appDetailsAreAddedOnlyWhenTurnedOn() throws {
        let model = FeedbackModel(diagnostics: details)
        model.message = "Hamper didn't open"
        model.includesDetails = true
        let text = try #require(model.preview)
        #expect(
            text == """
                Nifty Outfit Nook feedback
                About: Something’s wrong

                Hamper didn't open

                App version: 0.1 (14)
                iOS: 26.5
                Device: iPhone13,2
                """)
    }

    @Test func sendSharesExactlyThePreview() throws {
        let model = FeedbackModel(diagnostics: details)
        model.message = "  Love it \n"
        let preview = try #require(model.preview)
        #expect(model.send())
        #expect(model.phase == .sharing(preview))

        // Closing the share sheet without sending keeps the note.
        model.shareFinished(completed: false)
        #expect(model.phase == .writing)
        #expect(model.message == "  Love it \n")

        // Sending it says thank you and shows what went.
        #expect(model.send())
        model.shareFinished(completed: true)
        guard case .sent(let note) = model.phase else {
            Issue.record("Not sent")
            return
        }
        #expect(note.message == "Love it")
        #expect(FeedbackComposer.text(note) == preview)

        model.startOver()
        #expect(model.phase == .writing)
        #expect(model.message.isEmpty)
        #expect(!model.includesDetails)
    }

    @Test func anEmptyNoteShowsItsProblemOnlyAfterSend() {
        let model = FeedbackModel(diagnostics: details)
        #expect(model.problem == nil)
        #expect(model.preview == nil)
        #expect(!model.send())
        #expect(model.phase == .writing)
        #expect(model.problem == .empty)
        #expect(FeedbackText.problem(.empty) == "Write a few words to send the note.")
        // It goes as she types.
        model.message = "Hi"
        #expect(model.problem == nil)
    }

    @Test func theFieldFollowsTheKind() {
        #expect(FeedbackText.messageLabel(.somethingWrong) == "What happened?")
        #expect(FeedbackText.messageLabel(.idea) == "What’s your idea?")
        #expect(FeedbackText.messageLabel(.other) == "What would you like to say?")
    }
}

@MainActor
struct DeleteDataModelTests {
    private func services(_ set: FixtureSet = .demo, behavior: FixtureBehavior = .normal) -> NookServices {
        FixtureServices.make(
            set: set, behavior: behavior, draft: .look, now: TestTime.now, calendar: TestTime.calendar)
    }

    @Test func countsWhatWillGo() async throws {
        let services = services()
        let model = DeleteDataModel()
        await model.load(from: services)
        let counts = try #require(model.counts)
        #expect(counts.pieces == (try await services.closet.garments().count))
        #expect(counts.looks == (try await services.looks.looks().count))
        #expect(counts.pictures == (try await services.pictures.pictures().count))
        #expect(counts.suitcases == (try await services.suitcases.suitcases().count))
        #expect(counts.drafts == 1)
        #expect(Set(model.parts) == Set(DataPart.allCases.filter { !$0.isRemote }))
        #expect(DeleteDataText.count(.drafts, in: counts) == "1 draft")
        #expect(DeleteDataText.count(.closet, in: counts) == "\(counts.pieces) pieces")
        #expect(DeleteDataText.count(.profile, in: counts) == nil)
    }

    @Test func deletingEverythingLeavesAFreshApp() async throws {
        let services = services()
        let model = DeleteDataModel()
        await model.load(from: services)
        #expect(await model.delete(in: services))
        #expect(model.phase == .ready)

        // What the fresh app shows: Home with Hello and an empty closet, an empty Closet.
        let home = HomeModel()
        await home.load(from: services)
        #expect(home.phase == .loaded)
        #expect(home.content.signName == "")
        #expect(home.content.hamper == .off)
        #expect(home.content.framedLooks.isEmpty)
        let closet = ClosetModel()
        await closet.load(from: services, now: TestTime.now)
        #expect(closet.phase == .loaded)
        let profile = ProfileModel()
        await profile.load(from: services, locale: Locale(identifier: "en_US"))
        #expect(profile.profile == Profile())
        #expect(profile.keptDirtyCount == 0)
    }

    @Test func aFailedDeletionSaysWhatsLeft() async {
        let services = services(behavior: .storesFail)
        let model = DeleteDataModel()
        await model.load(from: services)
        #expect(model.counts == nil)
        #expect(await !model.delete(in: services))
        guard case .incomplete(let report) = model.phase else {
            Issue.record("Expected an incomplete deletion")
            return
        }
        #expect(DeleteDataText.incomplete(report) == "Nothing was deleted. Try again in a moment.")

        let partial = DeletionReport(
            scope: .thisDevice, results: [(.closet, .deleted), (.looks, .failed), (.pictures, .failed)])
        #expect(
            DeleteDataText.incomplete(partial)
                == "Most of your data is deleted, but not: Looks and Try-on pictures. Try again to finish.")
    }
}

/// Delete my account (Phase 24c): what the screen shows for each way a deletion can end.
@MainActor
struct DeleteAccountModelTests {
    /// Answers every deletion with the same report.
    struct Scripted: DataDeletionService {
        let report: DeletionReport
        var scopes: [DeletionScope] { [.thisDevice, .account] }
        func parts(in scope: DeletionScope) -> [DataPart] {
            scope == .account
                ? [.serverData, .account, .signInWithApple, .drafts, .pictures, .looks, .suitcases, .closet, .profile]
                : [.drafts, .pictures, .looks, .suitcases, .closet, .profile]
        }
        func delete(_ scope: DeletionScope) async -> DeletionReport { report }
    }

    private func services(_ report: DeletionReport) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.deletion = Scripted(report: report)
        return services
    }

    private static let local: [(DataPart, DeletionOutcome)] = [
        (.drafts, .deleted), (.closet, .deleted), (.profile, .deleted),
    ]

    @Test func listsWhatTheServerHoldsFirstThenThisIPhone() async {
        let model = DeleteDataModel(scope: .account)
        await model.load(from: services(DeletionReport(scope: .account, results: [])))
        #expect(
            model.parts == [
                .serverData, .account, .signInWithApple, .closet, .looks, .pictures, .suitcases, .profile, .drafts,
            ])
        #expect(DeleteDataText.screenTitle(.account) == "Delete my account")
    }

    @Test func aFinishedDeletionStartsTheAppFresh() async {
        let report = DeletionReport(
            scope: .account,
            results: [(.serverData, .deleted), (.account, .deleted), (.signInWithApple, .deleted)] + Self.local)
        let model = DeleteDataModel(scope: .account)
        #expect(await model.delete(in: services(report)))
        #expect(model.phase == .ready)
    }

    @Test func aServerStillFinishingIsSaidPlainlyAndDoneLeaves() async {
        let report = DeletionReport(
            scope: .account,
            results: [(.serverData, .deleted), (.account, .pending), (.signInWithApple, .failed)] + Self.local)
        let model = DeleteDataModel(scope: .account)
        #expect(await !model.delete(in: services(report)))
        #expect(model.phase == .finished(report))
        let text = DeleteDataText.finished(report)
        #expect(text.contains("Everything on this iPhone is deleted and you’re signed out."))
        #expect(text.contains("Still being deleted on the server: Your account."))
        #expect(text.contains("Sign in with Apple"))
    }

    @Test func aLocalFailureOffersTryAgain() async {
        let report = DeletionReport(
            scope: .account,
            results: [(.serverData, .deleted), (.account, .deleted), (.signInWithApple, .deleted), (.closet, .failed)])
        let model = DeleteDataModel(scope: .account)
        #expect(await !model.delete(in: services(report)))
        #expect(model.phase == .incomplete(report))
    }

    @Test func nothingDeletedSaysWhyAndClosingApplesSheetChangesNothing() async {
        let offline = DeletionReport(scope: .account, results: [], notStarted: .offline)
        let model = DeleteDataModel(scope: .account)
        #expect(await !model.delete(in: services(offline)))
        #expect(model.phase == .notStarted(.offline))
        #expect(DeleteDataText.notStarted(.offline).hasPrefix("Nothing was deleted."))
        #expect(DeleteDataText.notStarted(.unavailable(retryAfterSeconds: 30)).contains("30 seconds"))

        let cancelled = DeletionReport(scope: .account, results: [], notStarted: .cancelled)
        #expect(await !model.delete(in: services(cancelled)))
        #expect(model.phase == .ready)
    }

    @Test func theSubscriptionNoteSaysDeletingDoesntCancelIt() {
        #expect(DeleteDataText.subscriptionNote.contains("doesn’t cancel your subscription"))
        #expect(DeleteDataText.subscriptionNote.contains("Subscriptions"))
    }
}

/// Phase 21a: the unsent note is kept in a `FeedbackDraftStore`, so it's there after a relaunch
/// (a new model on the same store), until she sends it or clears it.
@MainActor
struct FeedbackDraftKeepingTests {
    private let details = FeedbackDiagnostics(
        appVersion: "0.1", build: "14", systemVersion: "26.5", deviceModel: "iPhone13,2")

    @Test func anUnsentNoteComesBackAfterARelaunch() async throws {
        let store = InMemoryFeedbackDraftStore()
        let model = FeedbackModel(diagnostics: details, store: store)
        model.kind = .idea
        model.message = "The hamper is lovely"
        model.includesDetails = true
        await model.finishWriting()
        #expect(
            try await store.draft()
                == FeedbackDraft(kind: .idea, message: "The hamper is lovely", includesDetails: true))

        let relaunched = FeedbackModel(diagnostics: details, store: store)
        await relaunched.restore()
        #expect(relaunched.kind == .idea)
        #expect(relaunched.message == "The hamper is lovely")
        #expect(relaunched.includesDetails)
    }

    @Test func sendingOrClearingItForgetsTheNote() async throws {
        let store = InMemoryFeedbackDraftStore()
        let model = FeedbackModel(diagnostics: details, store: store)
        model.message = "Hamper didn't open"
        #expect(model.send())
        model.shareFinished(completed: true)
        await model.finishWriting()
        #expect(try await store.draft() == nil)

        model.startOver()
        model.message = "Another one"
        await model.finishWriting()
        #expect(try await store.draft()?.message == "Another one")
        // Emptying the words is clearing it.
        model.message = "  "
        await model.finishWriting()
        #expect(try await store.draft() == nil)
    }

    /// A share sheet closed without sending keeps the note.
    @Test func aCancelledShareKeepsTheNote() async throws {
        let store = InMemoryFeedbackDraftStore()
        let model = FeedbackModel(diagnostics: details, store: store)
        model.message = "Hamper didn't open"
        model.send()
        model.shareFinished(completed: false)
        await model.finishWriting()
        #expect(try await store.draft()?.message == "Hamper didn't open")
    }

    /// A kept note read late never replaces what she has started typing.
    @Test func restoringNeverReplacesHerTyping() async throws {
        let store = InMemoryFeedbackDraftStore(draft: FeedbackDraft(message: "Old note"))
        let model = FeedbackModel(diagnostics: details, store: store)
        model.message = "New note"
        await model.restore()
        #expect(model.message == "New note")
    }

    /// A store that fails leaves the page working, in memory.
    @Test func aFailingStoreLeavesTheNoteOnScreen() async {
        let store = InMemoryFeedbackDraftStore(options: StoreOptions(fails: true))
        let model = FeedbackModel(diagnostics: details, store: store)
        await model.restore()
        model.message = "Still here"
        await model.finishWriting()
        #expect(model.message == "Still here")
        #expect(model.preview != nil)
    }
}
