import Fixtures
import Foundation
import ImageIO
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Services

/// 33a: the whole try-on pipeline on the phone, with drawn pictures, a temporary photo folder and
/// a recording stand-in for the backend: what is sent (only the faceless photo and the garment
/// photos, with no metadata), when nothing is sent (fail closed), and the head going back on.
struct PhoneTryOnTests {
    let folder: URL
    let files: PhotoFileStore
    let paid = RecordingPaid()

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "tryon-\(UUID().uuidString)")
        files = PhotoFileStore(directory: folder, freeSpace: { 10_000_000_000 })
    }

    /// 32b: the backend refuses photos past the contract's pixel caps, so what the phone sends has
    /// to stay inside them. `TryOnCall` holds the sizes the contract test checks against the caps.
    @Test func sendsNoMorePixelsThanTheBackendTakes() {
        #expect(PhoneTryOn.workingSize <= TryOnCall.personSendSide)
        #expect(PhoneTryOn.garmentSize <= TryOnCall.garmentSendSide)
    }

    func pipeline(_ analyzer: SyntheticPersonAnalyzer = SyntheticPersonAnalyzer()) -> PhoneTryOn {
        PhoneTryOn(analyzer: analyzer, paid: paid, files: files, images: DrawnGarments())
    }

    /// Her try-on photo, drawn, in the photo folder.
    func photo(_ drawing: TryOnBitmap = SyntheticPerson.draw().bitmap) throws -> PhotoReference {
        let png = try #require(drawing.png())
        return .stored(EntityID(try files.add(png)))
    }

    static let pieces = [
        Garment(
            id: "g-top", name: "Striped sweater", category: .top, subKind: .sweater, colors: [.navy],
            photo: .sample("striped-sweater"), addedAt: TestTime.now),
        Garment(
            id: "g-trousers", name: "Trousers", category: .bottom, subKind: .trousers, colors: [.gray],
            photo: .sample("cut-off-trousers"), addedAt: TestTime.now),
        Garment(id: "g-words", name: "Belt", category: .accessory, subKind: .belt, addedAt: TestTime.now),
    ]

    func prepareProblem(_ pipeline: PhoneTryOn, photo: PhotoReference, pieces: [Garment] = Self.pieces) async
        -> TryOnPrepareProblem?
    {
        do {
            _ = try await pipeline.prepare(photo: photo, pieces: pieces)
            return nil
        } catch {
            return error
        }
    }

    @Test func onlyTheFacelessPhotoAndGarmentPhotosAreSent() async throws {
        let pipeline = pipeline()
        let upload = try await pipeline.prepare(photo: try photo(), pieces: Self.pieces)
        // The belt has no photo, so it isn't sent.
        #expect(upload.sent.garments.map(\.garmentID) == ["g-top", "g-trousers"])
        let dressed = try await pipeline.dress(upload, consentVersion: "tryon-1", idempotencyKey: "idem_key_33a_00000")
        let call = try #require(paid.calls.first)
        #expect(paid.calls.count == 1 && paid.keys == ["idem_key_33a_00000"])
        #expect(call.consentVersion == "tryon-1")
        // Exactly the kept bytes, so "See what was sent" shows exactly what left.
        guard case .stored(let personID) = upload.sent.person else {
            Issue.record("not stored")
            return
        }
        #expect(call.person == files.data(for: personID.rawValue))
        #expect(call.garments.map(\.id) == ["g-top", "g-trousers"])
        #expect(call.garments.map(\.subKind) == [.sweater, .trousers])
        // No face can be found in what was sent, and it has no metadata at all.
        let sent = try #require(TryOnBitmap.decode(call.person, maxPixelSize: 2_000))
        #expect(try await SyntheticPersonAnalyzer().faces(in: sent).isEmpty)
        for jpeg in [call.person] + call.garments.map(\.jpeg) {
            let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            #expect(properties[kCGImagePropertyGPSDictionary] == nil)
            #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
            // ImageIO writes its own colour space and size fields in a JPEG's Exif. Nothing else.
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let allowed: Set<String> = [
                kCGImagePropertyExifColorSpace as String, kCGImagePropertyExifPixelXDimension as String,
                kCGImagePropertyExifPixelYDimension as String,
            ]
            #expect(Set(exif.keys.map { $0 as String }).isSubset(of: allowed))
        }
        #expect(call.person.count <= TryOnCall.personMaxBytes)
        #expect(dressed == paid.reply)
    }

    @Test func herHeadGoesBackOnAndTheWorkFilesGo() async throws {
        let pipeline = pipeline()
        let upload = try await pipeline.prepare(photo: try photo(), pieces: Self.pieces)
        let work = try #require(upload.work)
        // The stand-in backend sends the faceless photo back unchanged, as the backend's fake does.
        let echoed = try #require(paid.echo(upload, files: files))
        let picture = try await pipeline.restore(echoed, upload: upload)
        guard case .stored(let id) = picture else {
            Issue.record("not stored")
            return
        }
        let restoredData = try #require(files.data(for: id.rawValue))
        let restored = try #require(TryOnBitmap.decode(restoredData, maxPixelSize: 2_000))
        #expect(try await SyntheticPersonAnalyzer().faces(in: restored).count == 1)
        let head = try #require(files.data(for: storedID(work.head)).flatMap(TryOnMask.decode))
        #expect(HeadRestore.greyLeft(in: restored, head: head, margin: 8) < 20)  // JPEG noise only
        await pipeline.discard(upload, keepingSent: true)
        for reference in work.imageReferences { #expect(files.data(for: storedID(reference)) == nil) }
        for reference in upload.sent.imageReferences { #expect(files.data(for: storedID(reference)) != nil) }
        await pipeline.discard(upload, keepingSent: false)
        for reference in upload.sent.imageReferences { #expect(files.data(for: storedID(reference)) == nil) }
    }

    // MARK: Fail closed: nothing written, nothing sent

    @Test func aFaceStillFoundAfterMaskingRefusesAndSendsNothing() async throws {
        // Something the grey didn't cover still reads as a face (a face printed on her top, say):
        // the check after masking finds it, and nothing is sent.
        let photo = try photo()
        let before = files.ids()
        let pipeline = PhoneTryOn(analyzer: SeesAFaceAfterMasking(), paid: paid, files: files, images: DrawnGarments())
        #expect(await prepareProblem(pipeline, photo: photo) == .faceStillVisible)
        #expect(files.ids() == before)
        #expect(paid.calls.isEmpty)
    }

    @Test func twoPeopleOrNoFaceOrNoPhotoSendNothing() async throws {
        let pipeline = pipeline()
        #expect(
            await prepareProblem(pipeline, photo: try photo(SyntheticPerson.draw(centers: [0.3, 0.72]).bitmap))
                == .severalPeople)
        #expect(
            await prepareProblem(pipeline, photo: try photo(SyntheticPerson.draw(facingAway: true).bitmap)) == .noFace)
        #expect(await prepareProblem(pipeline, photo: .noPhoto) == .noTryOnPhoto)
        #expect(await prepareProblem(pipeline, photo: try photo(), pieces: [Self.pieces[2]]) == .noGarmentPhotos)
        #expect(paid.calls.isEmpty)
    }

    @Test func checksThatCannotRunRefuse() async throws {
        let pipeline = PhoneTryOn(analyzer: BrokenAnalyzer(), paid: paid, files: files, images: DrawnGarments())
        #expect(await prepareProblem(pipeline, photo: try photo()) == .checksUnavailable)
        #expect(paid.calls.isEmpty)
    }

    private func storedID(_ reference: PhotoReference) -> String {
        if case .stored(let id) = reference { id.rawValue } else { "" }
    }
}

/// Garment photos drawn for the sample names (`SyntheticGarmentPhotos`).
struct DrawnGarments: ImageProvider {
    func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
        guard case .sample(let name) = reference, let scene = SyntheticGarmentPhotos.Scene(rawValue: name) else {
            return nil
        }
        return SyntheticGarmentPhotos.jpeg(scene, width: 600, height: 750, location: true)
    }
}

/// Reads the drawing like `SyntheticPersonAnalyzer`, but always finds a face when checking.
struct SeesAFaceAfterMasking: PersonAnalyzing {
    func analyze(_ image: TryOnBitmap) async throws(PersonAnalysisFailed) -> PersonAnalysis {
        try await SyntheticPersonAnalyzer().analyze(image)
    }
    func faces(in image: TryOnBitmap) async throws(PersonAnalysisFailed) -> [DetectedFace] {
        [DetectedFace(box: CGRect(x: 200, y: 300, width: 40, height: 50), confidence: 0.35)]
    }
    func pose(in image: TryOnBitmap) async -> BodyPose? { nil }
}

/// Vision failing, as on a simulator.
struct BrokenAnalyzer: PersonAnalyzing {
    func analyze(_ image: TryOnBitmap) async throws(PersonAnalysisFailed) -> PersonAnalysis {
        throw PersonAnalysisFailed()
    }
    func faces(in image: TryOnBitmap) async throws(PersonAnalysisFailed) -> [DetectedFace] {
        throw PersonAnalysisFailed()
    }
    func pose(in image: TryOnBitmap) async -> BodyPose? { nil }
}

/// The backend, recording each try-on call and answering with a fixed picture.
final class RecordingPaid: PaidActionService, Sendable {
    private let state = Mutex<[(TryOnCall, String)]>([])
    let reply = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])

    var calls: [TryOnCall] { state.withLock { $0.map(\.0) } }
    var keys: [String] { state.withLock { $0.map(\.1) } }

    func usage() async throws(CloudLimitProblem) -> CloudUsage { CloudUsage(allowances: [], paused: []) }

    func run(_ request: PaidActionRequest, idempotencyKey: String) async throws(CloudLimitProblem)
        -> PaidActionReceipt
    {
        guard case .tryOn(let call) = request else { throw .didNotFinish(retryAfterSeconds: nil) }
        state.withLock { $0.append((call, idempotencyKey)) }
        return PaidActionReceipt(
            id: "act_1", feature: .tryOn, replayed: false,
            usage: UsageAllowance(
                category: .tryOn, usedToday: 1, limitToday: 3, usedThisMonth: 1, limitThisMonth: 30, resetsAt: nil),
            tryOnImage: reply)
    }

    /// The faceless photo as sent, as a stand-in "dressed" picture.
    func echo(_ upload: TryOnUpload, files: PhotoFileStore) -> Data? {
        guard case .stored(let id) = upload.sent.person else { return nil }
        return files.data(for: id.rawValue)
    }
}
