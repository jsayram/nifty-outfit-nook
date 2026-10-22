import ImageIO
import Testing
import UIKit

@testable import Features

/// Phase 33b (after PR 101): the camera's try-on photo is kept at no more than 2,048 pixels.
@MainActor
struct CameraPhotoSizeTests {
    /// A drawn picture (never a photo of anyone), as a JPEG.
    private func jpeg(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image {
            UIColor.systemTeal.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    @Test func aBigPhotoIsScaledDownKeepingItsShape() async throws {
        let capped = try #require(await CameraPhotoSize.capped(try jpeg(width: 3_024, height: 4_032)))
        let found = try size(of: capped)
        #expect(max(found.width, found.height) <= 2_048)
        // 3 wide to 4 tall stays 3 wide to 4 tall.
        #expect(found.height == 2_048 && abs(found.width - 1_536) <= 1)
    }

    @Test func aSmallerPhotoIsNotEnlarged() async throws {
        let capped = try #require(await CameraPhotoSize.capped(try jpeg(width: 900, height: 1_200)))
        let found = try size(of: capped)
        #expect(found.width == 900 && found.height == 1_200)
    }

    @Test func somethingThatIsNotAPhotoGivesNothing() async {
        #expect(await CameraPhotoSize.capped(Data("not a photo".utf8)) == nil)
    }
}
