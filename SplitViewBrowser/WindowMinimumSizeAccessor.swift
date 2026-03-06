import AppKit
import SwiftUI

struct WindowMinimumSizeAccessor: NSViewRepresentable {
    let minWidth: CGFloat
    let minHeight: CGFloat
    let pendingPresetWindowSize: CGSize?
    let onWindowContentSizeChanged: (CGSize) -> Void
    let onPendingPresetWindowSizeApplied: () -> Void

    final class Coordinator: NSObject {
        var previousMinWidth: CGFloat?
        var previousMinHeight: CGFloat?
        var lastAppliedMinSize: NSSize?
        var lastReportedContentSize: NSSize?
        weak var observedWindow: NSWindow?
        var resizeObserver: NSObjectProtocol?
        var endResizeObserver: NSObjectProtocol?
        var onWindowContentSizeChanged: ((CGSize) -> Void)?

        deinit {
            detachWindowObservers()
        }

        func bindWindow(_ window: NSWindow?, onSizeChanged: @escaping (CGSize) -> Void) {
            onWindowContentSizeChanged = onSizeChanged

            let isSameWindow: Bool = {
                switch (observedWindow, window) {
                case (.none, .none):
                    return true
                case let (.some(lhs), .some(rhs)):
                    return lhs === rhs
                default:
                    return false
                }
            }()

            guard !isSameWindow else { return }

            detachWindowObservers()
            observedWindow = window
            lastReportedContentSize = nil

            guard let window else { return }
            let center = NotificationCenter.default
            resizeObserver = center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.reportCurrentWindowContentSizeIfNeeded()
            }
            endResizeObserver = center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.reportCurrentWindowContentSizeIfNeeded()
            }
        }

        func detachWindowObservers() {
            let center = NotificationCenter.default
            if let resizeObserver {
                center.removeObserver(resizeObserver)
            }
            if let endResizeObserver {
                center.removeObserver(endResizeObserver)
            }
            resizeObserver = nil
            endResizeObserver = nil
            observedWindow = nil
        }

        func reportCurrentWindowContentSizeIfNeeded() {
            guard let window = observedWindow else { return }
            reportContentSizeIfNeeded(for: window)
        }

        func reportContentSizeIfNeeded(for window: NSWindow) {
            let finalContentSize = window.contentRect(forFrameRect: window.frame).size
            let reportEpsilon: CGFloat = 0.5
            let shouldReportSize: Bool
            if let previous = lastReportedContentSize {
                shouldReportSize =
                    abs(previous.width - finalContentSize.width) > reportEpsilon ||
                    abs(previous.height - finalContentSize.height) > reportEpsilon
            } else {
                shouldReportSize = true
            }
            guard shouldReportSize else { return }
            lastReportedContentSize = finalContentSize
            guard let onWindowContentSizeChanged else { return }
            DispatchQueue.main.async {
                onWindowContentSizeChanged(finalContentSize)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyWindowConstraints(for: view.window, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bindWindow(nsView.window, onSizeChanged: onWindowContentSizeChanged)
        applyWindowConstraints(for: nsView.window, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detachWindowObservers()
    }

    private func applyWindowConstraints(for window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }

        let previousMinWidth = coordinator.previousMinWidth ?? minWidth
        let previousMinHeight = coordinator.previousMinHeight ?? minHeight
        coordinator.previousMinWidth = minWidth
        coordinator.previousMinHeight = minHeight

        let minimumContentSize = NSSize(width: minWidth, height: minHeight)
        if coordinator.lastAppliedMinSize != minimumContentSize {
            window.contentMinSize = minimumContentSize
            coordinator.lastAppliedMinSize = minimumContentSize
        }

        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        var targetWidth = max(currentContentSize.width, minWidth)
        var targetHeight = max(currentContentSize.height, minHeight)
        var shouldConsumePendingPresetWindowSize = false

        if let pendingPresetWindowSize {
            targetWidth = max(minWidth, pendingPresetWindowSize.width)
            targetHeight = max(minHeight, pendingPresetWindowSize.height)
            shouldConsumePendingPresetWindowSize = true
        } else if minWidth < previousMinWidth, currentContentSize.width > minWidth {
            // When panel count is reduced manually, shrink to the new split width baseline.
            targetWidth = minWidth
        } else if minHeight < previousMinHeight, currentContentSize.height > minHeight {
            targetHeight = minHeight
        }

        let resizeEpsilon: CGFloat = 0.5
        let shouldResize =
            abs(targetWidth - currentContentSize.width) > resizeEpsilon ||
            abs(targetHeight - currentContentSize.height) > resizeEpsilon
        if shouldResize {
            window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
        }

        coordinator.reportContentSizeIfNeeded(for: window)

        guard shouldConsumePendingPresetWindowSize else {
            return
        }

        DispatchQueue.main.async {
            onPendingPresetWindowSizeApplied()
        }
    }
}

func preferredContentWindow() -> NSWindow? {
    if let keyWindow = NSApp.keyWindow {
        if let parent = keyWindow.sheetParent {
            return parent
        }
        return keyWindow
    }

    if let mainWindow = NSApp.mainWindow {
        if let parent = mainWindow.sheetParent {
            return parent
        }
        return mainWindow
    }

    if let visibleNonSheet = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) {
        return visibleNonSheet
    }

    return NSApp.windows.first(where: { $0.isVisible })
}
