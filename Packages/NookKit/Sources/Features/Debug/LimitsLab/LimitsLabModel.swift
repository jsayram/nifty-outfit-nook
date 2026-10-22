#if DEBUG
    import Foundation
    import Models
    import Observation

    /// What the limits screen can change on the fake backend. Nil on the real services.
    public struct LimitsLabControls: Sendable {
        public var setPaused: @Sendable (PaidFeature, Bool) -> Void
        /// The next answer is lost after the server did the work (a timeout), once.
        public var loseNextAnswer: @Sendable () -> Void
        /// How many paid jobs really ran on the server.
        public var jobsRun: @Sendable () -> Int
        public var resetUsage: @Sendable () -> Void

        public init(
            setPaused: @escaping @Sendable (PaidFeature, Bool) -> Void,
            loseNextAnswer: @escaping @Sendable () -> Void,
            jobsRun: @escaping @Sendable () -> Int,
            resetUsage: @escaping @Sendable () -> Void
        ) {
            self.setPaused = setPaused
            self.loseNextAnswer = loseNextAnswer
            self.jobsRun = jobsRun
            self.resetUsage = resetUsage
        }
    }

    /// The Phase 24b checkpoint screen's state: placeholder paid actions through the gateway, the
    /// messages for each limit, her allowances, the kill switch, and a retry with the same key.
    @Observable
    final class LimitsLabModel {
        private(set) var signedIn = false
        private(set) var usage: CloudUsage?
        private(set) var message: String?
        private(set) var messageIsProblem = false
        private(set) var isWorking = false
        /// What the server says about the last action: replayed or not, and how many jobs ran.
        private(set) var detail: String?
        private(set) var paused: Set<PaidFeature> = []
        /// The last action's request and key, so it can be sent again unchanged.
        private var last: (request: PaidActionRequest, key: String)?

        let account: any AccountService
        let paid: any PaidActionService
        let controls: LimitsLabControls?
        private let now: () -> Date

        init(
            account: any AccountService, paid: any PaidActionService, controls: LimitsLabControls?,
            now: @escaping () -> Date = { Date() }
        ) {
            self.account = account
            self.paid = paid
            self.controls = controls
            self.now = now
        }

        var canSendAgain: Bool { last != nil }

        func start() async {
            signedIn = await account.isSignedIn()
            if signedIn { await refreshUsage() }
        }

        func signIn() async {
            await work {
                do {
                    _ = try await account.signIn()
                    signedIn = true
                    show("Signed in.", problem: false)
                } catch {
                    show("Couldn't sign in.", problem: true)
                }
                await refreshUsage()
            }
        }

        func refreshUsage() async {
            do {
                usage = try await paid.usage()
            } catch {
                show(CloudLimitText.message(for: error, now: now()), problem: true)
            }
        }

        /// A new action, with a new key.
        func run(_ request: PaidActionRequest) async {
            await send(request, key: IdempotencyKey.make())
        }

        /// The last action again, with the same key: the server answers from its record.
        func sendAgain() async {
            guard let last else { return }
            await send(last.request, key: last.key)
        }

        /// A new action whose first answer gets lost on the way back: the client retries with the
        /// same key and the server doesn't run it twice.
        func runWithLostAnswer(_ request: PaidActionRequest) async {
            controls?.loseNextAnswer()
            await send(request, key: IdempotencyKey.make())
        }

        func setPaused(_ feature: PaidFeature, _ on: Bool) async {
            if on { paused.insert(feature) } else { paused.remove(feature) }
            controls?.setPaused(feature, on)
            await refreshUsage()
        }

        func startOver() async {
            controls?.resetUsage()
            last = nil
            detail = nil
            message = nil
            await refreshUsage()
        }

        private func send(_ request: PaidActionRequest, key: String) async {
            await work {
                last = (request, key)
                let before = controls?.jobsRun()
                do throws(CloudLimitProblem) {
                    let receipt = try await paid.run(request, idempotencyKey: key)
                    show(Self.doneText(request), problem: false)
                    detail = Self.detailText(receipt: receipt, jobsBefore: before, jobsAfter: controls?.jobsRun())
                } catch {
                    show(CloudLimitText.message(for: error, now: now()), problem: true)
                    detail = nil
                }
                await refreshUsage()
            }
        }

        private func work(_ body: () async -> Void) async {
            guard !isWorking else { return }
            isWorking = true
            defer { isWorking = false }
            await body()
        }

        private func show(_ text: String, problem: Bool) {
            message = text
            messageIsProblem = problem
        }

        static func doneText(_ request: PaidActionRequest) -> String {
            switch request {
            case .style(let call) where call.mode == .full: "Done: an outfit idea (sample pieces)."
            case .style: "Done: a swap or question (sample pieces)."
            case .tryOn: "Done: a try-on picture (placeholder)."
            }
        }

        static func detailText(receipt: PaidActionReceipt, jobsBefore: Int?, jobsAfter: Int?) -> String {
            var text =
                receipt.replayed
                ? "The server had already done this one, so it wasn't run or counted again."
                : "Run and counted once."
            if let jobsBefore, let jobsAfter {
                text += " Jobs run on the server: \(jobsAfter) (+\(jobsAfter - jobsBefore))."
            }
            return text
        }
    }
#endif
