import CloudKit
import Foundation
import Models

// Phase 20a persistence spike: a garment as a `CKRecord` in her private zone. Only the record
// name, the type and a revision are plain fields; everything about the piece goes in
// `encryptedValues`, which CloudKit encrypts with her keys and, with Advanced Data Protection on,
// end to end (THREAT_MODEL.md F2, DATA_MAP.md). Which fields are encrypted is settled for good in
// Phase 20b, before the schema is promoted, since encryption can't be added to a field later.

enum SpikeCloudKitMapping {
    static let zoneID = CKRecordZone.ID(zoneName: "Closet", ownerName: CKCurrentUserDefaultName)
    static let recordType = "Garment"
    /// The one plain field. Everything else is encrypted.
    static let plainKeys: Set<String> = ["revision"]
    static let payloadKey = "garment"

    static func record(for garment: Garment, revision: Int) throws -> CKRecord {
        let record = CKRecord(
            recordType: recordType, recordID: CKRecord.ID(recordName: garment.id.rawValue, zoneID: zoneID))
        record["revision"] = revision as NSNumber
        // One encrypted JSON field keeps the spike short; Phase 20b decides between this and one
        // encrypted field per property, which merges would need for field-level server queries.
        record.encryptedValues[payloadKey] = try JSONEncoder().encode(garment) as NSData
        return record
    }

    static func garment(from record: CKRecord) throws -> Garment {
        guard let data = record.encryptedValues[payloadKey] as? Data else { throw StoreError.unavailable }
        return try JSONDecoder().decode(Garment.self, from: data)
    }

    /// The record's system fields (its ID and change tag), as the app keeps them next to the
    /// local record so the next save can say which server version it's based on.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) throws -> CKRecord? {
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
