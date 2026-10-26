import Foundation
import Network

@Observable
final class NetworkMonitor {
    var isOnline: Bool = true
    var isConstrained: Bool = false
    /// Mobile data or a personal hotspot — a connection someone may be paying for by the byte.
    var isExpensive: Bool = false
    var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Online without mobile data or Low Data Mode: where bulk downloads are welcome.
    var isUnmetered: Bool { isOnline && !isExpensive && !isConstrained }

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.ondumusic.networkmonitor")
    @ObservationIgnored private var powerObserver: Any?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isConstrained = path.isConstrained
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)

        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    deinit {
        monitor.cancel()
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }
}
