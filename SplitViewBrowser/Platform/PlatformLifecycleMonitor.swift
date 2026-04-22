import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

final class PlatformLifecycleMonitor {
    private var observers: [NSObjectProtocol] = []

    var isActiveNow: Bool {
        #if os(macOS)
        NSApp?.isActive ?? true
        #elseif os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }

    func start(
        onBecomeActive: @escaping () -> Void,
        onResignActive: @escaping () -> Void
    ) {
        stop()

        let center = NotificationCenter.default

        #if os(macOS)
        let didResign = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            onResignActive()
        }
        let didBecome = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            onBecomeActive()
        }
        observers = [didResign, didBecome]
        #elseif os(iOS)
        let willResign = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            onResignActive()
        }
        let didBecome = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            onBecomeActive()
        }
        observers = [willResign, didBecome]
        #endif
    }

    func stop() {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        stop()
    }
}
