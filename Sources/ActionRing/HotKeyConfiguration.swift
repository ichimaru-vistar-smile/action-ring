import Carbon.HIToolbox
import Foundation

enum HotKeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift

    var symbol: String {
        switch self {
        case .command:
            "⌘"
        case .option:
            "⌥"
        case .control:
            "⌃"
        case .shift:
            "⇧"
        }
    }

    var title: String {
        switch self {
        case .command:
            "Command"
        case .option:
            "Option"
        case .control:
            "Control"
        case .shift:
            "Shift"
        }
    }

    var carbonMask: UInt32 {
        switch self {
        case .command:
            UInt32(cmdKey)
        case .option:
            UInt32(optionKey)
        case .control:
            UInt32(controlKey)
        case .shift:
            UInt32(shiftKey)
        }
    }

    static let preferredOrder: [HotKeyModifier] = [
        .command,
        .option,
        .control,
        .shift
    ]

    static func normalized(_ modifiers: [HotKeyModifier]) -> [HotKeyModifier] {
        let unique = Set(modifiers)
        let ordered = preferredOrder.filter { unique.contains($0) }
        return ordered.isEmpty ? [.command, .option] : ordered
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: [HotKeyModifier]

    init(keyCode: UInt32, modifiers: [HotKeyModifier]) {
        self.keyCode = keyCode
        self.modifiers = HotKeyModifier.normalized(modifiers)
    }

    static let `default` = HotKeyConfiguration(
        keyCode: UInt32(kVK_Space),
        modifiers: [.command, .option]
    )

    var carbonModifiers: UInt32 {
        HotKeyModifier.normalized(modifiers).reduce(0) { partialResult, modifier in
            partialResult | modifier.carbonMask
        }
    }

    var displayString: String {
        let symbols = HotKeyModifier.normalized(modifiers).map(\.symbol).joined()
        return symbols + HotKeyKeyOption.title(for: keyCode)
    }
}

struct ActionRingPreferences: Codable, Equatable, Sendable {
    var hotKey: HotKeyConfiguration
    var overlayPosition: RingOverlayPositionMode

    static let `default` = ActionRingPreferences(
        hotKey: .default,
        overlayPosition: .followsMouse
    )
}

struct HotKeyKeyOption: Identifiable, Hashable, Sendable {
    let keyCode: UInt32
    let title: String

    var id: UInt32 {
        keyCode
    }

    static let allOptions: [HotKeyKeyOption] = [
        HotKeyKeyOption(keyCode: UInt32(kVK_Space), title: "Space"),
        HotKeyKeyOption(keyCode: UInt32(kVK_Tab), title: "Tab"),
        HotKeyKeyOption(keyCode: UInt32(kVK_Return), title: "Return"),
        HotKeyKeyOption(keyCode: UInt32(kVK_Escape), title: "Escape"),
        HotKeyKeyOption(keyCode: UInt32(kVK_LeftArrow), title: "Left Arrow"),
        HotKeyKeyOption(keyCode: UInt32(kVK_RightArrow), title: "Right Arrow"),
        HotKeyKeyOption(keyCode: UInt32(kVK_UpArrow), title: "Up Arrow"),
        HotKeyKeyOption(keyCode: UInt32(kVK_DownArrow), title: "Down Arrow"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Grave), title: "`"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Minus), title: "-"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Equal), title: "="),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_LeftBracket), title: "["),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_RightBracket), title: "]"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Semicolon), title: ";"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Quote), title: "'"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Comma), title: ","),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Period), title: "."),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Slash), title: "/"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Backslash), title: "\\"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_A), title: "A"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_B), title: "B"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_C), title: "C"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_D), title: "D"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_E), title: "E"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_F), title: "F"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_G), title: "G"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_H), title: "H"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_I), title: "I"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_J), title: "J"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_K), title: "K"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_L), title: "L"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_M), title: "M"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_N), title: "N"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_O), title: "O"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_P), title: "P"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Q), title: "Q"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_R), title: "R"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_S), title: "S"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_T), title: "T"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_U), title: "U"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_V), title: "V"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_W), title: "W"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_X), title: "X"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Y), title: "Y"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_Z), title: "Z"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_0), title: "0"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_1), title: "1"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_2), title: "2"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_3), title: "3"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_4), title: "4"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_5), title: "5"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_6), title: "6"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_7), title: "7"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_8), title: "8"),
        HotKeyKeyOption(keyCode: UInt32(kVK_ANSI_9), title: "9")
    ]

    static func option(for keyCode: UInt32) -> HotKeyKeyOption {
        allOptions.first(where: { $0.keyCode == keyCode }) ?? HotKeyKeyOption(
            keyCode: keyCode,
            title: "Key \(keyCode)"
        )
    }

    static func title(for keyCode: UInt32) -> String {
        option(for: keyCode).title
    }
}
