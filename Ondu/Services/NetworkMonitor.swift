import Foundation
import Network

@Observable
final class NetworkMonitor {
    var isOnline: Bool = true
    var isConstrained: Bool = false
    var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.ondumusic.networkmonitor")
    @ObservationIgnored private var powerObserver: Any?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isConstrained = path.isConstrained
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
