import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Gets a picked image ready to send.
///
/// Downscaled first rather than posted as-is: the server takes up to 25MB and 10000px and
/// renders its own variants from whatever it gets, so a 48-megapixel phone photo spends a
/// long upload to be thrown away at the other end. 2000px is larger than anything the app
/// draws an artist at.
nonisolated enum ArtworkUpload {
    static let maxPixels = 2000
    static let jpegQuality = 0.85

    struct Prepared: Sendable {
        let data: Data
        let filename: String
        let mimeType: String
    }

    enum Failure: Error {
        case notAnImage
    }

    static func prepare(contentsOf url: URL) throws -> Prepared {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { throw Failure.notAnImage }
        return try prepare(source: source)
    }

    static func prepare(data: Data) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw Failure.notAnImage }
        return try prepare(source: source)
    }

    private static func prepare(source: CGImageSource) throws -> Prepared {
        // Decoded straight to the size we want: the full-size bitmap never exists, which
        // matters for the photos people actually pick.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw Failure.notAnImage }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.notAnImage }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.notAnImage }

        return Prepared(data: encoded as Data, filename: "artwork.jpg", mimeType: "image/jpeg")
    }
}
