import Testing
@testable import ScanKit

@Suite struct ScanSettingsTests {
    @Test func defaultIsOneSidedGrayAt300() {
        #expect(ScanSettings.default == ScanSettings(sides: .front, color: .gray, dpi: 300))
    }
}
