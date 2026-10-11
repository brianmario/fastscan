import Foundation
import Testing
@testable import ScanKit

/// Byte values from docs/esci2-protocol.md.
@Suite struct ESCI2Tests {
    // MARK: Packets

    @Test func lockPacket() {
        #expect(ESCI2.packet(.lock, payload: ESCI2.lockPayload) == [
            0x49, 0x53, 0x21, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00,
            0x01, 0xA0, 0x04, 0x00, 0x00, 0x01, 0x2C,
        ])
    }

    @Test func unlockPacketIsEmpty() {
        #expect(ESCI2.packet(.unlock) == [0x49, 0x53, 0x21, 0x01, 0x00, 0x0C, 0, 0, 0, 0, 0, 0])
    }

    @Test func requestLengthCountsTheDataHeader() {
        let packet = ESCI2.request(ESCI2.commandBlock("INFO"), replyLength: 64)
        #expect(packet[0..<12] == [0x49, 0x53, 0x20, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x14, 0x00, 0x00])
        #expect(packet[12..<20] == [0x00, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x40])
        #expect(ESCI2.ascii(packet[20...]) == "INFOx0000000")
    }

    @Test func fetchRequestCarriesOnlyTheReplyLength() {
        #expect(ESCI2.request([], replyLength: 0x124)[6...] == [
            0x00, 0x00, 0x00, 0x08, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x24,
        ])
    }

    @Test func modeByte() {
        #expect(ESCI2.modeBytes("Y") == [0x1C, 0x59])
        #expect(ESCI2.modeBytes("X") == [0x1C, 0x58])
    }

    @Test func parsesTheGreetingHeader() throws {
        let header = try ESCI2.parseHeader([0x49, 0x53, 0x80, 0x00, 0x38, 0x0C, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00])
        #expect(header == ESCI2.PacketHeader(type: 0x8000, payloadLength: 5))
    }

    @Test func parsesALargeReplyLength() throws {
        let header = try ESCI2.parseHeader([0x49, 0x53, 0xA0, 0x00, 0x38, 0x0C, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00])
        #expect(header == ESCI2.PacketHeader(type: 0xA000, payloadLength: 0x40000))
    }

    @Test(arguments: [
        [UInt8]([0x49, 0x53, 0xA0, 0x00, 0x00, 0x0C, 0, 0, 0, 0, 0, 0]),  // host marker, not scanner
        [0x48, 0x53, 0xA0, 0x00, 0x38, 0x0C, 0, 0, 0, 0, 0, 0],
        [0x49, 0x53, 0xA0, 0x00, 0x38, 0x0C, 0, 0, 0, 0, 0],
    ])
    func rejectsABadHeader(bytes: [UInt8]) {
        #expect(throws: ScannerError.self) { try ESCI2.parseHeader(bytes) }
    }

    // MARK: Commands

    @Test func commandBlocks() {
        #expect(ESCI2.ascii(ESCI2.commandBlock("INFO")) == "INFOx0000000")
        #expect(ESCI2.ascii(ESCI2.commandBlock("IMG")) == "IMG x0000000")
        #expect(ESCI2.ascii(ESCI2.commandBlock("PARA", parameterLength: 1000)) == "PARAx00003E8")
    }

    @Test func parsesAReplyBlockAnnouncingData() throws {
        let block = try ESCI2.parseReplyBlock(Self.replyBlock("INFOx0000124"))
        #expect(block == ESCI2.ReplyBlock(command: "INFO", dataLength: 0x124, tokens: []))
    }

    @Test func parsesAnImageReplyBlock() throws {
        let block = try ESCI2.parseReplyBlock(Self.replyBlock("IMG x0040000#typIMGA#psti0002530d000i0003311"))
        #expect(block.command == "IMG ")
        #expect(block.dataLength == 0x40000)
        #expect(block.tokens == [
            ESCI2.Token("typ", [.word("IMGA")]),
            ESCI2.Token("pst", [.long(2530), .short(0), .long(3311)]),
        ])
    }

    @Test func replyBlockStopsAtANullByte() throws {
        var bytes = Array("PARAx0000000#parOK  ".utf8)
        bytes += [UInt8](repeating: 0, count: 64 - bytes.count)
        #expect(try ESCI2.parseReplyBlock(bytes).tokens == [ESCI2.Token("par", [.word("OK  ")])])
    }

    @Test func rejectsAReplyBlockWithoutLength() {
        #expect(throws: ScannerError.self) { try ESCI2.parseReplyBlock(Self.replyBlock("INFOy0000000")) }
    }

    // MARK: Tokens

    @Test func parsesSeveralFieldsInOneToken() throws {
        #expect(try ESCI2.parseTokens(Array("#ACQi0000000i0000000i0002550i0010800".utf8)[...]) == [
            ESCI2.Token("ACQ", [.long(0), .long(0), .long(2550), .long(10800)]),
        ])
    }

    @Test func parsesByteStringsByLength() throws {
        let tokens = try ESCI2.parseTokens(Array("#PRDh007FF-680W#VERh008ADF 18P4#EXI".utf8)[...])
        #expect(tokens == [
            ESCI2.Token("PRD", [.bytes(Array("FF-680W".utf8))]),
            ESCI2.Token("VER", [.bytes(Array("ADF 18P4".utf8))]),
            ESCI2.Token("EXI"),
        ])
    }

    @Test func skipsTheZeroPaddingAfterAByteString() throws {
        // As the scanner sends INFO: FF-680W is 7 bytes, padded with one zero; the serial number
        // here is 10, padded with two.
        let bytes = Array("#PRDh007FF-680W".utf8) + [0] + Array("#S/Nh00AABCDEFGHIJ".utf8) + [0, 0] + Array("#AFM".utf8)
        #expect(try ESCI2.parseTokens(bytes[...]) == [
            ESCI2.Token("PRD", [.bytes(Array("FF-680W".utf8))]),
            ESCI2.Token("S/N", [.bytes(Array("ABCDEFGHIJ".utf8))]),
            ESCI2.Token("AFM"),
        ])
    }

    @Test func aHashInsideAByteStringDoesNotEndTheToken() throws {
        let tokens = try ESCI2.parseTokens(Array("#S/Nh004A#B##DFMd100".utf8)[...])
        #expect(tokens == [ESCI2.Token("S/N", [.bytes(Array("A#B#".utf8))]), ESCI2.Token("DFM", [.short(100)])])
    }

    @Test func parsesWordsAndMixedFields() throws {
        let tokens = try ESCI2.parseTokens(Array("#ADFAREAd850i0001550#COLLISTC024M008#FMTLISTJPG #CRPRANGi-000020d020#IMXi0065535xFFFFFFF".utf8)[...])
        #expect(tokens == [
            ESCI2.Token("ADF", [.word("AREA"), .short(850), .long(1550)]),
            ESCI2.Token("COL", [.word("LIST"), .word("C024"), .word("M008")]),
            ESCI2.Token("FMT", [.word("LIST"), .word("JPG ")]),
            ESCI2.Token("CRP", [.word("RANG"), .long(-20), .short(20)]),
            ESCI2.Token("IMX", [.long(65535), .hex(0xFFFFFFF)]),
        ])
    }

    @Test func rejectsTextOutsideAToken() {
        #expect(throws: ScannerError.self) { try ESCI2.parseTokens(Array("PRD#VER".utf8)[...]) }
    }

    @Test func encodesFields() {
        #expect(ESCI2.ascii(ESCI2.Field.short(90).encoded) == "d090")
        #expect(ESCI2.ascii(ESCI2.Field.long(300).encoded) == "i0000300")
        #expect(ESCI2.ascii(ESCI2.Field.long(-20).encoded) == "i-000020")
        #expect(ESCI2.ascii(ESCI2.Field.hex(0xFFFFFFF).encoded) == "xFFFFFFF")
        #expect(ESCI2.Field.bytes(Array("FF-680W".utf8)).encoded == Array("h007FF-680W".utf8) + [0])
        #expect(ESCI2.ascii(ESCI2.Field.word("OFF").encoded) == "OFF ")
        #expect(ESCI2.Field.bytes([0x20, 0, 0, 0, 0x20, 0, 0, 0, 0x20]).encoded == Array("h009".utf8) + [0x20, 0, 0, 0, 0x20, 0, 0, 0, 0x20, 0, 0, 0])
    }

    @Test func gammaTableRoundTripsThroughItsHashByte() throws {
        // The identity ramp contains 0x23, `#`.
        let token = ESCI2.Token("GMT", [.word("RED "), .bytes(ESCI2.identityGamma)])
        #expect(try ESCI2.parseTokens((token.encoded + Array("#LAMOFF ".utf8))[...]) == [token, ESCI2.Token("LAM", [.word("OFF ")])])
    }

    // MARK: Status and EXI

    @Test func readsTheEmptyFeederCode() throws {
        let tokens = try ESCI2.parseTokens(Array("#ERRADF PE  ".utf8)[...])
        #expect(ESCI2.errorCodes(inStatus: tokens) == ["PE"])
        #expect(throws: ScannerError.feederEmpty) { try ScannerSession.checkStatus(Array("#ERRADF PE  ".utf8)) }
    }

    @Test func statusWithoutDataIsReady() throws {
        try ScannerSession.checkStatus([])
    }

    @Test func jamLeftInTheStatusIsAJam() {
        #expect(throws: ScannerError.jammed) { try ScannerSession.checkStatus(Array("#ERRADF PJ  ".utf8)) }
    }

    @Test func reportsUnobservedStatusCodesAsSent() {
        #expect(throws: ScannerError.scannerReported("OPN")) { try ScannerSession.checkStatus(Array("#ERRADF OPN ".utf8)) }
    }

    @Test func doubleFeedLeftInTheStatusIsADoubleFeed() {
        #expect(throws: ScannerError.doubleFeed) { try ScannerSession.checkStatus(Array("#ERRADF DFED".utf8)) }
    }

    @Test(arguments: [(300, 3600), (600, 1550), (200, nil)] as [(Int, Int?)])
    func readsTheNormalSpeedLength(dpi: Int, length: Int?) throws {
        #expect(try ESCI2.normalSpeedLength(exi: Self.exi, dpi: dpi) == length)
    }

    @Test func rejectsUnreadableEXI() {
        #expect(throws: ScannerError.self) { try ESCI2.normalSpeedLength(exi: Array("{".utf8), dpi: 300) }
    }

    // MARK: Scan parameters

    @Test func twoSidedParametersAreOneThousandBytes() {
        // PARAx00003E8 is the spec's example request block.
        #expect(ESCI2.encode(ESCI2.scanParameters(sides: .duplex, dpi: 600, length: 1550)).count == 0x3E8)
    }

    @Test func parametersFollowScanSmartsOrder() {
        #expect(ESCI2.scanParameters(sides: .front, dpi: 300, length: 3600).map(\.name) == [
            "ADF", "RSM", "RSS", "COL", "FMT", "JPG", "GMM", "GMT", "GMT", "GMT", "CMX", "CRP", "DFA", "LAM", "PAG", "ACQ", "BSZ",
        ])
    }

    @Test func oneSidedParametersAt300() {
        let text = ESCI2.ascii(ESCI2.encode(ESCI2.scanParameters(sides: .front, dpi: 300, length: 3600)))
        #expect(text.hasPrefix("#ADFCRP SKEWDFL1#RSMi0000300#RSSi0000300#COLC024#FMTJPG #JPGd090#GMMUG18#GMTRED h100"))
        #expect(text.hasSuffix("#CRPi0000000#DFAi0000000i0001550#LAMOFF #PAGd000#ACQi0000000i0000000i0002550i0010800#BSZi1048576"))
    }

    @Test func twoSidedParametersAt600() {
        let tokens = ESCI2.scanParameters(sides: .duplex, dpi: 600, length: 1550)
        #expect(ESCI2.ascii(tokens[0].encoded) == "#ADFCRP SKEWDPLXDFL1")
        #expect(ESCI2.ascii(tokens.first { $0.name == "RSM" }!.encoded) == "#RSMi0000600")
        #expect(ESCI2.ascii(tokens.first { $0.name == "ACQ" }!.encoded) == "#ACQi0000000i0000000i0005100i0009300")
    }

    @Test func gammaTablesAreExactIdentityRampsInRedBlueGreenOrder() {
        let tables = ESCI2.scanParameters(sides: .duplex, dpi: 600, length: 1550).filter { $0.name == "GMT" }
        #expect(tables.map(\.words) == [["RED "], ["BLU "], ["GRN "]])
        for table in tables {
            #expect(table.byteStrings == [(0...255).map(UInt8.init)])
            #expect(table.encoded.count == 4 + 4 + 4 + 256)
        }
    }

    @Test func colorMatrixIsIdentityPaddedWithThreeZeroBytes() {
        let matrix = ESCI2.scanParameters(sides: .duplex, dpi: 600, length: 1550).first { $0.name == "CMX" }!
        #expect(matrix.encoded == Array("#CMXUM08h009".utf8) + [0x20, 0, 0, 0, 0x20, 0, 0, 0, 0x20] + [0, 0, 0])
    }

    // MARK: Helpers

    static let exi = Array(#"""
        {"NormalSpeedLength":[{"Resolution":300,"Length":3600},{"Resolution":600,"Length":1550}],
         "MaxLength":[{"Resolution":200,"Length":24000},{"Resolution":300,"Length":21500},{"Resolution":600,"Length":5300}]}
        """#.utf8)

    /// A 64-byte reply block, padded with `#---`.
    static func replyBlock(_ text: String) -> [UInt8] {
        var bytes = Array(text.utf8)
        while bytes.count < 64 { bytes += Array("#---".utf8) }
        return Array(bytes.prefix(64))
    }
}
