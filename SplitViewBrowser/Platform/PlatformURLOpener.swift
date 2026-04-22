import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum PlatformURLOpener {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}
