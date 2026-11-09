import Foundation
import PastedLabelAITextEvalHarness

// PastedLabelAITextHeldOut (docs/pasted-label-ai-text-v1.md 5.5, #416 A4): the single held-out run.
//
//     PastedLabelAITextHeldOut run [--private-root DIR]
//     PastedLabelAITextHeldOut finalise [--private-root DIR]
//     PastedLabelAITextHeldOut check [--private-root DIR]
//
// The configuration is closed (prompt-v2 on gpt-6.1-sol-azure-4k, scorer v5, D35) and every path is
// fixed under the private root, `~/WHR-label-eval-private` by default; the private root is the only
// option. `run` reads the key from `OPENROUTER_API_KEY` only and refuses a missing, empty or
// malformed key before anything is read, reserved or created; it uses the shipped live transport
// through `LiveTransport`. `finalise` rebuilds `results.json` and the tier A subset from the journal
// after a crash, counting every label not run as failed; it needs no key and sends nothing. `check`
// makes every refusal `run` makes before the key and the catalogue (the output folder and cache are
// absent, the ledger is A3's with no A4 entry, the seals match and every case converts) and creates,
// reserves and sends nothing; it needs no key. Use
// promptfoo/run-heldout.sh, which checks the checkout and the freeze pins first.
//
// Standard output is one line of counts; standard error carries fixed reasons only, never a
// product, value, text, transcription, label ID or hash. Exit codes: 0 done, 2 usage or refusal,
// 1 an unexpected error after the run started.

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let usage = "usage: PastedLabelAITextHeldOut run|finalise|check [--private-root DIR]"
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, ["run", "finalise", "check"].contains(command) else { fail(usage) }
let rest = arguments.dropFirst()
let root: URL
switch rest.count {
case 0: root = HeldOutRun.defaultPrivateRootURL
case 2 where rest.first == "--private-root":
    root = URL(fileURLWithPath: (rest.last! as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
default: fail(usage)
}

/// The commit this executable was built from: the HEAD of the checkout holding this source file.
func currentCommit() -> String? {
    var repository = URL(fileURLWithPath: #filePath)
    // Tools/PastedLabelAITextEval/Sources/PastedLabelAITextHeldOut/main.swift
    for _ in 0 ..< 5 { repository.deleteLastPathComponent() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repository.path, "rev-parse", "HEAD"]
    // git never sees the key.
    process.environment = ["PATH": "/usr/bin:/bin"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

switch command {
case "run":
    let key: EnvironmentKey
    do { key = try EnvironmentKey() } catch {
        fail("run: OPENROUTER_API_KEY is missing, empty or malformed (its value is not shown); the run reads the key from the environment only (T4)")
    }
    guard let commit = currentCommit() else { fail("run: the commit of this checkout could not be read") }
    do {
        let counts = try await HeldOutRun.run(privateRoot: root, commit: commit, connection: LiveTransport.connection(key: key))
        print(HeldOutRun.report(counts))
    } catch let refusal as HeldOutRun.Refusal {
        fail("run: \(HeldOutRun.reason(refusal))")
    } catch {
        fail("run: \(HeldOutRun.reason(error))", code: 1)
    }
case "check":
    do {
        print(HeldOutRun.report(try HeldOutRun.check(privateRoot: root)))
    } catch {
        fail("check: \(HeldOutRun.reason(error))")
    }
default:
    do {
        print(HeldOutRun.report(try HeldOutRun.finalise(.init(root: root)).dictionary))
    } catch {
        fail("finalise: \(HeldOutRun.reason(error))")
    }
}
