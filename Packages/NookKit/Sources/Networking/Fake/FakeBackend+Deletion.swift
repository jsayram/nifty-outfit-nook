import Foundation

// 24c in the fake backend: account deletion with the same steps, answers and refusals as the
// real gateway (convex/deletion.ts). It deletes everything it holds for the account at once; a
// test or the debug screen can make the sign-in account's step fail, to see a pending deletion
// and a retry finish it. It doesn't model the usage the real backend keeps after a deletion.

struct FakeDeletions {
    struct Record {
        var id: String
        var subject: String
        var requestedAt: Date
        var completedAt: Date?
        var steps: [(step: String, state: String)]

        func state(_ step: String) -> String? { steps.first { $0.step == step }?.state }
        mutating func set(_ step: String, _ state: String) {
            if let index = steps.firstIndex(where: { $0.step == step }) { steps[index].state = state }
        }
    }

    var records: [String: Record] = [:]
    /// Subjects whose sign-in account was deleted: their tokens no longer work, as at Clerk.
    var deletedSubjects: Set<String> = []
    /// How many more times the sign-in account's step fails.
    var accountStepFailures = 0
    /// Deletions that reached the end, for tests and the debug screen.
    var completed = 0
    /// Told after every deletion request, with `FakeBackend.deletionReport()`.
    var observer: (@Sendable (Data) -> Void)?

    func running(for subject: String) -> Record? {
        records.values.first { $0.subject == subject && $0.completedAt == nil }
    }
}

extension FakeBackend {
    // MARK: Controls for tests and the debug screen

    /// The next `times` deletion requests can't delete the sign-in account (as if Clerk were down).
    public func failAccountDeletion(times: Int) {
        state.withLock { $0.deletions.accountStepFailures = times }
    }

    /// How many account deletions have finished.
    public var accountDeletionsCompleted: Int { state.withLock { $0.deletions.completed } }

    /// Whether the fake still holds anything for this pretend Apple user: the account, paid
    /// actions, keys, challenges or a rate bucket.
    public func holdsData(forSubject subject: String) -> Bool {
        state.withLock { state in
            state.principals[subject] != nil || state.ledger.actions.values.contains { $0.subject == subject }
                || state.ledger.keys.values.contains { $0.subject == subject }
                || state.ledger.challenges.values.contains { $0.subject == subject }
                || state.ledger.buckets[subject] != nil || state.support.tickets.contains { $0.subject == subject }
        }
    }

    /// Every pretend Apple user the fake has an account for.
    public var accountSubjects: [String] { state.withLock { Array($0.principals.keys) } }

    /// Calls `observer` after every deletion request with `deletionReport()`, for the debug
    /// launch that checks a deletion from outside the app (`-fake-signed-in`).
    public func observeDeletions(_ observer: @escaping @Sendable (Data) -> Void) {
        state.withLock { $0.deletions.observer = observer }
    }

    /// Counts only, no IDs: accounts held, deletions finished and running, and how many pretend
    /// users the fake still holds anything for.
    public func deletionReport() -> Data {
        let report = state.withLock { state -> [String: Int] in
            var subjects = Set(state.principals.keys)
            subjects.formUnion(state.ledger.actions.values.map(\.subject))
            subjects.formUnion(state.ledger.keys.values.map(\.subject))
            subjects.formUnion(state.ledger.challenges.values.map(\.subject))
            subjects.formUnion(state.ledger.buckets.keys)
            subjects.formUnion(state.support.tickets.map(\.subject))
            return [
                "accounts": state.principals.count,
                "deletionsCompleted": state.deletions.completed,
                "deletionsRunning": state.deletions.records.values.filter { $0.completedAt == nil }.count,
                "usersWithData": subjects.count,
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])) ?? Data()
    }

    // MARK: Answering

    func isDeletedSubject(_ subject: String) -> Bool {
        state.withLock { $0.deletions.deletedSubjects.contains(subject) }
    }

    func isDeleting(_ subject: String) -> Bool {
        state.withLock { $0.deletions.running(for: subject) != nil }
    }

    func routeDeleteAccount(_ request: URLRequest, body: Data?, subject: String, id: String) -> FakeReply {
        if let problem = checkJSON(request, body, fields: ["confirm", "appleAuthorizationCode"]) { return problem(id) }
        let object = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        guard object["confirm"] as? String == APIV1.DeletionRequest.confirmation,
            let code = object["appleAuthorizationCode"] as? String,
            code.wholeMatch(of: /[A-Za-z0-9._-]{8,512}/) != nil
        else { return error(.invalidRequest, id) }

        let record = state.withLock { state -> FakeDeletions.Record? in
            var record: FakeDeletions.Record
            if let running = state.deletions.running(for: subject) {
                record = running
            } else {
                guard state.principals[subject] != nil else { return nil }
                record = FakeDeletions.Record(
                    id: "del_" + FakeToken.randomHex(16), subject: subject,
                    requestedAt: Self.millisecondPrecision(now()),
                    steps: [("signInWithApple", "pending"), ("serverData", "pending"), ("account", "pending")])
            }
            if record.state("signInWithApple") != "done" {
                record.set("signInWithApple", code.contains("reject") ? "failed" : "done")
            }
            // Everything the fake holds for the account.
            state.principals[subject] = nil
            state.ledger.actions = state.ledger.actions.filter { $0.value.subject != subject }
            state.ledger.keys = state.ledger.keys.filter { $0.value.subject != subject }
            state.ledger.challenges = state.ledger.challenges.filter { $0.value.subject != subject }
            state.ledger.buckets[subject] = nil
            deleteSupport(for: subject, in: &state)
            // 30b: her picture-credit grants, as the backend deletes them for now (30c decides how
            // long billing records are kept).
            state.credits.grants = state.credits.grants.filter { $0.value.subject != subject }
            record.set("serverData", "done")
            if record.state("account") != "done" {
                if state.deletions.accountStepFailures > 0 {
                    state.deletions.accountStepFailures -= 1
                } else {
                    record.set("account", "done")
                    state.deletions.deletedSubjects.insert(subject)
                }
            }
            if record.state("account") == "done" {
                record.completedAt = Self.millisecondPrecision(now())
                state.deletions.completed += 1
            }
            state.deletions.records[record.id] = record
            return record
        }
        if let observer = state.withLock({ $0.deletions.observer }) { observer(deletionReport()) }
        guard let record else { return error(.notRegistered, id) }
        return encode(202, Self.status(record), id)
    }

    func routeDeletionStatus(_ request: URLRequest, body: Data?, id: String) -> FakeReply {
        if let problem = checkJSON(request, body, fields: ["deletionId"]) { return problem(id) }
        let object = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        guard let deletionId = object["deletionId"] as? String, deletionId.wholeMatch(of: /del_[0-9a-f]{32}/) != nil
        else { return error(.invalidRequest, id) }
        guard let record = state.withLock({ $0.deletions.records[deletionId] }) else {
            return error(.notFound, id, message: "No such deletion.")
        }
        return encode(200, Self.status(record), id)
    }

    static func status(_ record: FakeDeletions.Record) -> APIV1.DeletionStatus {
        APIV1.DeletionStatus(
            deletion: .init(
                id: record.id, state: record.completedAt == nil ? "in_progress" : "completed",
                requestedAt: .init(record.requestedAt), completedAt: record.completedAt.map(APIV1.DateTime.init),
                steps: record.steps.map { .init(step: $0.step, state: $0.state) }))
    }

    /// Content type, size, JSON object and no unknown fields, as the real gateway checks them.
    func checkJSON(_ request: URLRequest, _ body: Data?, fields: Set<String>) -> ((String) -> FakeReply)? {
        let type = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard type.lowercased().hasPrefix("application/json") else { return { self.error(.unsupportedMediaType, $0) } }
        guard let body, body.count <= APIV1.maxBodyBytes else { return { self.error(.payloadTooLarge, $0) } }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return { self.error(.invalidRequest, $0, message: "The body isn't valid JSON.") }
        }
        if let unknown = object.keys.sorted().first(where: { !fields.contains($0) }) {
            return { self.error(.invalidRequest, $0, message: "Unknown field: \(unknown).") }
        }
        return nil
    }
}
