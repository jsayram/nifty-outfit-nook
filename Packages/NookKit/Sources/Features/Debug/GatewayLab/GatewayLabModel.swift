#if DEBUG
    import Foundation
    import Models
    import Observation

    /// What the gateway screen can change about the fake backend. The app fills it in when it runs
    /// on the fakes; with Clerk and the real backend there's nothing to change, so it's nil.
    public struct GatewayLabControls: Sendable {
        public struct Mode: Sendable, Identifiable, Hashable {
            public var id: String
            public var title: String
            public init(id: String, title: String) {
                self.id = id
                self.title = title
            }
        }

        public var modes: [Mode]
        public var setMode: @Sendable (String) -> Void

        public init(modes: [Mode], setMode: @escaping @Sendable (String) -> Void) {
            self.modes = modes
            self.setMode = setMode
        }
    }

    /// The gateway's log lines, newest last, for the screen. The app appends a line per client
    /// event (never a token or a body).
    @Observable
    public final class GatewayLabLog {
        public private(set) var lines: [String] = []
        /// Every line ever added, so a call can find its own lines after old ones are dropped.
        public private(set) var total = 0
        public init() {}

        public func append(_ line: String) {
            lines.append(line)
            total += 1
            if lines.count > 60 { lines.removeFirst(lines.count - 60) }
        }

        /// The lines added since `total` was `start`, oldest first.
        public func lines(since start: Int) -> [String] {
            Array(lines.suffix(min(lines.count, max(0, total - start))))
        }
    }

    /// The gateway screen's state (Phase 24a checkpoint): sign in, who am I, sign out, and what
    /// each failure looks like to her.
    @Observable
    final class GatewayLabModel {
        enum Status: Equatable {
            case unknown
            case signedOut
            case signedIn(AccountUser?)
        }

        private(set) var status = Status.unknown
        private(set) var isWorking = false
        /// The last outcome, as she'd read it.
        private(set) var message: String?
        private(set) var messageIsProblem = false
        private(set) var modeID = "normal"
        /// After a 429 or 503 with Retry-After, calls wait until then.
        private(set) var retryAllowedAt: Date?

        /// Where the last call's log lines start, so the result can show what happened on the way.
        private(set) var callLogStart: Int?

        let account: any AccountService
        let controls: GatewayLabControls?
        let log: GatewayLabLog
        private let now: () -> Date

        init(
            account: any AccountService, controls: GatewayLabControls?, log: GatewayLabLog = GatewayLabLog(),
            now: @escaping () -> Date = { Date() }
        ) {
            self.account = account
            self.controls = controls
            self.log = log
            self.now = now
        }

        /// What the client did during the last call: tries, answers, a token refresh, waits.
        var lastCallLines: [String] {
            callLogStart.map { log.lines(since: $0) } ?? []
        }

        var providerName: String {
            account.providerKind == .clerk ? "Clerk (real)" : "Fake sign-in and fake backend"
        }

        var isWaitingToRetry: Bool {
            guard let retryAllowedAt else { return false }
            return retryAllowedAt > now()
        }

        func refreshStatus() async {
            status = await account.isSignedIn() ? .signedIn(currentUser) : .signedOut
        }

        private var currentUser: AccountUser? {
            if case .signedIn(let user) = status { return user }
            return nil
        }

        func signIn() async {
            await run { () async throws(AccountProblem) in
                let user = try await account.signIn()
                status = .signedIn(user)
                show("Signed in.", problem: false)
            }
        }

        func whoAmI() async {
            await run { () async throws(AccountProblem) in
                let user = try await account.whoAmI()
                status = .signedIn(user)
                show("The backend says you're \(user.id).", problem: false)
            }
        }

        func signOut() async {
            await account.signOut()
            status = .signedOut
            retryAllowedAt = nil
            callLogStart = nil
            show("Signed out.", problem: false)
        }

        func setMode(_ id: String) {
            modeID = id
            controls?.setMode(id)
        }

        private func run(_ work: () async throws(AccountProblem) -> Void) async {
            guard !isWorking else { return }
            isWorking = true
            message = nil
            callLogStart = log.total
            defer { isWorking = false }
            do {
                try await work()
                retryAllowedAt = nil
            } catch {
                handle(error)
            }
        }

        private func handle(_ problem: AccountProblem) {
            switch problem {
            case .rateLimited(let seconds):
                retryAllowedAt = now().addingTimeInterval(TimeInterval(seconds))
            case .unavailable(let seconds?):
                retryAllowedAt = now().addingTimeInterval(TimeInterval(seconds))
            case .signedOut:
                status = .signedOut
            default:
                break
            }
            if let text = Self.message(for: problem) {
                show(text, problem: true)
            }
            if let until = retryAllowedAt {
                // Lets Who am I? be tapped again once the wait is over.
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSince(Date()))))
                    if self?.retryAllowedAt == until { self?.retryAllowedAt = nil }
                }
            }
        }

        private func show(_ text: String, problem: Bool) {
            message = text
            messageIsProblem = problem
        }

        /// What she'd read for each problem. Proposed wording for the real sign-in screens, which
        /// still need a design; the local closet keeps working in every case.
        static func message(for problem: AccountProblem) -> String? {
            switch problem {
            case .cancelled:
                nil
            case .offline:
                "You're offline. Your closet still works on this iPhone. Try again when you're connected."
            case .timedOut:
                "The server took too long to answer. Try again in a moment."
            case .rateLimited(let seconds):
                "Too many tries. Try again in \(waitText(seconds))."
            case .unavailable(let seconds?):
                "This isn't available right now. Try again in \(waitText(seconds))."
            case .unavailable(nil):
                "This isn't available right now. Try again later."
            case .forbidden:
                "This account can't do that."
            case .signedOut:
                "You're signed out. Sign in to use this."
            case .serverError:
                "Something went wrong on our side. Try again later."
            case .updateRequired:
                "Update the app to keep using this."
            case .invalidResponse, .rejected:
                "Something went wrong. Try again later."
            }
        }

        static func waitText(_ seconds: Int) -> String {
            if seconds < 90 { return seconds == 1 ? "1 second" : "\(seconds) seconds" }
            let minutes = Int((Double(seconds) / 60).rounded(.up))
            return "\(minutes) minutes"
        }
    }
#endif
