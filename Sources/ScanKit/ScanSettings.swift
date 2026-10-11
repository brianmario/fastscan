public enum Sides: String, CaseIterable, Codable, Sendable {
    case front, duplex
}

/// What the scanner captures. How paper is stored afterwards is `ColorMode`.
public enum ScanColor: String, CaseIterable, Codable, Sendable {
    case lineart, gray, color
}

public struct ScanSettings: Equatable, Codable, Sendable {
    public var sides: Sides
    public var color: ScanColor
    public var dpi: Int

    public static let `default` = ScanSettings(sides: .front, color: .gray, dpi: 300)

    public init(sides: Sides, color: ScanColor, dpi: Int) {
        self.sides = sides
        self.color = color
        self.dpi = dpi
    }
}
