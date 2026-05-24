import AppKit

final class SystemMonitorStatusView: NSControl {
    private let iconView = NSImageView()
    private let downLabel = NSTextField(labelWithString: "--")
    private let upLabel = NSTextField(labelWithString: "--")
    private let cpuValueLabel = NSTextField(labelWithString: "--")
    private let ramValueLabel = NSTextField(labelWithString: "--")
    private let ssdValueLabel = NSTextField(labelWithString: "--")

    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(snapshot: MetricSnapshot) {
        downLabel.stringValue = "↓ \(snapshot.networkDownRate.compactRateString)"
        upLabel.stringValue = "↑ \(snapshot.networkUpRate.compactRateString)"
        cpuValueLabel.stringValue = snapshot.cpuUsage.percentString
        ramValueLabel.stringValue = snapshot.memoryUsage.percentString
        ssdValueLabel.stringValue = snapshot.diskAvailable.compactBytesString
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    private func setup() {
        wantsLayer = true
        frame = NSRect(x: 0, y: 0, width: 270, height: NSStatusBar.system.thickness)
        toolTip = "System Monitor"

        iconView.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "System Monitor")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let networkStack = NSStackView(views: [downLabel, upLabel])
        networkStack.orientation = .vertical
        networkStack.alignment = .leading
        networkStack.spacing = -1
        networkStack.translatesAutoresizingMaskIntoConstraints = false

        let metricsStack = NSStackView(views: [
            metricStack(title: "CPU", valueLabel: cpuValueLabel),
            metricStack(title: "RAM", valueLabel: ramValueLabel),
            metricStack(title: "SSD", valueLabel: ssdValueLabel)
        ])
        metricsStack.orientation = .horizontal
        metricsStack.alignment = .centerY
        metricsStack.spacing = 12
        metricsStack.translatesAutoresizingMaskIntoConstraints = false

        let rootStack = NSStackView(views: [iconView, networkStack, metricsStack])
        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 9
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)

        [downLabel, upLabel, cpuValueLabel, ramValueLabel, ssdValueLabel].forEach(configureValueLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 270),
            heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func metricStack(title: String, valueLabel: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        configureTitleLabel(titleLabel)

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = -1
        return stack
    }

    private func configureTitleLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
}
