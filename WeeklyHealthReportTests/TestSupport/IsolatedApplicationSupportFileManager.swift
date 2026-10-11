import Foundation

/// Redirect only the existing application-support capability to an isolated test directory.
final class IntakeRenderFileManager: FileManager, @unchecked Sendable {
    private let directory: URL
    init(directory: URL) { self.directory = directory; super.init() }
    override func url(for directory: FileManager.SearchPathDirectory,
                      in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        guard directory == .applicationSupportDirectory else {
            return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
        }
        if shouldCreate { try createDirectory(at: self.directory, withIntermediateDirectories: true) }
        return self.directory
    }
}
