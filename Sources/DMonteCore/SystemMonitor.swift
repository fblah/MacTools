import Combine
import Foundation

@MainActor
public final class SystemMonitor: ObservableObject {
    @Published public private(set) var snapshot = MetricSnapshot.placeholder

    private let provider = SystemMetricsProvider()
    private var timer: Timer?

    public init(snapshot: MetricSnapshot = .placeholder) {
        self.snapshot = snapshot
    }

    public func start() {
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        snapshot = provider.sample()
    }
}
