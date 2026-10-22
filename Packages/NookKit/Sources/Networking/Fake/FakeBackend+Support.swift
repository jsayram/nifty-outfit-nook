import Foundation
import ImageIO
import Models

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    // The fake backend's 24d half: POST /v1/feedback with the real gateway's checks, limits and
    // answers (convex/support.ts in the backend repo): the schema with unknown fields refused, a
    // resend returning the same ticket, a burst limit, a daily count, a daily count of screenshots
    // and intake that can be closed.
    //
    // It also acts as an auditor of what the app sends. For a screenshot it reads the picture it was
    // handed with ImageIO and keeps which metadata dictionaries are in it (Exif, GPS, TIFF, IPTC),
    // so a test or the debug launch can check the app removed them before sending. The real backend
    // removes them again; the fake deliberately does not, so a mistake in the app shows.

    /// One note the fake holds, as a test can read it.
    public struct FakeSupportTicket: Sendable, Equatable {
        public struct Screenshot: Sendable, Equatable {
            public var contentType: String
            public var bytes: Int
            public var pixelWidth: Int
            public var pixelHeight: Int
            /// What the picture it received says about where, when, with what and about whom: a
            /// dictionary such as "{GPS}" or "{IPTC}", or a field such as "{TIFF}.Make" or
            /// "{Exif}.UserComment". Empty for a clean one (ImageIO still writes the picture's size,
            /// colour and resolution, which say nothing about her).
            public var metadataDictionaries: [String]
            public var data: Data
        }

        public var reference: String
        public var subject: String
        public var submissionId: String
        public var kind: String
        public var message: String
        public var replyTo: String?
        public var diagnostics: [String: String]?
        public var closetCounts: [String: Int]?
        /// 31: the approved device-health summary, as the fake read it from the request.
        public var deviceHealth: DeviceHealthSummary?
        public var screenshot: Screenshot?
        /// Release: a report about an AI result (kind `aiReport`): its block's fields as sent.
        public var aiReport: [String: String]?
        public var createdAt: Date
    }

    struct FakeSupport {
        var tickets: [FakeSupportTicket] = []
        var buckets: [String: (tokens: Double, updatedAt: Date)] = [:]
        /// Intake closed, like `NOOK_SUPPORT_INTAKE=closed` on the real backend.
        var closed = false
        /// Told after every accepted note, with `supportReport()`.
        var observer: (@Sendable (Data) -> Void)?
    }

    extension FakeBackend {
        // The backend's policy (convex/ticketing/policy.ts).
        private static let burst = 5.0
        private static let burstSeconds = 3600.0
        private static let notesPerDay = 10
        /// Release: AI reports have their own bucket and daily count.
        private static let aiReportsPerDay = 20
        private static let screenshotsPerDay = 3
        private static let day: TimeInterval = 86_400

        // MARK: Controls for tests and the debug launch

        /// Every note the fake holds, oldest first.
        public var supportTickets: [FakeSupportTicket] { state.withLock { $0.support.tickets } }

        /// Closes or opens intake, like the server's switch.
        public func setSupportIntake(closed: Bool) {
            state.withLock { $0.support.closed = closed }
        }

        /// Calls `observer` after every accepted note with `supportReport()`, for the debug launch
        /// that checks what was sent from outside the app (`-fake-signed-in`).
        public func observeSupport(_ observer: @escaping @Sendable (Data) -> Void) {
            state.withLock { $0.support.observer = observer }
        }

        /// What the newest note carried, for a check from outside the app: no IDs, and no account.
        public func supportReport() -> Data {
            let tickets = supportTickets
            var report: [String: Any] = ["tickets": tickets.count]
            if let last = tickets.last {
                var note: [String: Any] = [
                    "kind": last.kind, "message": last.message, "hasReplyAddress": last.replyTo != nil,
                    "hasDiagnostics": last.diagnostics != nil, "hasClosetCounts": last.closetCounts != nil,
                    "hasDeviceHealth": last.deviceHealth != nil,
                ]
                if let replyTo = last.replyTo { note["replyTo"] = replyTo }
                if let diagnostics = last.diagnostics { note["diagnostics"] = diagnostics }
                if let counts = last.closetCounts { note["closetCounts"] = counts }
                if let report = last.aiReport { note["aiReport"] = report }
                if let screenshot = last.screenshot {
                    note["screenshot"] = [
                        "contentType": screenshot.contentType, "bytes": screenshot.bytes,
                        "pixelWidth": screenshot.pixelWidth, "pixelHeight": screenshot.pixelHeight,
                        "metadataDictionaries": screenshot.metadataDictionaries,
                    ]
                }
                report["last"] = note
            }
            return (try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])) ?? Data()
        }

        // MARK: Answering

        func routeFeedback(_ request: URLRequest, body: Data?, subject: String, id: String) -> FakeReply {
            let type = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard type.lowercased().hasPrefix("application/json") else { return error(.unsupportedMediaType, id) }
            guard let body, body.count <= APIV1.sendFeedback.maxBodyBytes else { return error(.payloadTooLarge, id) }
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return error(.invalidRequest, id, message: "The body isn't valid JSON.")
            }
            let parsed: ParsedNote
            switch ParsedNote.parse(object) {
            case .failure(let problem): return error(.invalidRequest, id, message: problem.message)
            case .success(let note): parsed = note
            }

            enum Outcome {
                case reply(FakeReply)
                case taken(FakeSupportTicket, observer: (@Sendable (Data) -> Void)?)
            }
            let time = now()
            let outcome = state.withLock { state -> Outcome in
                // The same note again: the same ticket, nothing new, no allowance used.
                if let earlier = state.support.tickets.first(where: {
                    $0.subject == subject && $0.submissionId == parsed.submissionId
                }) {
                    return .taken(earlier, observer: nil)
                }
                if state.support.closed {
                    return .reply(
                        error(
                            .unavailable, id, message: "Sending notes is paused for now. Try the support page.",
                            retryAfter: 3600))
                }
                let mine = state.support.tickets.filter {
                    $0.subject == subject && $0.createdAt > time.addingTimeInterval(-Self.day)
                }
                let isReport = parsed.aiReport != nil
                let sameKind = mine.filter { ($0.aiReport != nil) == isReport }
                if sameKind.count >= (isReport ? Self.aiReportsPerDay : Self.notesPerDay),
                    let oldest = sameKind.map(\.createdAt).min()
                {
                    let wait = max(1, Int(oldest.addingTimeInterval(Self.day).timeIntervalSince(time).rounded(.up)))
                    return .reply(error(.rateLimited, id, retryAfter: wait))
                }
                if parsed.screenshot != nil {
                    let withPicture = mine.filter { $0.screenshot != nil }
                    if withPicture.count >= Self.screenshotsPerDay, let oldest = withPicture.map(\.createdAt).min() {
                        let wait = max(1, Int(oldest.addingTimeInterval(Self.day).timeIntervalSince(time).rounded(.up)))
                        return .reply(error(.rateLimited, id, retryAfter: wait))
                    }
                }
                let perSecond = Self.burst / Self.burstSeconds
                let bucketName = isReport ? subject + "|aiReport" : subject
                let bucket = state.support.buckets[bucketName] ?? (Self.burst, time)
                let tokens = min(
                    Self.burst, bucket.tokens + max(0, time.timeIntervalSince(bucket.updatedAt)) * perSecond)
                if tokens < 1 {
                    let wait = max(1, Int(((1 - tokens) / perSecond).rounded(.up)))
                    state.support.buckets[bucketName] = (tokens, time)
                    return .reply(error(.rateLimited, id, retryAfter: wait))
                }
                state.support.buckets[bucketName] = (tokens - 1, time)

                let ticket = FakeSupportTicket(
                    reference: "NK-" + FakeToken.randomHex(4).uppercased(), subject: subject,
                    submissionId: parsed.submissionId, kind: parsed.kind, message: parsed.message,
                    replyTo: parsed.replyTo, diagnostics: parsed.diagnostics, closetCounts: parsed.closetCounts,
                    deviceHealth: parsed.deviceHealth, screenshot: parsed.screenshot, aiReport: parsed.aiReport,
                    createdAt: Self.millisecondPrecision(time))
                state.support.tickets.append(ticket)
                return .taken(ticket, observer: state.support.observer)
            }
            switch outcome {
            case .reply(let reply):
                return reply
            case .taken(let ticket, let observer):
                observer?(supportReport())
                return encode(
                    202,
                    APIV1.FeedbackReceipt(
                        ticket: .init(
                            ref: ticket.reference, receivedAt: APIV1.formatDate(ticket.createdAt),
                            hasAttachment: ticket.screenshot != nil)),
                    id)
            }
        }

        /// Deletes the account's notes, as the real deletion does.
        func deleteSupport(for subject: String, in state: inout State) {
            state.support.tickets.removeAll { $0.subject == subject }
            state.support.buckets[subject] = nil
            state.support.buckets[subject + "|aiReport"] = nil
        }
    }

    /// A note that passed the contract's FeedbackRequest checks.
    private struct ParsedNote {
        struct Problem: Error { var message: String }

        var submissionId: String
        var kind: String
        var message: String
        var replyTo: String?
        var diagnostics: [String: String]?
        var closetCounts: [String: Int]?
        var deviceHealth: DeviceHealthSummary?
        var screenshot: FakeSupportTicket.Screenshot?
        var aiReport: [String: String]?

        static func parse(_ object: [String: Any]) -> Result<ParsedNote, Problem> {
            func fail(_ text: String) -> Result<ParsedNote, Problem> { .failure(Problem(message: text)) }
            let allowed: Set<String> = [
                "submissionId", "kind", "message", "replyTo", "diagnostics", "closetCounts", "deviceHealth",
                "attachment", "aiReport",
            ]
            if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
                return fail("Unknown field: \(unknown).")
            }
            guard let submissionId = object["submissionId"] as? String,
                submissionId.wholeMatch(of: /[A-Za-z0-9_-]{16,64}/) != nil
            else { return fail("submissionId has the wrong format.") }
            guard let kind = object["kind"] as? String, ["somethingWrong", "idea", "other", "aiReport"].contains(kind)
            else {
                return fail("kind isn't an allowed value.")
            }
            guard let message = object["message"] as? String, message.count <= 2_000,
                message.contains(where: { !$0.isWhitespace }),
                !message.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) })
            else { return fail("message can't be sent.") }

            var replyTo: String?
            if let value = object["replyTo"] {
                guard let text = value as? String, FeedbackRules.isEmailAddress(text) else {
                    return fail("replyTo has the wrong format.")
                }
                replyTo = text
            }
            var diagnostics: [String: String]?
            if let value = object["diagnostics"] {
                let fields: [(String, Regex<Substring>)] = [
                    ("appVersion", /[0-9A-Za-z.+-]{1,32}/), ("build", /[0-9A-Za-z.-]{1,16}/),
                    ("systemVersion", /[0-9.]{1,16}/), ("deviceModel", /[A-Za-z0-9,]{1,32}/),
                ]
                guard let dictionary = value as? [String: Any], Set(dictionary.keys) == Set(fields.map(\.0)) else {
                    return fail("diagnostics has the wrong fields.")
                }
                var checked: [String: String] = [:]
                for (name, pattern) in fields {
                    guard let text = dictionary[name] as? String, text.wholeMatch(of: pattern) != nil else {
                        return fail("\(name) has the wrong format.")
                    }
                    checked[name] = text
                }
                diagnostics = checked
            }
            var closetCounts: [String: Int]?
            if let value = object["closetCounts"] {
                guard let dictionary = value as? [String: Any],
                    Set(dictionary.keys) == ["pieces", "looks", "suitcases"]
                else { return fail("closetCounts has the wrong fields.") }
                var checked: [String: Int] = [:]
                for (name, raw) in dictionary {
                    guard let number = raw as? Int, (0...100_000).contains(number) else {
                        return fail("\(name) isn't a sensible count.")
                    }
                    checked[name] = number
                }
                closetCounts = checked
            }
            var deviceHealth: DeviceHealthSummary?
            if let value = object["deviceHealth"] {
                guard let dictionary = value as? [String: Any], let checked = parseDeviceHealth(dictionary) else {
                    return fail("deviceHealth has the wrong fields.")
                }
                deviceHealth = checked
            }
            var screenshot: FakeSupportTicket.Screenshot?
            if let value = object["attachment"] {
                guard let dictionary = value as? [String: Any], Set(dictionary.keys) == ["contentType", "data"],
                    let contentType = dictionary["contentType"] as? String,
                    ["image/jpeg", "image/png"].contains(contentType),
                    let text = dictionary["data"] as? String, text.count <= 800_000,
                    let data = Data(base64Encoded: text), data.count <= FeedbackScreenshot.maximumBytes,
                    let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                    let width = properties[kCGImagePropertyPixelWidth] as? Int,
                    let height = properties[kCGImagePropertyPixelHeight] as? Int
                else { return fail("That picture can't be used. Attach a JPEG or PNG screenshot.") }
                screenshot = .init(
                    contentType: contentType, bytes: data.count, pixelWidth: width, pixelHeight: height,
                    metadataDictionaries: ImageMetadata.identifying(in: properties), data: data)
            }
            // Release: the report's block goes with kind aiReport, and only a try-on picture's
            // report may carry a picture (the backend's gateway rules).
            var aiReport: [String: String]?
            if (kind == "aiReport") != (object["aiReport"] != nil) {
                return fail("A report needs its details, and only a report has them.")
            }
            if let value = object["aiReport"] {
                guard let block = value as? [String: Any], let checked = parseReport(block) else {
                    return fail("aiReport has the wrong fields.")
                }
                if screenshot != nil, checked["subject"] != "tryOnPicture" {
                    return fail("Only a try-on picture's report can include a picture.")
                }
                aiReport = checked
            }
            return .success(
                ParsedNote(
                    submissionId: submissionId, kind: kind, message: message, replyTo: replyTo,
                    diagnostics: diagnostics,
                    closetCounts: closetCounts, deviceHealth: deviceHealth, screenshot: screenshot, aiReport: aiReport))
        }

        /// The contract's AIReport: four reasons, four subjects, no provider or model fields.
        private static func parseReport(_ block: [String: Any]) -> [String: String]? {
            let required = ["subject", "reason", "resultId", "madeBy", "madeAt", "hidden"]
            let keys = Set(block.keys)
            guard Set(required).isSubset(of: keys), keys.isSubset(of: Set(required + ["actionId", "lookVersion"]))
            else { return nil }
            let enums: [String: Set<String>] = [
                "subject": ["look", "why", "askAnswer", "tryOnPicture"],
                "reason": ["wrongOrOffensive", "notMyClothes", "looksWrongOnMe", "other"],
                "madeBy": ["cloud", "onDevice", "phone"],
                "lookVersion": ["simple", "dressedUp", "somethingNew"],
            ]
            var checked: [String: String] = [:]
            for (name, allowed) in enums {
                guard let raw = block[name] else { continue }
                guard let text = raw as? String, allowed.contains(text) else { return nil }
                checked[name] = text
            }
            guard let resultID = block["resultId"] as? String, resultID.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil,
                let madeAt = block["madeAt"] as? String, madeAt.count <= 30, APIV1.parseDate(madeAt) != nil,
                let hidden = block["hidden"] as? Bool
            else { return nil }
            checked["resultId"] = resultID
            checked["madeAt"] = madeAt
            checked["hidden"] = hidden ? "true" : "false"
            if let raw = block["actionId"] {
                guard let action = raw as? String, AIReportTarget.isActionID(action) else { return nil }
                checked["actionId"] = action
            }
            return checked
        }

        /// The contract's `FeedbackDeviceHealth`: exactly these fields, whole numbers in range, at most
        /// eight crash kinds with fixed names. Anything else is refused.
        private static func parseDeviceHealth(_ dictionary: [String: Any]) -> DeviceHealthSummary? {
            let required = [
                "windowDays", "crashes", "hangs", "cpuExceptions", "diskWriteExceptions", "memoryExits",
                "watchdogExits",
            ]
            let optional = ["longestHangMs", "launchMedianMs", "peakMemoryMB", "crashKinds"]
            let keys = Set(dictionary.keys)
            guard Set(required).isSubset(of: keys), keys.isSubset(of: Set(required + optional)) else { return nil }
            func whole(_ name: String) -> Int? {
                guard let number = dictionary[name] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                    number.doubleValue == number.doubleValue.rounded()
                else { return nil }
                return number.intValue
            }
            guard let windowDays = whole("windowDays"), (1...90).contains(windowDays) else { return nil }
            var counts: [Int] = []
            for name in required.dropFirst() {
                guard let count = whole(name), (0...10_000).contains(count) else { return nil }
                counts.append(count)
            }
            func timing(_ name: String, upTo limit: Int) -> Int?? {
                guard dictionary[name] != nil else { return .some(nil) }
                guard let value = whole(name), (0...limit).contains(value) else { return nil }
                return .some(value)
            }
            guard let hang = timing("longestHangMs", upTo: 3_600_000),
                let launch = timing("launchMedianMs", upTo: 600_000),
                let memory = timing("peakMemoryMB", upTo: 65_536)
            else { return nil }
            var kinds: [DeviceHealthSummary.CrashKind] = []
            if let raw = dictionary["crashKinds"] {
                guard let list = raw as? [[String: Any]], list.count <= DeviceHealthSummary.maximumCrashKinds else {
                    return nil
                }
                for item in list {
                    guard Set(item.keys) == ["exception", "signal", "count"],
                        let exception = (item["exception"] as? String).flatMap(CrashExceptionKind.init(rawValue:)),
                        let signal = (item["signal"] as? String).flatMap(CrashSignalKind.init(rawValue:)),
                        let count = (item["count"] as? NSNumber)?.intValue, (0...10_000).contains(count)
                    else { return nil }
                    kinds.append(.init(exception: exception, signal: signal, count: count))
                }
            }
            return DeviceHealthSummary(
                windowDays: windowDays, crashes: counts[0], hangs: counts[1], cpuExceptions: counts[2],
                diskWriteExceptions: counts[3], memoryExits: counts[4], watchdogExits: counts[5], longestHangMs: hang,
                launchMedianMs: launch, peakMemoryMB: memory, crashKinds: kinds)
        }
    }

    /// Which of a picture's ImageIO properties identify where it was taken, when, with what or by
    /// whom. The technical ones every JPEG or PNG carries (size, colour, resolution, orientation)
    /// don't count.
    enum ImageMetadata {
        private static let allowed: [String: Set<String>] = [
            "{Exif}": [
                "ExifVersion", "PixelXDimension", "PixelYDimension", "ColorSpace", "ComponentsConfiguration",
                "FlashPixVersion",
            ],
            "{TIFF}": ["Orientation", "XResolution", "YResolution", "ResolutionUnit"],
            "{PNG}": ["Gamma", "InterlaceType", "XPixelsPerMeter", "YPixelsPerMeter", "sRGBIntent"],
            "{JFIF}": ["JFIFVersion", "XDensity", "YDensity", "DensityUnit", "IsProgressive"],
        ]

        static func identifying(in properties: [CFString: Any]) -> [String] {
            var found: [String] = []
            for (key, value) in properties {
                let name = key as String
                guard name.hasPrefix("{") else { continue }
                guard let permitted = allowed[name] else {
                    found.append(name)
                    continue
                }
                for field in (value as? [CFString: Any])?.keys ?? [:].keys where !permitted.contains(field as String) {
                    found.append("\(name).\(field)")
                }
            }
            return found.sorted()
        }
    }
#endif
