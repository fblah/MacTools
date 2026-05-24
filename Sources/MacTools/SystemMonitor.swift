import Combine
import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = MetricSnapshot.placeholder

    private let provider = SystemMetricsProvider()
    private var timer: Timer?

    func start() {
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        snapshot = provider.sample()
    }
}
