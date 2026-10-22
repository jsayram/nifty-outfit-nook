import Foundation
import Models

// The 33a bodies: POST /v1/try-on's request and answer. Same rules as APIV1.swift: these mirror
// contract.json, and the contract tests round-trip its golden examples through them.
//
// What leaves the phone is only the faceless photo on the studio backdrop and the garment photos,
// each garment with its ID, category and kind (the backend builds the prompt from those alone).
// The first POST starts the job and answers 409 action_in_progress; the client asks again with the
// same Idempotency-Key and the same body until the picture comes back.

extension APIV1 {
    public struct TryOnImage: Codable, Sendable, Equatable {
        public var contentType: String
        /// Base64 of the image bytes.
        public var data: String

        public init(jpeg: Data) {
            contentType = "image/jpeg"
            data = jpeg.base64EncodedString()
        }
    }

    public struct TryOnGarment: Codable, Sendable, Equatable {
        public var id: String
        public var category: String
        public var kind: String?
        public var image: TryOnImage
    }

    public struct TryOnRequest: Codable, Sendable, Equatable {
        public var contextRevision: String
        public var consentVersion: String
        public var person: TryOnImage
        public var garments: [TryOnGarment]

        /// The only place a try-on becomes something that can leave the phone.
        public init(_ call: TryOnCall) {
            contextRevision = call.contextRevision
            consentVersion = call.consentVersion
            person = TryOnImage(jpeg: call.person)
            garments = call.garments.prefix(TryOnCall.maximumGarments).map {
                TryOnGarment(
                    id: $0.id.rawValue, category: $0.category.rawValue, kind: $0.subKind?.rawValue,
                    image: TryOnImage(jpeg: $0.jpeg))
            }
        }
    }

    public struct TryOnResultImage: Codable, Sendable, Equatable {
        public var contentType: String
        public var data: String

        public init(contentType: String, data: Data) {
            self.contentType = contentType
            self.data = data.base64EncodedString()
        }

        /// The bytes, if they are base64 of a JPEG, PNG or WebP image.
        public var bytes: Data? {
            guard ["image/jpeg", "image/png", "image/webp"].contains(contentType),
                let bytes = Data(base64Encoded: data), !bytes.isEmpty
            else { return nil }
            return bytes
        }
    }

    public struct TryOnResult: Codable, Sendable, Equatable {
        public var image: TryOnResultImage
    }

    public struct TryOnResponse: Codable, Sendable, Equatable {
        public var action: PaidAction
        public var result: TryOnResult
        public var usage: UsageCategory
    }
}
