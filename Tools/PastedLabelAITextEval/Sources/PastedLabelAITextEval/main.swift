import FoodLabelPhotoCapture
import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore
import PastedLabelAITextEvalHarness

// PastedLabelAITextEval (docs/pasted-label-ai-text-v1.md 5.2, #416 A2 and A3).
//
//     PastedLabelAITextEval send --label-id ID --text FILE --route CANDIDATE --cell CELL \
//         --ledger FILE --cache DIR (--fake-transport DIR | --live) [--prompt-version prompt-v1|prompt-v2]
//         [--fresh-run NAME] [--data DIR] [--cell-stop-usd N<=5] [--programme-stop-usd N<=25]
//     PastedLabelAITextEval score --case FILE --text FILE --send FILE|-
//     PastedLabelAITextEval convert --in FILE --set SET --copy-method TEXT --text-sha256 HEX [--tier T] [--layout-shape SHAPE] [--label-id ID]
//     PastedLabelAITextEval convert-legacy --in FILE --copy-method TEXT --text-sha256 HEX [--layout-shape SHAPE] [--label-id ID]
//
// `convert` reads a Taiwan reader v3 fresh or UK transcription (chosen by its `schema`) into a
// tuning case of `SET`, a tuning set of 5.1; `uk_v2_fresh`, the sealed held-out set, is refused.
// `convert-legacy` reads the Taiwan reader v3 development set's older format. Both take the
// layout shape assigned by hand (5.2.1) and a case ID to name the case by, round-trip check the
// case against the file, and print its canonical JSON.
//
// `send` needs exactly one of `--fake-transport DIR` (canned replies; nothing is sent) and `--live`
// (A3 tuning runs under the evaluation egress terms T1 to T6: the shipped transport to OpenRouter,
// up to three attempts per tap, each with its own reservation). `--live` reads the key from
// `OPENROUTER_API_KEY` only and never prints it; a missing, empty or malformed key is a usage error
// before anything is reserved or sent. Outputs are JSON on stdout; errors go to stderr. Exit codes:
// 0 done, 2 usage or input error, 3 the call was refused by a spend stop. `--prompt-version` picks
// the instruction (revision 11): `prompt-v1`, the app's, by default; it is recorded in the output.
// `--fresh-run NAME` (revision 16) sends the same request body again for a noise measurement: it
// never reads the default cache entry, keeps its own entry under the request SHA-256 and NAME, and
// is reserved, retried and settled like any tap; NAME is recorded as `fresh_run`. Before the text
// is read, a text path naming the sealed held-out set (`uk-english-v2`) is refused, as given and
// after resolving symbolic links, and with `--data DIR` (provider.js passes its data directory) a
// text that resolves outside DIR is refused too; a refusal reserves nothing and sends nothing.

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// `--name value` pairs, plus the bare flags in `flags` (recorded with an empty value).
func options(_ list: ArraySlice<String>, flags: Set<String> = []) -> [String: String] {
    var out: [String: String] = [:]
    var iterator = list.makeIterator()
    while let name = iterator.next() {
        guard name.hasPrefix("--") else { fail("expected --name value pairs, got \(name)") }
        guard out[name] == nil else { fail("\(name) given twice") }
        if flags.contains(name) { out[name] = ""; continue }
        guard let value = iterator.next(), !flags.contains(value) else { fail("\(name) needs a value") }
        out[name] = value
    }
    return out
}

func path(_ value: String) -> URL { URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL }

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { fail("could not encode the output") }
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { fail("usage: PastedLabelAITextEval send|score|convert|convert-legacy ...") }
let given = options(arguments.dropFirst(), flags: command == "send" ? ["--live"] : [])

switch command {
case "send":
    let allowed: Set<String> = ["--label-id", "--text", "--route", "--cell", "--ledger", "--cache", "--fake-transport", "--live",
                                "--cell-stop-usd", "--programme-stop-usd", "--prompt-version", "--fresh-run", "--data"]
    if let unknown = given.keys.first(where: { !allowed.contains($0) }) { fail("unknown option \(unknown)") }
    // Exactly one connection, and for --live a well-formed key in the environment, before anything else.
    let choice: SendTransportChoice
    do { choice = try SendTransportChoice.choose(fakeTransport: given["--fake-transport"], live: given["--live"] != nil) } catch {
        fail("\(error)")
    }
    guard let labelID = given["--label-id"], let text = given["--text"], let routeID = given["--route"], let cell = given["--cell"],
          let ledger = given["--ledger"], let cache = given["--cache"] else {
        fail("send needs --label-id, --text, --route, --cell, --ledger, --cache and one of --fake-transport DIR and --live")
    }
    guard let route = PastedLabelAITextRoute.candidate(routeID) else {
        fail("unknown route candidate \(routeID); the closed set is \(PastedLabelAITextRoute.candidates.map(\.candidateID))")
    }
    let promptVersion: OpenRouterPastedLabelAITextRequest.PromptVersion
    if let value = given["--prompt-version"] {
        guard let chosen = OpenRouterPastedLabelAITextRequest.PromptVersion(rawValue: value) else {
            fail("unknown prompt version \(value); the closed set is \(OpenRouterPastedLabelAITextRequest.PromptVersion.allCases.map(\.rawValue))")
        }
        promptVersion = chosen
    } else {
        promptVersion = OpenRouterPastedLabelAITextRequest.defaultPromptVersion
    }
    if let name = given["--fresh-run"], !SendCommand.isFreshRunName(name) {
        fail("bad fresh run name \(name): a lower-case letter, then up to 15 lower-case letters, digits or single hyphens")
    }
    let cellStop = given["--cell-stop-usd"].map { Decimal(string: $0) } ?? Decimal(5)
    let programmeStop = given["--programme-stop-usd"].map { Decimal(string: $0) } ?? Decimal(25)
    guard let cellStop, let programmeStop, cellStop > 0, cellStop <= 5, programmeStop > 0, programmeStop <= 25 else {
        fail("the stops may not exceed $5 per cell and $25 for the programme")
    }
    do {
        let connection: SendCommand.Connection = switch choice {
        case let .fake(directory): .fake(directory: path(directory))
        case let .live(key): LiveTransport.connection(key: key)
        }
        let output = try await SendCommand.run(.init(labelID: labelID, textURL: path(text), route: route, cell: cell, ledgerURL: path(ledger),
                                                     cacheDirectory: path(cache), connection: connection, cellStop: cellStop,
                                                     programmeStop: programmeStop, promptVersion: promptVersion,
                                                     freshRun: given["--fresh-run"], dataDirectory: given["--data"].map(path)))
        printJSON(output)
        if output.attempt.hasPrefix("refused:") { exit(3) }
    } catch {
        fail("send: \(error)")
    }

case "score":
    let allowed: Set<String> = ["--case", "--text", "--send"]
    if let unknown = given.keys.first(where: { !allowed.contains($0) }) { fail("unknown option \(unknown)") }
    guard let casePath = given["--case"], let text = given["--text"], let sendPath = given["--send"] else {
        fail("score needs --case, --text and --send (a file, or - for stdin)")
    }
    do {
        let evalCase = try EvalCase.decode(try Data(contentsOf: path(casePath)))
        let sendData = sendPath == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: path(sendPath))
        let send = try JSONDecoder().decode(SendCommand.Output.self, from: sendData)
        printJSON(try ScoreCommand.run(evalCase: evalCase, textData: try Data(contentsOf: path(text)), send: send))
    } catch {
        fail("score: \(error)")
    }

case "convert", "convert-legacy":
    let legacy = command == "convert-legacy"
    let allowed: Set<String> = legacy ? ["--in", "--copy-method", "--text-sha256", "--layout-shape", "--label-id"]
        : ["--in", "--set", "--copy-method", "--text-sha256", "--tier", "--layout-shape", "--label-id"]
    if let unknown = given.keys.first(where: { !allowed.contains($0) }) { fail("unknown option \(unknown)") }
    guard let input = given["--in"], let copyMethod = given["--copy-method"], let sha = given["--text-sha256"], legacy || given["--set"] != nil else {
        fail(legacy ? "convert-legacy needs --in, --copy-method and --text-sha256" : "convert needs --in, --set, --copy-method and --text-sha256")
    }
    // The held-out set is refused before its file is opened.
    if given["--set"] == EvalCase.EvalSet.ukV2Fresh.rawValue { fail("convert: uk_v2_fresh is the sealed held-out set (D4); it is never converted here") }
    let convertOptions = ConvertCommand.Options(set: given["--set"], tier: given["--tier"], copyMethod: copyMethod, textSHA256: sha,
                                                layoutShape: given["--layout-shape"], labelID: given["--label-id"])
    do {
        let data = try Data(contentsOf: path(input))
        let evalCase = legacy ? try ConvertCommand.convertLegacy(data, convertOptions) : try ConvertCommand.convert(data, convertOptions)
        FileHandle.standardOutput.write(try evalCase.canonicalJSON())
    } catch {
        fail("\(command): \(error)")
    }

default:
    fail("unknown command \(command); use send, score, convert or convert-legacy")
}
