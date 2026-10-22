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

        public struct Attachment: Codable, Sendable, Equatable {
            public var contentType: String
            public var data: String
        }

        public var submissionId: String
        public var kind: String
        public var message: String
        public var replyTo: String?
        public var diagnostics: Diagnostics?
        public var closetCounts: ClosetCounts?
        public var attachment: Attachment?

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
