import Foundation

/// Where the evaluation may write (docs/confirm-enrichment-openrouter-v1.md section 11.1a): raw responses,
/// the ledger and the first-request record stay in the owner's private folder, never inside the repository.
public enum EvalPaths {
    /// Whether `path` is the repository or inside it, after resolving `.` and `..` and symbolic links.
    public static func isInside(_ path: String, repository: String) -> Bool {
        func resolved(_ text: String) -> [String] {
            URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath().pathComponents
        }
        // Case-insensitive, as the default APFS volume is.
        let folder = resolved(path).map { $0.lowercased() }, repo = resolved(repository).map { $0.lowercased() }
        return folder.count >= repo.count && Array(folder.prefix(repo.count)) == repo
    }
}
