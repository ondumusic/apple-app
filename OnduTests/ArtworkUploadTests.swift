import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Ondu

struct ArtworkUploadTests {

    /// A JPEG of the given size, standing in for something off a camera.
    private func makeImage(width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
                properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// The server renders its own variants from whatever it gets, so sending a
    /// 48-megapixel photo is a long upload to have it thrown away at the other end.
    @Test func shrinksSomethingLargerThanWeEverDraw() throws {
        let prepared = try ArtworkUpload.prepare(data: try makeImage(width: 6000, height: 4000))
        let size = try pixelSize(of: prepared.data)
        #expect(max(size.width, size.height) == ArtworkUpload.maxPixels)
    }

    /// Artists aren't square and the server keeps the source ratio, so neither should we.
    @Test func keepsTheAspectRatio() throws {
        let prepared = try ArtworkUpload.prepare(data: try makeImage(width: 4000, height: 2000))
        let size = try pixelSize(of: prepared.data)
        #expect(size.width == 2 * size.height)
    }

    @Test func leavesSomethingSmallerAlone() throws {
        let prepared = try ArtworkUpload.prepare(data: try makeImage(width: 800, height: 600))
        let size = try pixelSize(of: prepared.data)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test func sendsJPEGWhateverWentIn() throws {
        let prepared = try ArtworkUpload.prepare(data: try makeImage(width: 500, height: 500))
        #expect(prepared.mimeType == "image/jpeg")
        #expect(prepared.filename.hasSuffix(".jpg"))
    }

    @Test func refusesSomethingThatIsntAnImage() {
        #expect(throws: ArtworkUpload.Failure.self) {
            try ArtworkUpload.prepare(data: Data("not an image".utf8))
        }
    }
}

struct ArtworkErrorDecodingTests {

    @Test func decodesTheTwoTheServerNames() {
        #expect(APIService.ArtworkError.decode(Data(#"{"error":"invalid_image"}"#.utf8)) == .notAnImage)
        #expect(APIService.ArtworkError.decode(Data(#"{"error":"too_large"}"#.utf8)) == .tooLarge)
    }

    @Test func leavesAnythingElseUndecoded() {
        #expect(APIService.ArtworkError.decode(Data(#"{"error":"something_else"}"#.utf8)) == nil)
        #expect(APIService.ArtworkError.decode(Data("not json".utf8)) == nil)
    }
}
