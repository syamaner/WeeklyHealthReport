import FoodLedgerApplication
import Foundation
import PastedLabelAITextEvalCore
import PastedLabelAITextEvalHarness

// PastedLabelAITextEval (docs/pasted-label-ai-text-v1.md 5.2, #416 A2).
//
//     PastedLabelAITextEval send --label-id ID --text FILE --route CANDIDATE --cell CELL \
//         --ledger FILE --cache DIR --fake-transport DIR [--cell-stop-usd N<=5] [--programme-stop-usd N<=25]
//     PastedLabelAITextEval score --case FILE --text FILE --send FILE|-
//     PastedLabelAITextEval convert-legacy --in FILE --copy-method TEXT --text-sha256 HEX
//
// `send` refuses to run without `--fake-transport`: A2 wires no live transport, so nothing can
// reach OpenRouter or any provider. Outputs are JSON on stdout; errors go to stderr. Exit codes:
// 0 done, 2 usage or input error, 3 the call was refused by a spend stop.

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func options(_ list: ArraySlice<String>) -> [String: String] {
    var out: [String: String] = [:]
    var iterator = list.makeIterator()
    while let name = iterator.next() {
        guard name.hasPrefix("--"), let value = iterator.next() else { fail("expected --name value pairs, got \(name)") }
        guard out[name] == nil else { fail("\(name) given twice") }
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
guard let command = arguments.first else { fail("usage: PastedLabelAITextEval send|score|convert-legacy ...") }
let given = options(arguments.dropFirst())

switch command {
case "send":
    let allowed: Set<String> = ["--label-id", "--text", "--route", "--cell", "--ledger", "--cache", "--fake-transport", "--cell-stop-usd",
                                "--programme-stop-usd"]
    if let unknown = given.keys.first(where: { !allowed.contains($0) }) { fail("unknown option \(unknown)") }
    guard let fake = given["--fake-transport"] else {
        fail("send needs --fake-transport DIR: A2 wires no live transport, and nothing is sent to OpenRouter")
    }
    guard let labelID = given["--label-id"], let text = given["--text"], let routeID = given["--route"], let cell = given["--cell"],
          let ledger = given["--ledger"], let cache = given["--cache"] else {
        fail("send needs --label-id, --text, --route, --cell, --ledger, --cache and --fake-transport")
    }
    guard let route = PastedLabelAITextRoute.candidate(routeID) else {
        fail("unknown route candidate \(routeID); the closed set is \(PastedLabelAITextRoute.candidates.map(\.candidateID))")
    }
    let cellStop = given["--cell-stop-usd"].map { Decimal(string: $0) } ?? Decimal(5)
    let programmeStop = given["--programme-stop-usd"].map { Decimal(string: $0) } ?? Decimal(25)
    guard let cellStop, let programmeStop, cellStop > 0, cellStop <= 5, programmeStop > 0, programmeStop <= 25 else {
        fail("the stops may not exceed $5 per cell and $25 for the programme")
    }
    do {
        let output = try await SendCommand.run(.init(labelID: labelID, textURL: path(text), route: route, cell: cell, ledgerURL: path(ledger),
                                                     cacheDirectory: path(cache), fakeTransportDirectory: path(fake), cellStop: cellStop,
                                                     programmeStop: programmeStop))
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

case "convert-legacy":
    let allowed: Set<String> = ["--in", "--copy-method", "--text-sha256"]
    if let unknown = given.keys.first(where: { !allowed.contains($0) }) { fail("unknown option \(unknown)") }
    guard let input = given["--in"], let copyMethod = given["--copy-method"], let sha = given["--text-sha256"] else {
        fail("convert-legacy needs --in, --copy-method and --text-sha256")
    }
    do {
        let evalCase = try EvalCaseConverter.fromTaiwanLegacy(try Data(contentsOf: path(input)),
                                                             metadata: .init(set: .taiwanV3Development, tier: nil, copyMethod: copyMethod, textSHA256: sha))
        FileHandle.standardOutput.write(try evalCase.canonicalJSON())
    } catch {
        fail("convert-legacy: \(error)")
    }

default:
    fail("unknown command \(command); use send, score or convert-legacy")
}
