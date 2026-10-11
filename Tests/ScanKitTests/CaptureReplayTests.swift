import CryptoKit
import Foundation
import Testing
@testable import ScanKit

/// Replays real scanner traffic through the parser and side assembly. Captures hold scanned pages
/// and the scanner's serial number, so they stay out of the repository: set FASTSCAN_REPLAYS to a
/// folder of `<name>.replay` files (each scanner payload after TRDT's reply, as a 4-byte
/// big-endian length and the bytes) with a `<name>.json` of the expected sides and ending.
private let replayFolder = ProcessInfo.processInfo.environment["FASTSCAN_REPLAYS"].map { URL(filePath: $0, directoryHint: .isDirectory) }

@Suite(.enabled(if: replayFolder != nil))
struct CaptureReplayTests {
    static var captures: [String] {
        guard let folder = replayFolder else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".replay") }.map { String($0.dropLast(".replay".count)) }.sorted()
    }

    struct Expected: Decodable {
        struct Side: Decodable, Equatable {
            var side: String
            var sha256: String
            var width: Int
            var height: Int
        }
        var sides: [Side]
        var ending: String
    }

    @Test(arguments: captures)
    func replaysLikeTheScannerSentIt(name: String) throws {
        let folder = try #require(replayFolder)
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: folder.appending(path: "\(name).json")))
        var payloads = Self.records(try [UInt8](Data(contentsOf: folder.appending(path: "\(name).replay"))))[...]

        // The same order of checks as ScannerSession's IMG loop.
        var assembler = SideAssembler()
        var sides: [Expected.Side] = []
        var ending = "stream ended"
        loop: while let payload = payloads.popFirst() {
            guard payload.starts(with: Array("IMG x".utf8)) else { break }
            let reply = try ESCI2.parseReplyBlock(payload)
            let next = reply.dataLength > 0 ? payloads.popFirst() : []
            let data = try #require(next)
            #expect(data.count == reply.dataLength)
            if reply.token("atn")?.words == ["CAN "] {
                ending = "atn CAN"
                break
            }
            do {
                for (side, jpeg) in try assembler.take(reply, data: data) {
                    let image = try ScannerSession.decode(jpeg, side: side)
                    sides.append(Expected.Side(side: side.rawValue, sha256: SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined(),
                                               width: image.width, height: image.height))
                }
            } catch ScannerError.jammed {
                ending = "err PJ"
                break loop
            } catch ScannerError.doubleFeed {
                ending = "err DFED"
                break loop
            }
            if assembler.isFinished {
                ending = "finished"
                break
            }
        }

        #expect(sides == expected.sides)
        #expect(ending == expected.ending)
    }

    static func records(_ bytes: [UInt8]) -> [[UInt8]] {
        var records: [[UInt8]] = []
        var index = 0
        while index + 4 <= bytes.count {
            let length = Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            records.append(Array(bytes[index + 4..<index + 4 + length]))
            index += 4 + length
        }
        return records
    }
}
