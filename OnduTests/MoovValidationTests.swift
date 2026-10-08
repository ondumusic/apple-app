import Foundation
import Testing
@testable import Ondu

struct MoovValidationTests {

    // MARK: - Helper to build MP4 atoms

    /// Builds a minimal MP4 atom: 4-byte big-endian size + 4-byte ASCII type + optional body
    private func atom(_ type: String, body: Data = Data()) -> Data {
        let size = UInt32(8 + body.count)
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: size.bigEndian) { Array($0) })
        data.append(contentsOf: type.utf8)
        data.append(body)
        return data
    }

    /// Builds an atom with size=0 (meaning "extends to end of file")
    private func atomSizeZero(_ type: String) -> Data {
        var data = Data()
        data.append(contentsOf: [0, 0, 0, 0]) // size = 0
        data.append(contentsOf: type.utf8)
        return data
    }

    private func writeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        try data.write(to: url)
        return url
    }

    // MARK: - Valid files

    @Test func validM4AWithMoov() throws {
        // ftyp + mdat + moov
        let file = atom("ftyp", body: Data(repeating: 0, count: 12))
            + atom("mdat", body: Data(repeating: 0, count: 100))
            + atom("moov", body: Data(repeating: 0, count: 50))
        let url = try writeTempFile(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DownloadService.testHasMoovAtom(at: url))
    }

    @Test func validM4AWithFreeAtom() throws {
        // ftyp + free + mdat + moov
        let file = atom("ftyp", body: Data(repeating: 0, count: 12))
            + atom("free")
            + atom("mdat", body: Data(repeating: 0, count: 100))
            + atom("moov", body: Data(repeating: 0, count: 50))
        let url = try writeTempFile(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DownloadService.testHasMoovAtom(at: url))
    }

    @Test func moovBeforeMdat() throws {
        // ftyp + moov + mdat (faststart layout)
        let file = atom("ftyp", body: Data(repeating: 0, count: 12))
            + atom("moov", body: Data(repeating: 0, count: 50))
            + atom("mdat", body: Data(repeating: 0, count: 100))
        let url = try writeTempFile(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DownloadService.testHasMoovAtom(at: url))
    }

    // MARK: - mdat size=0 (no faststart, ffmpeg output)

    @Test func mdatSizeZeroWithMoovAfter() throws {
        // ftyp + free + mdat(size=0) + audio data + moov
        // This is the common ffmpeg output layout without -movflags +faststart
        let audioData = Data(repeating: 0xAB, count: 1000)
        let moov = atom("moov", body: Data(repeating: 0, count: 50))
        let file = atom("ftyp", body: Data(repeating: 0, count: 12))
            + atom("free")
            + atomSizeZero("mdat")
            + audioData
            + moov
        let url = try writeTempFile(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DownloadService.testHasMoovAtom(at: url))
    }

    // MARK: - Invalid/truncated files

    @Test func truncatedNoMoov() throws {
        // ftyp + mdat only — truncated download
        let file = atom("ftyp", body: Data(repeating: 0, count: 12))
            + atom("mdat", body: Data(repeating: 0, count: 100))
        let url = try writeTempFile(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!DownloadService.testHasMoovAtom(at: url))
    }

    @Test func mdatSizeZeroNoMoov() throws {
        // ftyp + mdat(size=0) + audio data but NO moov — truly truncated
        let file = atom("ftyp", body: Data(repeating: 0, count: 12))
            + atomSizeZero("mdat")
            + Data(repeating: 0xAB, count: 1000)
        let url = try writeTempFile(file)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!DownloadService.testHasMoovAtom(at: url))
    }

    @Test func emptyFile() throws {
        let url = try writeTempFile(Data())
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!DownloadService.testHasMoovAtom(at: url))
    }

    @Test func tooSmallFile() throws {
        let url = try writeTempFile(Data([0x00, 0x00, 0x00]))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(!DownloadService.testHasMoovAtom(at: url))
    }

    @Test func nonExistentFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID().uuidString).m4a")
        #expect(!DownloadService.testHasMoovAtom(at: url))
    }
}
