import Testing
@testable import ScanKit

/// Random and damaged scanner bytes must be rejected with a `ScannerError`, never a crash.
@Suite struct ParserFuzzTests {
    /// SplitMix64, so a failure reproduces from its seed.
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Bytes the protocol uses, so random input often looks nearly valid.
    static let alphabet = Array("#hdixIMG ABCDEFPSTRNOK0123456789-+x".utf8) + [0x00, 0xFF, 0x0C, 0x38]

    static func randomBytes(_ count: Int, using generator: inout Generator) -> [UInt8] {
        (0..<count).map { _ in
            Bool.random(using: &generator) ? alphabet.randomElement(using: &generator)! : UInt8.random(in: 0...255, using: &generator)
        }
    }

    /// Valid blocks from the captures, to damage.
    static let seeds: [[UInt8]] = [
        ESCI2Tests.replyBlock("IMG x0000265#errADF DFED#psti0005100d000i0009300#typIMGA"),
        ESCI2Tests.replyBlock("IMG x0040000#typIMGA#atnCAN "),
        ESCI2Tests.replyBlock("IMG x0000000#peni0005052i0006622#typIMGB"),
        Array("#PRDh007FF-680W".utf8) + [0] + Array("#VERh008ADF 18P4#CRPRANGi-000020d020".utf8),
        ESCI2.encode(ESCI2.scanParameters(sides: .duplex, dpi: 600, length: 1550)),
    ]

    static func damaged(_ seed: [UInt8], using generator: inout Generator) -> [UInt8] {
        var bytes = seed
        for _ in 0..<Int.random(in: 1...4, using: &generator) where !bytes.isEmpty {
            let index = Int.random(in: 0..<bytes.count, using: &generator)
            switch Int.random(in: 0..<3, using: &generator) {
            case 0: bytes[index] = alphabet.randomElement(using: &generator)!
            case 1: bytes.removeSubrange(index...)
            default: bytes.insert(alphabet.randomElement(using: &generator)!, at: index)
            }
        }
        return bytes
    }

    func parseEverything(_ bytes: [UInt8]) {
        _ = try? ESCI2.parseHeader(Array(bytes.prefix(12)))
        _ = try? ESCI2.parseTokens(bytes[...], stopAtNull: false)
        _ = try? ESCI2.parseTokens(bytes[...], stopAtNull: true)
        if let reply = try? ESCI2.parseReplyBlock(bytes) {
            var assembler = SideAssembler()
            _ = try? assembler.take(reply, data: Array(bytes.prefix(8)))
        }
        _ = try? ScannerSession.checkStatus(bytes)
    }

    @Test(arguments: 0..<8)
    func randomBytesNeverCrash(seed: UInt64) {
        var generator = Generator(state: seed)
        for _ in 0..<5_000 {
            parseEverything(Self.randomBytes(Int.random(in: 0...80, using: &generator), using: &generator))
        }
    }

    @Test(arguments: 0..<8)
    func damagedRealBlocksNeverCrash(seed: UInt64) {
        var generator = Generator(state: seed)
        for _ in 0..<5_000 {
            parseEverything(Self.damaged(Self.seeds.randomElement(using: &generator)!, using: &generator))
        }
    }

    @Test func signedLengthsAreRejected() {
        #expect(throws: ScannerError.self) { try ESCI2.parseReplyBlock(ESCI2Tests.replyBlock("IMG x-000001")) }
        // `h-01` isn't a length, so it reads as a word rather than a byte string.
        #expect((try? ESCI2.parseTokens(Array("#PRDh-01".utf8)[...]))?.first?.byteStrings == [])
    }
}
