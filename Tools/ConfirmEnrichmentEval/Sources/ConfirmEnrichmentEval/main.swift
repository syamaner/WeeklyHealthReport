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
//   verify-freeze --cases DEVELOPMENT_CASES --private DIR
//   prepare-sealed-review --cases SEALED_CASES --private DIR
//   score --part details|nutrients --cases CASES --private DIR [--review-sheet CSV] [--fake]
//   select --export FILE --private DIR [--seed N] [--repo DIR]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func value(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1),
          !arguments[index + 1].hasPrefix("--") else { return nil }
    return arguments[index + 1]
}

/// A misspelt or repeated option must never turn a one-request probe into a full send.
func validSendArguments(_ arguments: [String]) -> Bool {
    let options: Set<String> = ["--part", "--cases", "--private", "--fake", "--repo"]
    var seen: Set<String> = []
    var remaining = arguments.dropFirst()
    while let option = remaining.popFirst() {
        guard seen.insert(option).inserted else { return false }
        if option == "--first-request-only" { continue }
        guard options.contains(option), let value = remaining.popFirst(), !value.hasPrefix("--") else { return false }
    }
    return true
}

/// Local Git verification. The wrapper fetches origin before invoking the tool.
func gitOutput(repo: URL, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", repo.path] + arguments
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
    guard let origin = gitOutput(repo: repo, ["show", "origin/main:docs/privacy-and-egress.md"]) else { fail(EvalConsole.stopLine("preflight_origin_main_unreadable")) }
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

func outsideWorkTrees(_ folder: URL, repo: URL) -> Bool {
    !EvalPaths.isInside(folder.path, repository: repo.path) && !EvalWorkTree.contains(folder)
}

func needsMergedFreeze(repo: URL, folder: URL) {
    guard let freeze = EvalConfiguration.freeze, freeze.isComplete else {
        fail(EvalConsole.stopLine("route_freeze_pending"))
    }
    let merged = gitOutput(repo: repo, ["merge-base", "--is-ancestor", "HEAD", "origin/main"])
    let status = gitOutput(repo: repo, ["status", "--porcelain", "--untracked-files=normal"])
    let configPath = "HEAD:Tools/ConfirmEnrichmentEval/Sources/ConfirmEnrichmentEvalCore/EvalConfiguration.swift"
    let config = gitOutput(repo: repo, ["show", configPath])
    guard merged != nil, status == "", config?.contains(freeze.firstDetailsRequestSHA256) == true else {
        fail(EvalConsole.stopLine("sealed_run_requires_clean_merged_checkout"))
    }
    let development = cases(folder.appendingPathComponent(EvalSelector.developmentFile).path)
    guard (try? EvalHashes.manifest(development)) == EvalConfiguration.development,
          EvalScorer().verifyDetailsFreeze(development, folder: folder, expectedSHA256: freeze.firstDetailsRequestSHA256) else {
        fail(EvalConsole.stopLine("route_freeze_mismatch"))
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let repo = URL(fileURLWithPath: value("--repo", in: arguments) ?? FileManager.default.currentDirectoryPath)
if arguments.first == "score" {
    let part = value("--part", in: arguments).flatMap(ConfirmEnrichmentPart.init(rawValue:))
    let reportPart = part ?? .details
    let fake = arguments.contains("--fake")
    let results: [EvalScoring.Result]
    if let part, let path = value("--cases", in: arguments), let folder = value("--private", in: arguments),
       let bytes = FileManager.default.contents(atPath: path), let list = try? EvalCaseList.decode(bytes),
       let manifest = try? EvalHashes.manifest(list),
       fake ? manifest != EvalConfiguration.sealed : (manifest == EvalConfiguration.development || manifest == EvalConfiguration.sealed) {
        let local = URL(fileURLWithPath: folder, isDirectory: true)
        let sealed = manifest == EvalConfiguration.sealed
        let child = fake ? "fake" : sealed ? "sealed" : nil
        let evidence = child.map { local.appendingPathComponent($0, isDirectory: true) } ?? local
        let sheet = value("--review-sheet", in: arguments).map { URL(fileURLWithPath: $0) }
        if outsideWorkTrees(local, repo: repo), outsideWorkTrees(evidence, repo: repo),
           EvalPaths.isInside(evidence.path, repository: local.path) {
            results = EvalScorer().score(list, part: part, folder: local, reviewSheet: sheet,
                                         evidenceFolder: evidence, fake: fake)
        } else {
            results = [EvalScorer.invalid(part)]
        }
    } else {
        results = [EvalScorer.invalid(reportPart)]
    }
    results.forEach { print(EvalConsole.scoreLine($0, fake: fake)) }
    exit(results.allSatisfy(\.passed) ? 0 : 1)
}
// A flag given without a value is a usage error, never "not given" (a bare `--fake` must not run live).
for flag in ["--part", "--cases", "--private", "--fake", "--repo", "--export", "--seed"] where arguments.contains(flag) && value(flag, in: arguments) == nil {
    fail("usage: \(flag) needs a value")
}

switch arguments.first {
case "preflight":
    preflight(repo: repo)
    print("preflight passed")
case "manifest":
    guard arguments.count >= 2 else { fail("usage: manifest CASES") }
    guard let manifest = try? EvalHashes.manifest(cases(arguments[1])) else { fail(EvalConsole.stopLine("manifest_failed")) }
    print(EvalConsole.manifestLine(manifest))
case "verify-freeze":
    guard let path = value("--cases", in: arguments), let folder = value("--private", in: arguments),
          let freeze = EvalConfiguration.freeze, freeze.isComplete else {
        fail(EvalConsole.stopLine("route_freeze_pending"))
    }
    let local = URL(fileURLWithPath: folder, isDirectory: true)
    guard outsideWorkTrees(local, repo: repo) else {
        fail(EvalConsole.stopLine("private_folder_inside_repository"))
    }
    let list = cases(path)
    guard (try? EvalHashes.manifest(list)) == EvalConfiguration.development,
          EvalScorer().verifyDetailsFreeze(list, folder: local, expectedSHA256: freeze.firstDetailsRequestSHA256) else {
        fail(EvalConsole.stopLine("route_freeze_mismatch"))
    }
    print("route freeze pass")
case "prepare-sealed-review":
    guard let path = value("--cases", in: arguments), let folder = value("--private", in: arguments) else {
        fail(EvalConsole.stopLine("sealed_review_arguments_invalid"))
    }
    let local = URL(fileURLWithPath: folder, isDirectory: true)
    guard outsideWorkTrees(local, repo: repo) else { fail(EvalConsole.stopLine("private_folder_inside_repository")) }
    needsMergedFreeze(repo: repo, folder: local)
    let list = cases(path)
    guard (try? EvalHashes.manifest(list)) == EvalConfiguration.sealed else {
        fail(EvalConsole.stopLine("sealed_manifest_mismatch"))
    }
    guard let count = try? EvalReviewSheet.writeSealed(list, folder: local) else {
        fail(EvalConsole.stopLine("sealed_review_unwritable"))
    }
    print("review_sheet sealed cases \(count)")
case "send":
    guard validSendArguments(arguments),
          let partName = value("--part", in: arguments), let part = ConfirmEnrichmentPart(rawValue: partName),
          let casesPath = value("--cases", in: arguments), let privatePath = value("--private", in: arguments) else {
        fail("usage: send --part details|nutrients --cases CASES --private DIR [--fake DIR] [--first-request-only] [--repo DIR]")
    }
    preflight(repo: repo)
    let list = cases(casesPath)
    let firstRequestOnly = arguments.contains("--first-request-only")
    if firstRequestOnly && part != .details { fail(EvalConsole.stopLine("first_request_details_only")) }
    let fakePath = value("--fake", in: arguments)
    guard let manifest = try? EvalHashes.manifest(list) else { fail(EvalConsole.stopLine("manifest_failed")) }
    let sealed = manifest == EvalConfiguration.sealed
    if fakePath != nil && sealed { fail(EvalConsole.stopLine("sealed_run_requires_live_full_send")) }
    if fakePath == nil && !sealed && manifest != EvalConfiguration.development {
        fail(EvalConsole.stopLine("development_manifest_mismatch"))
    }
    let chosenFolder = URL(fileURLWithPath: privatePath, isDirectory: true)
    let child = fakePath != nil ? "fake" : sealed ? "sealed" : nil
    let evidence = child.map { chosenFolder.appendingPathComponent($0, isDirectory: true) } ?? chosenFolder
    guard outsideWorkTrees(chosenFolder, repo: repo), outsideWorkTrees(evidence, repo: repo),
          EvalPaths.isInside(evidence.path, repository: chosenFolder.path) else {
        fail(EvalConsole.stopLine("private_folder_inside_repository"))
    }
    if sealed {
        guard !firstRequestOnly else { fail(EvalConsole.stopLine("sealed_run_requires_live_full_send")) }
        needsMergedFreeze(repo: repo, folder: chosenFolder)
    }
    let transport: any ConfirmEnrichmentHTTPTransportingBox
    let keys: any FoodWebKeyStoring
    if let fakePath {
        transport = Box(FakeTransport.directory(URL(fileURLWithPath: fakePath, isDirectory: true)))
        keys = FixedEvalKey()
    } else {
        do { keys = try EnvironmentKey() } catch { fail(EvalConsole.stopLine("\(error)")) }
        transport = Box(LiveTransport.make())
    }
    let liveLock = fakePath == nil ? EvalLiveRunLock.acquire(in: chosenFolder) : nil
    guard fakePath != nil || liveLock != nil else { fail(EvalConsole.stopLine("live_run_busy_or_unwritable")) }
    defer { try? liveLock?.close() }
    let ledgerFolder = fakePath == nil ? chosenFolder : evidence
    let ledger = EvalSpendLedger(url: ledgerFolder.appendingPathComponent("confirm-enrichment-eval-spend-ledger-v1.json"))
    let sender = EvalSender(part: part, transport: transport.value, keys: keys, ledger: ledger,
                            privateFolder: chosenFolder, evidenceFolder: evidence, fake: fakePath != nil)
    let semaphore = DispatchSemaphore(value: 0)
    let output = OutputLines()
    // Detached: top-level code is main-actor isolated in Swift 6, so an inherited task would wait for
    // the main thread this line blocks (defect review of PR 3).
    Task.detached {
        output.set(await sender.run(list, firstRequestOnly: firstRequestOnly, sealed: sealed))
        semaphore.signal()
    }
    semaphore.wait()
    output.lines.forEach { print(fakePath == nil ? $0 : "fake " + $0) }
    if output.lines.contains(where: { $0.hasPrefix("stop ") }) { exit(1) }
case "select":
    // The owner-approved case selection (docs/privacy-and-egress.md): deterministic, sends nothing, writes
    // only in the private folder and prints counts, manifests and stop codes only.
    guard let exportPath = value("--export", in: arguments), let privatePath = value("--private", in: arguments) else {
        fail("usage: select --export FILE --private DIR [--seed N] [--repo DIR]")
    }
    let privateFolder = URL(fileURLWithPath: privatePath, isDirectory: true)
    if EvalPaths.isInside(privateFolder.path, repository: repo.path) || EvalWorkTree.contains(privateFolder) {
        fail(EvalConsole.stopLine("private_folder_inside_repository"))
    }
    let seed: UInt64
    if let text = value("--seed", in: arguments) {
        guard let parsed = UInt64(text) else { fail("usage: --seed needs a whole number") }
        seed = parsed
    } else {
        var system = SystemRandomNumberGenerator()
        seed = system.next()
    }
    let lines = EvalSelector().select(export: URL(fileURLWithPath: exportPath), privateFolder: privateFolder, seed: seed)
    lines.forEach { print($0) }
    if lines.last?.hasPrefix("stop ") == true { exit(1) }
default:
    fail("usage: preflight | manifest CASES | verify-freeze --cases CASES --private DIR | send --part details|nutrients --cases CASES --private DIR [--fake DIR] | score --part details|nutrients --cases CASES --private DIR [--review-sheet CSV] | select --export FILE --private DIR [--seed N]")
}
