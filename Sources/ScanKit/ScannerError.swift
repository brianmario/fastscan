import Foundation

public enum ScannerError: Error, Equatable, Sendable {
    case feederEmpty
    /// A paper jam (`PJ`), such as a sheet held back while the scanner tried to pull it in.
    case jammed
    /// `DFED`, which ScanSmart calls a double feed. A folded, crooked sheet set it off, and so did
    /// opening the cover mid-scan.
    case doubleFeed
    case cancelled
    /// The scanner's own Stop button was pressed (`#atnCAN ` in an `IMG` reply).
    case stoppedAtScanner
    case notOpen
    /// Another app or computer holds the scanner's lock.
    case busy
    case unsupportedScanner(String)
    case unsupportedSettings(String)
    /// An error code without a known meaning, as the scanner sent it.
    case scannerReported(String)
    /// A reply that was well formed but not what the protocol calls for at that point.
    case unexpectedReply(String)
    case malformed(String)
    case connection(String)
    case undecodableImage(PageSide)
}

extension ScannerError {
    /// The error for a code from `STAT`'s `#ERR` or an `IMG` reply's `#err`: `PE` is an empty
    /// feeder, `PJ` a paper jam, and `DFED` a double feed. Other codes haven't been observed.
    static func reported(_ code: String) -> ScannerError {
        switch code {
        case "PE": .feederEmpty
        case "PJ": .jammed
        case "DFED": .doubleFeed
        default: .scannerReported(code)
        }
    }
}

extension ScannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .feederEmpty: "The feeder is empty. Load pages and try again."
        case .jammed: "The feeder is jammed. Clear the paper path and try again."
        case .doubleFeed: "The scanner stopped feeding. Open the scanner, take out the sheet, close it, and try again."
        case .cancelled: "The scan was cancelled."
        case .stoppedAtScanner: "The scan was stopped at the scanner."
        case .notOpen: "The scanner connection isn't open."
        case .busy: "The scanner is busy. Try again in a moment."
        case .unsupportedScanner(let product): "FastScan works with the Epson FF-680W, not \(product)."
        case .unsupportedSettings(let reason): "The scanner can't scan that way: \(reason)."
        case .scannerReported(let code): "The scanner reported error \(code)."
        case .unexpectedReply(let detail): "The scanner sent an unexpected reply: \(detail)"
        case .malformed(let detail): "The scanner sent a reply FastScan couldn't read: \(detail)"
        // The detail stays in the error for logs; the wording is FastScan's original.
        case .connection: "Lost contact with the scanner."
        case .undecodableImage(let side): "The scanner sent a \(side.rawValue) side that isn't a readable JPEG."
        }
    }
}
