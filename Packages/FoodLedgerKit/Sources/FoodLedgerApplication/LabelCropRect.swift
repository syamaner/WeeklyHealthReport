import Foundation

/// The user's crop of a label photo as it crosses `LabelImagePreparing`
/// (docs/label-photo-ai-prefill-v1.md P3 and 17.2): a pure value, never `CGRect`. Normalised to the
/// photo as displayed upright (0...1 on both axes, origin top left), plus the quarter turns the user
/// applied. Only the part inside the crop is ever prepared, sent or kept.
public struct LabelCropRect: Equatable, Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    /// Clockwise quarter turns, 0 to 3.
    public let quarterTurns: Int

    /// The whole photo, upright: the crop screen's starting value.
    public static let whole = LabelCropRect(validX: 0, y: 0, width: 1, height: 1, quarterTurns: 0)

    /// Nil unless every value is finite, the rectangle is non-empty and inside the unit square, and
    /// the turns are 0 to 3.
    public init?(x: Double, y: Double, width: Double, height: Double, quarterTurns: Int = 0) {
        let values = [x, y, width, height]
        guard values.allSatisfy(\.isFinite), x >= 0, y >= 0, width > 0, height > 0,
              x + width <= 1, y + height <= 1, (0...3).contains(quarterTurns) else { return nil }
        self.init(validX: x, y: y, width: width, height: height, quarterTurns: quarterTurns)
    }

    private init(validX x: Double, y: Double, width: Double, height: Double, quarterTurns: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height; self.quarterTurns = quarterTurns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let crop = LabelCropRect(x: try container.decode(Double.self, forKey: .x), y: try container.decode(Double.self, forKey: .y),
                                       width: try container.decode(Double.self, forKey: .width),
                                       height: try container.decode(Double.self, forKey: .height),
                                       quarterTurns: try container.decode(Int.self, forKey: .quarterTurns)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "crop outside the photo"))
        }
        self = crop
    }

    /// The short edge in pixels of this crop of a `pixelWidth` × `pixelHeight` upright photo.
    public func shortEdge(pixelWidth: Int, pixelHeight: Int) -> Double {
        min(width * Double(pixelWidth), height * Double(pixelHeight))
    }

    /// P5, decided 25 October 2026 (17.9): a crop whose short edge is under 240 px is refused.
    public static let minimumShortEdge: Double = 240
}
