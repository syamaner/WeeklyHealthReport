import ConfirmEnrichmentEvalCore
import ConfirmEnrichmentEvalHarness
import FoodLedgerApplication
import Foundation

// Confirm enrichment evaluation CLI (docs/confirm-enrichment-openrouter-v1-phase.md section 9). Run by the
// owner on the Mac through run.sh, which fetches origin first with the key unset. Every line printed names
// cases by hash only (G11).
//
//   preflight [--repo DIR]
//   manifest CASES
//   send --part details|nutrients --cases CASES --private DIR [--fake DIR] [--repo DIR]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func value(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

/// `git show origin/main:docs/privacy-and-egress.md`, run locally: no network (run.sh fetched already).
func originMainPolicy(repo: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", repo.path, "show", "origin/main:docs/privacy-and-egress.md"]
    var environment = ProcessInfo.processInfo.environment
    environment[EnvironmentKey.variable] = nil
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

func preflight(repo: URL) {
    guard let checkout = try? String(contentsOfFile: repo.appendingPathComponent("docs/privacy-and-egress.md").path, encoding: .utf8) else {
        fail(EvalConsole.stopLine("preflight_checkout_unreadable"))
    }
    guard let origin = originMainPolicy(repo: repo) else { fail(EvalConsole.stopLine("preflight_origin_main_unreadable")) }
    do { try EvalPreflight.check(checkout: checkout, originMain: origin) } catch {
        fail(EvalConsole.stopLine(error is EvalPreflight.Refusal ? "preflight_paragraph_missing" : "preflight_failed"))
    }
}

func cases(_ path: String) -> EvalCaseList {
    guard let data = FileManager.default.contents(atPath: path) else { fail(EvalConsole.stopLine("cases_unreadable")) }
    do { return try EvalCaseList.decode(data) } catch let problem as EvalCaseList.Problem {
        fail(EvalConsole.stopLine("cases_\(problem)".replacingOccurrences(of: " ", with: "_")))
    } catch { fail(EvalConsole.stopLine("cases_unreadable")) }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let repo = URL(fileURLWithPath: value("--repo", in: arguments) ?? FileManager.default.currentDirectoryPath)

switch arguments.first {
case "preflight":
    preflight(repo: repo)
    print("preflight passed")
case "manifest":
    guard arguments.count >= 2 else { fail("usage: manifest CASES") }
    guard let manifest = try? EvalHashes.manifest(cases(arguments[1])) else { fail(EvalConsole.stopLine("manifest_failed")) }
    print(EvalConsole.manifestLine(manifest))
case "send":
    guard let partName = value("--part", in: arguments), let part = ConfirmEnrichmentPart(rawValue: partName),
          let casesPath = value("--cases", in: arguments), let privatePath = value("--private", in: arguments) else {
        fail("usage: send --part details|nutrients --cases CASES --private DIR [--fake DIR] [--repo DIR]")
    }
    preflight(repo: repo)
    let list = cases(casesPath)
    let privateFolder = URL(fileURLWithPath: privatePath, isDirectory: true)
    let transport: any ConfirmEnrichmentHTTPTransportingBox
    let keys: any FoodWebKeyStoring
    if let fake = value("--fake", in: arguments) {
        transport = Box(FakeTransport.directory(URL(fileURLWithPath: fake, isDirectory: true)))
        keys = FixedEvalKey()
    } else {
        do { keys = try EnvironmentKey() } catch { fail(EvalConsole.stopLine("\(error)")) }
        transport = Box(LiveTransport.make())
    }
    let ledger = EvalSpendLedger(url: privateFolder.appendingPathComponent("confirm-enrichment-eval-spend-ledger-v1.json"))
    let sender = EvalSender(part: part, transport: transport.value, keys: keys, ledger: ledger, privateFolder: privateFolder)
    let semaphore = DispatchSemaphore(value: 0)
    let output = OutputLines()
    Task {
        output.set(await sender.run(list))
        semaphore.signal()
    }
    semaphore.wait()
    output.lines.forEach { print($0) }
default:
    fail("usage: preflight | manifest CASES | send --part details|nutrients --cases CASES --private DIR [--fake DIR]")
}
