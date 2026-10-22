import Fixtures
import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Features

/// An account service whose Sign in with Apple does what the test says.
final class ScriptedAccount: AccountService {
    enum Answer {
        case signsIn
        case cancelled
        case fails(AccountProblem)
    }

    private struct State {
        var signedIn: Bool
        var answers: [Answer]
        var signIns = 0
        var signOuts = 0
    }

    private let state: Mutex<State>

    init(signedIn: Bool = false, answers: [Answer] = [.signsIn]) {
        state = Mutex(State(signedIn: signedIn, answers: answers))
    }

    var signIns: Int { state.withLock { $0.signIns } }
    var signOuts: Int { state.withLock { $0.signOuts } }

    var providerKind: AuthProviderKind { .fake }
    func isSignedIn() async -> Bool { state.withLock { $0.signedIn } }

    func signIn() async throws(AccountProblem) -> AccountUser {
        let answer = state.withLock { state -> Answer in
            state.signIns += 1
            let answer = state.answers.isEmpty ? .signsIn : state.answers.removeFirst()
            if case .signsIn = answer { state.signedIn = true }
            return answer
        }
        switch answer {
        case .signsIn: return AccountUser(id: "usr_test", createdAt: TestTime.now)
        case .cancelled: throw .cancelled
        case .fails(let problem): throw problem
        }
    }

    func whoAmI() async throws(AccountProblem) -> AccountUser { AccountUser(id: "usr_test", createdAt: TestTime.now) }
    func signOut() async {
        state.withLock {
            $0.signedIn = false
            $0.signOuts += 1
        }
    }
    func deleteAccount() async throws(AccountProblem) -> AccountDeletion { throw .signedOut }
    func accountDeletion(id: String) async throws(AccountProblem) -> AccountDeletion { throw .signedOut }
    func forgetAccountOnThisDevice() async {}
}

/// Release: Sign in with Apple only when she first uses a cloud feature. The sheet asks; Sign in
/// lets the action carry on; Not now cancels it cleanly; nothing asks with no sign-in in the
/// build or when she's already signed in.
@MainActor
struct SignInGateTests {
    private func services(_ account: ScriptedAccount, offersSignIn: Bool = true) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.account = account
        services.offersSignIn = offersSignIn
        return services
    }

    /// Starts an ask and waits until the sheet is open.
    private func asking(
        _ gate: SignInGate, _ reason: SignInReason, services: NookServices
    ) async -> Task<Bool, Never> {
        let task = Task { await gate.ask(reason, services: services) }
        while gate.request == nil { await Task.yield() }
        return task
    }

    @Test func signedOutTheSheetAsksAndSignInLetsTheActionCarryOn() async {
        let account = ScriptedAccount()
        let gate = SignInGate()
        let answer = await asking(gate, .tryOn, services: services(account))
        #expect(gate.request?.reason == .tryOn)
        await gate.signIn()
        #expect(await answer.value)
        #expect(gate.request == nil)
        #expect(await account.isSignedIn())
        #expect(account.signIns == 1)
    }

    @Test func notNowAnswersNoAndSignsNothingIn() async {
        let account = ScriptedAccount()
        let gate = SignInGate()
        let answer = await asking(gate, .stylingAccess, services: services(account))
        gate.notNow()
        #expect(await answer.value == false)
        #expect(gate.request == nil)
        #expect(account.signIns == 0)
        // Swiping the sheet away is the same as Not now.
        let again = await asking(gate, .tryOn, services: services(account))
        gate.dismissed()
        #expect(await again.value == false)
    }

    @Test func closingApplesSheetKeepsThisOneAndAFailureSaysWhy() async {
        let account = ScriptedAccount(answers: [.cancelled, .fails(.offline), .signsIn])
        let gate = SignInGate()
        let answer = await asking(gate, .support, services: services(account))
        await gate.signIn()
        #expect(gate.request != nil)
        #expect(gate.problem == nil)
        await gate.signIn()
        #expect(gate.request != nil)
        #expect(gate.problem == .offline)
        await gate.signIn()
        #expect(await answer.value)
        #expect(account.signIns == 3)
    }

    @Test func nothingAsksWhenSignedInOrWithNoSignInInTheBuild() async {
        let gate = SignInGate()
        #expect(await gate.ask(.styling, services: services(ScriptedAccount(signedIn: true))))
        #expect(await gate.ask(.styling, services: services(ScriptedAccount(), offersSignIn: false)))
        var unavailable = services(ScriptedAccount())
        unavailable.cloudUnavailable = true
        #expect(await gate.ask(.tryOn, services: unavailable))
        #expect(gate.request == nil)
        // No gate installed (previews, tests): every action goes on at once.
        #expect(await SignInCheck.notNeeded(.tryOn))
        #expect(!SignInCheck.notNeeded.isInstalled)
    }

    /// Style Me opens often, so its Not now holds for the rest of the run; a Sign in button she
    /// taps herself asks again.
    @Test func stylingsNotNowIsRememberedUntilSheAsks() async {
        let account = ScriptedAccount()
        let services = services(account)
        let gate = SignInGate()
        let first = await asking(gate, .styling, services: services)
        gate.notNow()
        #expect(await first.value == false)
        #expect(await gate.ask(.styling, services: services) == false)
        #expect(gate.request == nil)
        gate.forgetNotNow()
        let again = Task { await gate.ask(.styling, services: services, remembersNotNow: false) }
        while gate.request == nil { await Task.yield() }
        await gate.signIn()
        #expect(await again.value)
    }
}

/// The flows on each screen's model: what she started carries on after signing in, and Not now
/// cancels it with nothing sent or bought.
@MainActor
struct SignInFlowTests {
    /// The reasons asked, in order.
    final class Asked: Sendable {
        let reasons = Mutex<[SignInReason]>([])
        var list: [SignInReason] { reasons.withLock { $0 } }
    }

    private func check(_ answer: Bool, asked: Asked) -> SignInCheck {
        SignInCheck { reason in
            asked.reasons.withLock { $0.append(reason) }
            return answer
        }
    }

    @Test func styleMeAsksBeforeTheCloudAndCarriesOnOnceSignedIn() async {
        let asked = Asked()
        let stylist = ScriptedStylist()
        var services = yourLooksServices(stylist: stylist)
        services.cloudStyling = true
        services.stylistConsent = InMemoryStylistConsentStore(StylistConsent(agreedAt: TestTime.now))
        let model = yourLooksModel()
        model.signIn = check(true, asked: asked)
        model.start(with: services)
        await model.settle()
        #expect(asked.list == [.styling])
        #expect(await stylist.calls == 1)
        #expect(model.result?.madeBy == nil)
    }

    @Test func styleMesNotNowGivesQuickIdeasAndSendsNothing() async {
        let asked = Asked()
        let stylist = ScriptedStylist()
        let quick = ScriptedStylist()
        var services = yourLooksServices(stylist: stylist)
        services.cloudStyling = true
        services.quickIdeas = quick
        services.stylistConsent = InMemoryStylistConsentStore(StylistConsent(agreedAt: TestTime.now))
        let model = yourLooksModel()
        model.signIn = check(false, asked: asked)
        model.start(with: services)
        await model.settle()
        #expect(asked.list == [.styling])
        #expect(await stylist.calls == 0)
        #expect(await quick.calls == 1)
        #expect(model.status == .showing)
        #expect(model.quickIdeasReason == .limited(.account(.signedOut)))
        #expect(services.aiJobs.activeJobs.isEmpty)
    }

    @Test func stylingAccessIsBoughtOnlyAfterSigningIn() async {
        let asked = Asked()
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let store = ScriptedSubscriptionService(status: .none(at: TestTime.now))
        services.subscriptions = store
        let model = StylingAccessModel(now: { TestTime.now })
        await model.load(from: services)
        await model.purchase(in: services, signIn: check(false, asked: asked))
        #expect(store.purchaseCount == 0)
        #expect(model.message == nil)
        await model.purchase(in: services, signIn: check(true, asked: asked))
        #expect(store.purchaseCount == 1)
        #expect(model.hasAccess)
        #expect(asked.list == [.stylingAccess, .stylingAccess])
    }

    @Test func deleteMyAccountAsksFirstAndNotNowDeletesNothing() async throws {
        let asked = Asked()
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let model = DeleteDataModel(scope: .account)
        await model.load(from: services)
        #expect(await model.delete(in: services, signIn: check(false, asked: asked)) == false)
        #expect(model.phase == .ready)
        #expect(asked.list == [.deleteAccount])
        // Her closet is still there.
        #expect(try await services.closet.garments().isEmpty == false)
    }

    @Test func aRealPictureAsksFirstThenCarriesOnToHerConsent() async throws {
        let asked = Asked()
        let pipeline = StubPipeline()
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.tryOnPipeline = pipeline
        services.tryOnIsSimulated = false
        services.tryOnConsent = InMemoryTryOnConsentStore(nil)
        services.subscriptions = ScriptedSubscriptionService.debug("active", now: TestTime.now)
        services.aiJobs = AIJobs(now: { TestTime.now })
        let look = try await services.looks.look("o-blazer-office")
        let garments = Dictionary(uniqueKeysWithValues: try await services.closet.garments().map { ($0.id, $0) })

        // Not now: back where she was, nothing prepared or sent.
        let declined = TryOnModel(look: look, lookName: "Blazer", garments: garments, now: { TestTime.now })
        declined.signIn = check(false, asked: asked)
        await declined.start(with: services)
        declined.make()
        while declined.isAskingToSignIn { await Task.yield() }
        #expect(declined.step == .ready)
        #expect(pipeline.prepared == 0 && pipeline.sent == 0)

        // Signed in: Make a picture carries on by itself, to her consent first.
        let model = TryOnModel(look: look, lookName: "Blazer", garments: garments, now: { TestTime.now })
        model.signIn = check(true, asked: asked)
        await model.start(with: services)
        model.make()
        while model.step == .ready { await Task.yield() }
        #expect(model.step == .consent)
        #expect(asked.list == [.tryOn, .tryOn])
        #expect(pipeline.sent == 0)
    }
}
