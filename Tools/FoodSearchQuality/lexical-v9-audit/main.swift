// Offline audit for food-lexical-terms-v9 (docs/food-lexical-terms-v9.md).
// Never shipped and never linked into the app or FoodLedgerKit: Apple's
// NaturalLanguage lemmatiser is used here once, as a second opinion on the
// deterministic rules, and is not consulted at run time.
//
// Input: the vocabulary file written by vocabulary.py (word TAB sources).
// Output: a summary line, every word where the rule and the lemmatiser disagree
// (CHANGED: the rule folds it; KEPT: the rule leaves an -s word alone), and every
// MERGE where two distinct vocabulary words fold to the same term.
import Foundation
import NaturalLanguage

let lines = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n")
var sources: [String: String] = [:]
for line in lines {
    let parts = line.split(separator: "\t")
    sources[String(parts[0])] = String(parts[1])
}
let vocabulary = sources.keys.sorted()
let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])

func lemma(_ word: String) -> (String, String) {
    // A carrier sentence: isolated words rarely receive a lemma.
    let text = "I bought some " + word + " today."
    tagger.string = text
    let index = text.index(after: text.range(of: " " + word + " ")!.lowerBound)
    let (tag, _) = tagger.tag(at: index, unit: .word, scheme: .lemma)
    let (lexicalClass, _) = tagger.tag(at: index, unit: .word, scheme: .lexicalClass)
    return (tag?.rawValue.lowercased() ?? "-", lexicalClass?.rawValue ?? "-")
}

var changed = 0, agree = 0, noLemma = 0
var disagreements: [String] = []
var folded: [String: [String]] = [:]
for word in vocabulary {
    let rule = FoodLexicalPlurals.singular(word)
    folded[rule, default: []].append(word)
    let (nl, lexicalClass) = lemma(word)
    if rule != word { changed += 1 }
    if rule != word && nl == "-" { noLemma += 1 }
    if rule != word && nl != rule && nl != "-" {
        disagreements.append("CHANGED\t\(word)\trule=\(rule)\tnl=\(nl)\t\(lexicalClass)\t\(sources[word]!)")
    } else if rule == word && word.hasSuffix("s") && nl != word && nl != "-" {
        disagreements.append("KEPT\t\(word)\trule=\(rule)\tnl=\(nl)\t\(lexicalClass)\t\(sources[word]!)")
    } else if rule != word && nl == rule {
        agree += 1
    }
}
print("vocabulary\t\(vocabulary.count)\tchanged\t\(changed)\tagreeWithNL\t\(agree)\tnoLemma\t\(noLemma)")
for line in disagreements { print(line) }
for (term, words) in folded.sorted(by: { $0.key < $1.key }) where words.count > 1 {
    print("MERGE\t\(term)\t\(words.joined(separator: ","))")
}
