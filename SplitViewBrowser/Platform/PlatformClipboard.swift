import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum PlatformClipboard {
    static var changeCount: Int {
        #if os(macOS)
        NSPasteboard.general.changeCount
        #elseif os(iOS)
        UIPasteboard.general.changeCount
        #else
        0
        #endif
    }

    static func readString() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #elseif os(iOS)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }

    static func writeString(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
