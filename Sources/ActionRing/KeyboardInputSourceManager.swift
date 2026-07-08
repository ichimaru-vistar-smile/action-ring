import Carbon.HIToolbox
import Foundation

enum KeyboardInputSourceManager {
    static func selectEnglishInputSource() {
        for identifier in preferredEnglishSourceIdentifiers {
            if selectSource(withIdentifier: identifier) {
                return
            }
        }

        _ = selectInputSourceForEnglishLanguage()
    }

    private static let preferredEnglishSourceIdentifiers = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]

    private static func selectSource(withIdentifier identifier: String) -> Bool {
        let properties = [
            kTISPropertyInputSourceID as String: identifier
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }

        for source in sourceList where TISSelectInputSource(source) == noErr {
            return true
        }

        return false
    }

    private static func selectInputSourceForEnglishLanguage() -> Bool {
        guard let source = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue() else {
            return false
        }

        return TISSelectInputSource(source) == noErr
    }
}
