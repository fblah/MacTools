import AppKit
import SwiftUI

/// The Window Manager popover: a grid of snap tiles that resize the frontmost app's focused
/// window, an Accessibility-permission banner when the grant is missing, and the default
/// keyboard-shortcut hints.
public struct WindowManagerPopoverView: View {
    @ObservedObject var controller: WindowManagerController
    var onQuit: () -> Void

    private let scale = WindowManagerSizing.currentScale

    public init(controller: WindowManagerController, onQuit: @escaping () -> Void) {
        self.controller = controller
        self.onQuit = onQuit
    }

    private func s(_ value: CGFloat) -> CGFloat { value * scale }

    // Tile groups, laid out top to bottom.
    private let halves: [WindowAction] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
    private let corners: [WindowAction] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    private let thirds: [WindowAction] = [.leftThird, .centerThird, .rightThird, .firstTwoThirds, .lastTwoThirds]
    private let sizing: [WindowAction] = [.maximize, .almostMaximize, .center]

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: s(14)) {
                    if !controller.hasAccessibility {
                        permissionBanner
                    }
                    section("Halves", halves, columns: 4)
                    section("Corners", corners, columns: 4)
                    section("Thirds", thirds, columns: 5)
                    section("Size", sizing, columns: 3)
                    shortcutHint
                }
                .padding(.horizontal, s(16))
                .padding(.vertical, s(12))
            }
        }
        .frame(width: WindowManagerSizing.preferredSize().width, height: WindowManagerSizing.preferredSize().height)
        .frostedPanel(cornerRadius: 18)
        .onAppear { controller.refreshPermission() }
    }

    private var header: some View {
        HStack(spacing: s(8)) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: s(15), weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Window Manager")
                .font(.system(size: s(15), weight: .bold))
                .foregroundStyle(.primary.opacity(0.9))
            Spacer()
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: s(15), weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Window Manager")
        }
        .padding(.horizontal, s(16))
        .padding(.top, s(14))
        .padding(.bottom, s(10))
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: s(6)) {
            Label("Accessibility access needed", systemImage: "lock.shield")
                .font(.system(size: s(12), weight: .semibold))
                .foregroundStyle(.orange)
            Text("Window Manager moves other apps' windows, which macOS gates behind Accessibility. Grant access, then the snaps and shortcuts activate.")
                .font(.system(size: s(11)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") {
                controller.requestPermission()
            }
            .font(.system(size: s(12), weight: .medium))
        }
        .padding(s(10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: s(8)).fill(Color.orange.opacity(0.12)))
    }

    private func section(_ title: String, _ actions: [WindowAction], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: s(6)) {
            Text(title)
                .font(.system(size: s(11), weight: .bold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: s(6)), count: columns),
                spacing: s(6)
            ) {
                ForEach(actions) { action in
                    tile(action)
                }
            }
        }
    }

    private func tile(_ action: WindowAction) -> some View {
        Button {
            controller.apply(action)
        } label: {
            VStack(spacing: s(4)) {
                Image(systemName: action.symbol)
                    .font(.system(size: s(17), weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(action.title)
                    .font(.system(size: s(8.5), weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, s(8))
            .background(RoundedRectangle(cornerRadius: s(8), style: .continuous).fill(Color.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: s(8), style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!controller.hasAccessibility)
        .opacity(controller.hasAccessibility ? 1 : 0.5)
        .help(shortcutLabel(for: action).map { "\(action.title)  \($0)" } ?? action.title)
    }

    private var shortcutHint: some View {
        VStack(alignment: .leading, spacing: s(3)) {
            Text("Shortcuts use ⌃⌥ + arrows · ⌃⌥↩ maximize · ⌃⌥C center")
                .font(.system(size: s(9.5)))
                .foregroundStyle(.secondary)
            if case .noFocusedWindow = controller.lastResult {
                Text("No focused window to arrange.")
                    .font(.system(size: s(9.5)))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.top, s(2))
    }

    /// A human-readable shortcut label for tiles that have a default shortcut.
    private func shortcutLabel(for action: WindowAction) -> String? {
        guard let shortcut = action.defaultShortcut else { return nil }
        let arrows: [UInt32: String] = [
            HotKeyCode.left: "←", HotKeyCode.right: "→", HotKeyCode.up: "↑", HotKeyCode.down: "↓",
            HotKeyCode.returnKey: "↩", HotKeyCode.c: "C"
        ]
        return "⌃⌥" + (arrows[shortcut.keyCode] ?? "?")
    }
}
