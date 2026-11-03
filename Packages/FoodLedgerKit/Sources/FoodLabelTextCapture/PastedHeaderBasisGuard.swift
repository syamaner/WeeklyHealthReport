import Foundation
import NutritionLabelParsing

/// `pasted-header-basis-guard-v1` (#375, owner decision 3 November 2026). Parser v3 binds any
/// header containing `per` that its per 100 patterns do not match as per serving, so `Per 100gm`,
/// `per 100 grams` or a bare `Per 100` stored per 100 values as per serving. This guard turns
/// such a candidate into a decline and never changes an accepted reading: a per serving header
/// that names a standalone 100 outside its outermost brackets, or 100 of anything but grams or
/// millilitres inside them (`Per serving (100g)` stays per serving, which is numerically
/// correct), declines `unrecognised_unit`. Applied by `NutritionLabelTextReader` to every read.
enum PastedHeaderBasisGuard {
    static let version = "pasted-header-basis-guard-v1"
    static let declineCode = "unrecognised_unit"

    static func apply(_ candidate: LabelCaptureCandidate) -> LabelCaptureCandidate {
        guard !candidate.declined, candidate.headers.contains(where: { $0.basis == .perServing && namesHundred($0.printedText) }) else {
            return candidate
        }
        return .declined(route: candidate.route, inputSHA256: candidate.inputSHA256, language: candidate.language, reasons: [declineCode])
    }

    static let standaloneHundred = try! NSRegularExpression(pattern: #"(?<![\d.,])100(?![\d.,])"#)
    static let hundredOfGramsOrMillilitres = try! NSRegularExpression(pattern: #"(?i)(?<![\d.,])100(?![\d.,])\s*(?:g|ml)(?![\p{L}])"#)

    static func namesHundred(_ printed: String) -> Bool {
        let (outside, inside) = splitOutermostBrackets(printed)
        if count(standaloneHundred, outside) > 0 { return true }
        return inside.contains { count(standaloneHundred, $0) > count(hundredOfGramsOrMillilitres, $0) }
    }

    static func count(_ pattern: NSRegularExpression, _ text: String) -> Int {
        pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func splitOutermostBrackets(_ text: String) -> (outside: String, inside: [String]) {
        var outside = ""
        var inside: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "（":
                if depth > 0 { current.append(character) }
                depth += 1
            case ")" where depth > 0, "）" where depth > 0:
                depth -= 1
                if depth == 0 { inside.append(current); current = ""; outside.append(" ") } else { current.append(character) }
            default:
                if depth > 0 { current.append(character) } else { outside.append(character) }
            }
        }
        if depth > 0 { outside += current }
        return (outside, inside)
    }
}
