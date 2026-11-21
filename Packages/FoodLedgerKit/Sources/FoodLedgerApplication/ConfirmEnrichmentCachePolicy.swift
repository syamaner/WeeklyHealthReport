import Foundation
import FoodLedgerDomain

/// `confirm-enrichment-cache-v1.json` and the one policy every cache applies (docs/confirm-enrichment-
/// openrouter-v1.md CE1.2; phase gate section 2.5): exactly CE1.2's value, at most 500 entries ordered
/// by `received_at` with the oldest dropped first, an entry older than 30 days a miss and dropped at the
/// next write, and a corrupt, unknown-schema or over-size file discarded whole. Pure: `now` comes in.
public enum ConfirmEnrichmentCachePolicy {
    public static let schema = "confirm-enrichment-cache-v1"
    public static let maximumEntries = 500
    public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
    /// The largest file read: 500 entries of the largest B response, base64, with room for the fields.
    public static let maximumFileBytes = 500 * (ConfirmEnrichmentVersions.nutrientResponseByteLimit * 4 / 3 + 1_024)

    /// One entry as stored. No field for the request body, key, amount, description or any other date.
    struct Entry: Codable, Equatable, Sendable {
        let subjectSHA256: String
        let part: ConfirmEnrichmentPart
        let response: String
        let responseSHA256: String
        let model: String
        let provider: String
        let costMicroUSD: Int?
        let receivedAt: String

        enum CodingKeys: String, CodingKey, CaseIterable {
            case part, response, model, provider
            case subjectSHA256 = "subject_sha256"
            case responseSHA256 = "response_sha256"
            case costMicroUSD = "cost_microusd"
            case receivedAt = "received_at"
        }

        init(_ answer: ConfirmEnrichmentCachedAnswer) {
            subjectSHA256 = answer.subjectSHA256; part = answer.part; response = answer.response.base64EncodedString()
            responseSHA256 = answer.responseSHA256; model = answer.model; provider = answer.provider
            costMicroUSD = answer.costMicroUSD; receivedAt = ConfirmEnrichmentTime.text(answer.receivedAt)
        }

        init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            subjectSHA256 = try c.decode(String.self, forKey: .subjectSHA256)
            part = try c.decode(ConfirmEnrichmentPart.self, forKey: .part)
            response = try c.decode(String.self, forKey: .response)
            responseSHA256 = try c.decode(String.self, forKey: .responseSHA256)
            model = try c.decode(String.self, forKey: .model)
            provider = try c.decode(String.self, forKey: .provider)
            costMicroUSD = try c.decode(Int?.self, forKey: .costMicroUSD)
            receivedAt = try c.decode(String.self, forKey: .receivedAt)
            guard (try? SHA256Digest(subjectSHA256)) != nil, (try? SHA256Digest(responseSHA256)) != nil,
                  Data(base64Encoded: response) != nil, ConfirmEnrichmentTime.date(receivedAt) != nil,
                  costMicroUSD.map({ $0 >= 0 }) ?? true else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid cache entry"))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(subjectSHA256, forKey: .subjectSHA256)
            try c.encode(part, forKey: .part)
            try c.encode(response, forKey: .response)
            try c.encode(responseSHA256, forKey: .responseSHA256)
            try c.encode(model, forKey: .model)
            try c.encode(provider, forKey: .provider)
            try c.encode(costMicroUSD, forKey: .costMicroUSD)
            try c.encode(receivedAt, forKey: .receivedAt)
        }

        var answer: ConfirmEnrichmentCachedAnswer? {
            guard let bytes = Data(base64Encoded: response), let date = ConfirmEnrichmentTime.date(receivedAt) else { return nil }
            return ConfirmEnrichmentCachedAnswer(subjectSHA256: subjectSHA256, part: part, response: bytes, responseSHA256: responseSHA256,
                                                 model: model, provider: provider, costMicroUSD: costMicroUSD, receivedAt: date)
        }
    }

    struct File: Codable, Equatable, Sendable {
        let entries: [Entry]

        enum CodingKeys: String, CodingKey, CaseIterable { case schema, entries }

        init(entries: [Entry]) { self.entries = entries }

        init(from decoder: any Decoder) throws {
            try ConfirmEnrichmentStrictObject.require(CodingKeys.self, in: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decode(String.self, forKey: .schema) == ConfirmEnrichmentCachePolicy.schema else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown cache schema"))
            }
            entries = try c.decode([Entry].self, forKey: .entries)
            guard entries.count <= ConfirmEnrichmentCachePolicy.maximumEntries else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Too many cache entries"))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ConfirmEnrichmentCachePolicy.schema, forKey: .schema)
            try c.encode(entries, forKey: .entries)
        }
    }

    /// The answers a file holds, or nil when the file must be discarded whole.
    public static func decode(_ data: Data) -> [ConfirmEnrichmentCachedAnswer]? {
        guard data.count <= maximumFileBytes, let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let answers = file.entries.compactMap(\.answer)
        return answers.count == file.entries.count ? answers : nil
    }

    /// The canonical file bytes for `answers`.
    public static func encode(_ answers: [ConfirmEnrichmentCachedAnswer], encoder: any CanonicalEncoding) throws -> Data {
        try encoder.encode(File(entries: answers.map(Entry.init)))
    }

    public static func isExpired(_ answer: ConfirmEnrichmentCachedAnswer, now: Date) -> Bool {
        now.timeIntervalSince(answer.receivedAt) > maximumAge
    }

    /// The entry for a subject and part, when it has not expired.
    public static func lookup(_ answers: [ConfirmEnrichmentCachedAnswer], subject: String, part: ConfirmEnrichmentPart,
                              now: Date) -> ConfirmEnrichmentCachedAnswer? {
        answers.first { $0.subjectSHA256 == subject && $0.part == part && !isExpired($0, now: now) }
    }

    /// The entries after a write: the subject's earlier entry replaced, expired entries dropped, ordered
    /// by `received_at`, oldest first out above 500.
    public static func storing(_ answer: ConfirmEnrichmentCachedAnswer, in answers: [ConfirmEnrichmentCachedAnswer],
                               now: Date) -> [ConfirmEnrichmentCachedAnswer] {
        let kept = answers.filter { !($0.subjectSHA256 == answer.subjectSHA256 && $0.part == answer.part) && !isExpired($0, now: now) }
        let ordered = (kept + [answer]).enumerated().sorted {
            $0.element.receivedAt == $1.element.receivedAt ? $0.offset < $1.offset : $0.element.receivedAt < $1.element.receivedAt
        }.map(\.element)
        return Array(ordered.suffix(maximumEntries))
    }

    public static func removing(subject: String, part: ConfirmEnrichmentPart,
                                from answers: [ConfirmEnrichmentCachedAnswer]) -> [ConfirmEnrichmentCachedAnswer] {
        answers.filter { !($0.subjectSHA256 == subject && $0.part == part) }
    }
}

/// The one time text of Confirm enrichment: RFC 3339 UTC with exactly three fractional digits, and the
/// truncation to whole milliseconds applied before any time reaches a capture, provenance, release or
/// the cache (gate section 2.5).
public enum ConfirmEnrichmentTime {
    /// Whole milliseconds, always built as `Double(ms) / 1000`, so a truncated time and the same time
    /// read back from its text are the same `Date`. The tiny bias keeps a time already on a
    /// millisecond from flooring to the one before it.
    public static func truncated(_ date: Date) -> Date {
        fromMilliseconds((date.timeIntervalSince1970 * 1_000 + 0.000_1).rounded(.down))
    }

    static func fromMilliseconds(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1_000) }

    /// One shared formatter: built once, since a cache file reads and writes up to 500 of these times.
    /// `ISO8601DateFormatter` is thread safe.
    nonisolated(unsafe) private static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func formatter() -> ISO8601DateFormatter { shared }

    public static func text(_ date: Date) -> String { formatter().string(from: truncated(date)) }

    public static func date(_ text: String) -> Date? {
        guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"#, options: .regularExpression) != nil else {
            return nil
        }
        return formatter().date(from: text).map { fromMilliseconds(($0.timeIntervalSince1970 * 1_000).rounded()) }
    }
}
