import Foundation
import Models

// The 24d bodies: a note to the support queue. Same rules as APIV1.swift: these mirror
// contract.json, and the contract tests check them against its examples.

extension APIV1 {
    /// A note is not repeated by the client on a timeout unless every try carries the same
    /// `submissionId`, which it does, so the backend returns the same ticket. No App Attest:
    /// support has to work on a device that can't attest, and it costs nothing.
    public static let sendFeedback = Endpoint(
        id: "sendFeedback", method: "POST", path: "/v1/feedback", requiresAuth: true, idempotent: true,
        maxBodyBytes: 1_048_576)

    /// The contract's limits for a note.
    public enum FeedbackLimits {
        public static let messageMaxCharacters = 2_000
        public static let attachmentMaxBytes = FeedbackScreenshot.maximumBytes
    }

    public struct FeedbackRequest: Codable, Sendable, Equatable {
        public struct Diagnostics: Codable, Sendable, Equatable {
            public var appVersion: String
            public var build: String
            public var systemVersion: String
            public var deviceModel: String
        }

        public struct ClosetCounts: Codable, Sendable, Equatable {
            public var pieces: Int
            public var looks: Int
            public var suitcases: Int
        }

        /// 31: the phone's crash and speed counts, only when she approved sharing them. Numbers and
        /// fixed names; there is no field for a stack, a name or any text.
        public struct DeviceHealth: Codable, Sendable, Equatable {
            public struct CrashKind: Codable, Sendable, Equatable {
                public var exception: String
                public var signal: String
                public var count: Int
            }

            public var windowDays: Int
            public var crashes: Int
            public var hangs: Int
            public var cpuExceptions: Int
            public var diskWriteExceptions: Int
            public var memoryExits: Int
            public var watchdogExits: Int
            public var longestHangMs: Int?
            public var launchMedianMs: Int?
            public var peakMemoryMB: Int?
            public var crashKinds: [CrashKind]?
        }

        public struct Attachment: Codable, Sendable, Equatable {
            public var contentType: String
            public var data: String
        }

        /// Release (guideline 1.2): the result a report is about. Never a provider or a model.
        public struct AIReport: Codable, Sendable, Equatable {
            public var subject: String
            public var reason: String
            public var resultId: String
            public var actionId: String?
            public var lookVersion: String?
            public var madeBy: String
            public var madeAt: String
            public var hidden: Bool
        }

        public var submissionId: String
        public var kind: String
        public var message: String
        public var replyTo: String?
        public var diagnostics: Diagnostics?
        public var closetCounts: ClosetCounts?
        public var deviceHealth: DeviceHealth?
        public var attachment: Attachment?
        public var aiReport: AIReport?

        /// Release: a report about an AI result, as kind `aiReport`. The picture goes only when
        /// she ticked Include the picture (`AIReport.picture`), as the cleaned JPEG.
        public init(_ submission: AIReportSubmission) {
            let report = submission.report
            let target = report.target
            submissionId = submission.id
            kind = "aiReport"
            message = report.message
            aiReport = AIReport(
                subject: target.subject.rawValue, reason: report.reason.rawValue,
                resultId: Self.resultID(target.resultID), actionId: target.actionID,
                lookVersion: target.lookVersion?.rawValue, madeBy: target.madeBy.rawValue,
                madeAt: APIV1.formatDate(target.madeAt), hidden: report.hidden)
            attachment = report.picture.map {
                Attachment(contentType: "image/jpeg", data: $0.data.base64EncodedString())
            }
        }

        /// The contract allows letters, digits, `_` and `-`, at most 64. The app's IDs fit;
        /// anything else is sent as a stand-in rather than refused, since the report matters more.
        static func resultID(_ id: String) -> String {
            id.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil ? id : "unknown"
        }

        /// Exactly what is in the note, and nothing else: there is no field here for anything she
        /// didn't see on the page (`FeedbackNote.sentValues`).
        public init(_ submission: FeedbackSubmission) {
            let note = submission.note
            submissionId = submission.id
            kind = note.kind.rawValue
            message = note.message
            replyTo = note.replyAddress
            diagnostics = note.diagnostics.map {
                Diagnostics(
                    appVersion: $0.appVersion, build: $0.build, systemVersion: $0.systemVersion,
                    deviceModel: $0.deviceModel)
            }
            closetCounts = note.closetCounts.map {
                ClosetCounts(pieces: $0.pieces, looks: $0.looks, suitcases: $0.suitcases)
            }
            deviceHealth = note.deviceHealth.map {
                DeviceHealth(
                    windowDays: $0.windowDays, crashes: $0.crashes, hangs: $0.hangs, cpuExceptions: $0.cpuExceptions,
                    diskWriteExceptions: $0.diskWriteExceptions, memoryExits: $0.memoryExits,
                    watchdogExits: $0.watchdogExits, longestHangMs: $0.longestHangMs,
                    launchMedianMs: $0.launchMedianMs, peakMemoryMB: $0.peakMemoryMB,
                    crashKinds: $0.crashKinds.isEmpty
                        ? nil
                        : $0.crashKinds.map {
                            DeviceHealth.CrashKind(
                                exception: $0.exception.rawValue, signal: $0.signal.rawValue, count: $0.count)
                        })
            }
            // The screenshot is always a JPEG (`PhotoCleaner`).
            attachment = note.screenshot.map {
                Attachment(contentType: "image/jpeg", data: $0.data.base64EncodedString())
            }
        }
    }

    public struct FeedbackReceipt: Codable, Sendable, Equatable {
        public struct Ticket: Codable, Sendable, Equatable {
            public var ref: String
            public var receivedAt: String
            public var hasAttachment: Bool
        }
        public var ticket: Ticket
    }
}
