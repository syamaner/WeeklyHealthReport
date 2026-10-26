import FoodLedgerApplication
import Foundation
import Network

/// Whether the device has a usable network path now (7.2, the offline state), from `NWPathMonitor`.
/// It only observes the path; it opens no connection and sends nothing.
public final class NWPathConnectivityStatus: ConnectivityStatus, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var satisfied = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock { self.satisfied = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "label-photo.connectivity"))
    }

    deinit { monitor.cancel() }

    public var isOnline: Bool { lock.withLock { satisfied } }
}
