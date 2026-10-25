import Foundation
import FoodLedgerDomain

/// Prepared bytes of a label photo crop (docs/label-photo-ai-prefill-v1.md E3, 12.1 and 17.8 M6):
/// a JPEG decoded from pixels, oriented, cropped, in sRGB, scaled and encoded without metadata.
/// Its initialiser is private to this file and reached only through `PreparedLabelImageFactory`,
/// which the boundary script lets only the preparer (and tests) call; the request builder accepts
/// only this type, so no other bytes can be sent (invariant 3).
public struct PreparedLabelImage: Equatable, Sendable {
    /// E3 bounds: a long edge of at most 2,048 px, at most 3.2 megapixels and 1,500,000 bytes.
    public static let maximumLongEdge = 2_048
    public static let maximumPixels = 3_200_000
    public static let maximumBytes = 1_500_000

    public let bytes: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Lower-case hex SHA-256 of `bytes`, computed by the preparer.
    public let sha256: String
    /// Decimal text, as recorded in the manifest.
    public let jpegQuality: String

    fileprivate init(bytes: Data, pixelWidth: Int, pixelHeight: Int, sha256: String, jpegQuality: String) throws {
        guard !bytes.isEmpty, bytes.count <= Self.maximumBytes, pixelWidth > 0, pixelHeight > 0,
              max(pixelWidth, pixelHeight) <= Self.maximumLongEdge, pixelWidth * pixelHeight <= Self.maximumPixels,
              sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              LabelPhotoManifest.isDecimalText(jpegQuality) else {
            throw LabelImagePreparationError.outOfBounds
        }
        self.bytes = bytes; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.sha256 = sha256; self.jpegQuality = jpegQuality
    }

    /// The manifest's `image` record for these bytes.
    public var manifestImage: LabelPhotoManifest.Image {
        LabelPhotoManifest.Image(sha256: sha256, byteCount: bytes.count, pixelWidth: pixelWidth, pixelHeight: pixelHeight, jpegQuality: jpegQuality)
    }
}

/// The one way to build a `PreparedLabelImage` (17.8 M6). `package` access keeps it out of the
/// app; `check-boundaries.sh` refuses any call outside the photo capture adapter and tests.
package enum PreparedLabelImageFactory {
    /// The image for `bytes`, its SHA-256 computed here by the injected digester, so the recorded
    /// hash is always that of the bytes.
    package static func make(bytes: Data, pixelWidth: Int, pixelHeight: Int, jpegQuality: String,
                             digester: any Digesting) throws -> PreparedLabelImage {
        let digest = try digester.sha256(bytes).value
        return try PreparedLabelImage(bytes: bytes, pixelWidth: pixelWidth, pixelHeight: pixelHeight, sha256: digest, jpegQuality: jpegQuality)
    }
}

public enum LabelImagePreparationError: Error, Equatable, Sendable {
    /// The photo could not be decoded.
    case unreadable
    /// The crop's short edge is under `LabelCropRect.minimumShortEdge` pixels, before or after scaling.
    case cropTooSmall
    /// The crop is longer than 8 times its width (or the reverse).
    case cropTooNarrow
    /// No encoding fits the E3 bounds.
    case outOfBounds
    /// The encoder's output is not the allow-listed JPEG structure.
    case malformedOutput
}

/// Crop rectangle and source bytes in, prepared bytes out (12.1). The conformer lives in the
/// capture adapter, where ImageIO is confined.
public protocol LabelImagePreparing: Sendable {
    func prepare(_ source: Data, crop: LabelCropRect) throws -> PreparedLabelImage
}

/// The model's reply to one tap, before any mapping (12.1): the wire text and the identity,
/// usage and attempts the manifest records.
public struct LabelPhotoWireReply: Equatable, Sendable {
    public let wireText: String
    public let model: String
    public let provider: String
    public let generationID: String
    public let finishReason: String
    public let attempts: Int
    public let usage: LabelPhotoManifest.Usage
    public let requestedAt: Int64
    public let completedAt: Int64

    public init(wireText: String, model: String, provider: String, generationID: String, finishReason: String, attempts: Int,
                usage: LabelPhotoManifest.Usage, requestedAt: Int64, completedAt: Int64) {
        self.wireText = wireText; self.model = model; self.provider = provider; self.generationID = generationID
        self.finishReason = finishReason; self.attempts = attempts; self.usage = usage
        self.requestedAt = requestedAt; self.completedAt = completedAt
    }
}

/// Why a read ended with nothing to show (7.2). The reader never retries across a user action.
public enum LabelImageReadingFailure: Error, Equatable, Sendable {
    case offline, keyMissing, keyRejected, routeUnavailable, dailyLimit, paused, timedOut, cancelled
    case providerUnavailable, wrongModel, wrongProvider, truncated, refused, oversize, unreadableAnswer, failed
    /// HTTP 429: OpenRouter reports a quota or rate limit (7.2, its own copy). Still retried (E11).
    case quotaLimited
}

/// What one attempt that sent the prepared bytes returned (12.1, 17.5). A failed attempt carries
/// its retry outcome and, when the reply reported it, its cost.
public enum LabelPhotoAttemptResult: Equatable, Sendable {
    /// A reply that passed every response check (E5, E12): the wire text and its identity and usage.
    case answered(wireText: String, model: String, provider: String, generationID: String, finishReason: String,
                  usage: LabelPhotoManifest.Usage)
    /// No usable answer; `failure` is what the user is told if the read ends here.
    case failed(LabelPhotoRetryPolicy.Outcome, failure: LabelImageReadingFailure, reportedCost: Decimal?, promptTokens: Int?)
    /// The attempt was cancelled before it could send any bytes (nothing is charged).
    case notSent(LabelImageReadingFailure)
}

/// One attempt: the prepared bytes in, the checked result out, within `timeout` seconds (12.1).
/// The OpenRouter adapter conforms, over an injected transport; until L5 only a fake transport is
/// wired. It must stop at once when its task is cancelled.
public protocol LabelPhotoAttempting: Sendable {
    func attempt(_ image: PreparedLabelImage, timeout: TimeInterval) async -> LabelPhotoAttemptResult
    /// The manifest's record of what every attempt sends under the session's catalogue check.
    func manifestRequest(catalogue: LabelPhotoManifest.CatalogueCheck) -> LabelPhotoManifest.Request
}

/// Waits between attempts; throws when the task is cancelled (an injected clock in tests).
public protocol LabelPhotoSleeping: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

/// Image and candidate in, one location record per cell and serving line out (12.1). The Vision
/// adapter conforms in L2, through the pinned matcher.
public protocol LabelValueLocating: Sendable {
    func locate(_ image: PreparedLabelImage, candidate: PastedLabelManifest.Candidate) async throws -> LabelPhotoManifest.Locations
}

/// The on-the-day catalogue check (E7, 17.5 M3): free, with no Authorization header and no user
/// data, once per session before the first image request.
public protocol LabelPhotoRouteChecking: Sendable {
    func check(_ route: LabelPhotoRoute.Route) async throws -> LabelPhotoManifest.CatalogueCheck
}

/// Today's reads and cost, persisted by a file-backed adapter (17.8, L4). No record yet is
/// `.absent` (a fresh day); a record that cannot be read is `.unreadable`, which fails closed
/// (`LabelPhotoSpendPolicy.admission`).
public protocol LabelPhotoSpendLedger: Sendable {
    func load() -> LabelPhotoSpendPolicy.Stored
    /// One atomic read-modify-write (#326 re-check): `transform` sees the day as stored now and
    /// returns the day to store, or throws to store nothing. No other write, from this process or
    /// another, can come between the read and the write. Returns the day stored.
    @discardableResult
    func update(_ transform: (LabelPhotoSpendPolicy.Stored) throws -> LabelPhotoSpendPolicy.Day) throws -> LabelPhotoSpendPolicy.Day
}

/// Whether the device can reach the network now (7.2, offline state).
public protocol ConnectivityStatus: Sendable {
    var isOnline: Bool { get }
}
