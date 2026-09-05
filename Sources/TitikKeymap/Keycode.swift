import Foundation
import Carbon

public enum Keycode: UInt32, CaseIterable, Hashable, Sendable {
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F
    case y = 0x10
    case t = 0x11
    case one = 0x12
    case two = 0x13
    case three = 0x14
    case four = 0x15
    case six = 0x16
    case five = 0x17
    case equal = 0x18
    case nine = 0x19
    case seven = 0x1A
    case minus = 0x1B
    case eight = 0x1C
    case zero = 0x1D
    case rightBracket = 0x1E
    case o = 0x1F
    case u = 0x20
    case leftBracket = 0x21
    case i = 0x22
    case p = 0x23
    case l = 0x25
    case j = 0x26
    case quote = 0x27
    case k = 0x28
    case semicolon = 0x29
    case backslash = 0x2A
    case comma = 0x2B
    case slash = 0x2C
    case n = 0x2D
    case m = 0x2E
    case period = 0x2F
    case grave = 0x32

    // Control and navigation keys
    case returnKey = 0x24
    case tab = 0x30
    case space = 0x31
    case delete = 0x33
    case escape = 0x35
    case command = 0x37
    case shift = 0x38
    case option = 0x3A
    case control = 0x3B
    case upArrow = 0x7E
    case downArrow = 0x7D
    case leftArrow = 0x7B
    case rightArrow = 0x7C

    // Function keys
    case f1 = 0x7A
    case f2 = 0x78
    case f3 = 0x63
    case f4 = 0x76
    case f5 = 0x60
    case f6 = 0x61
    case f7 = 0x62
    case f8 = 0x64
    case f9 = 0x65
    case f10 = 0x6D
    case f11 = 0x67
    case f12 = 0x6F

    public var displayGlyph: String {
        switch self {
        case .returnKey: return "↵"
        case .tab: return "⇥"
        case .space: return "␣"
        case .delete: return "⌫"
        case .escape: return "⎋"
        case .command: return "⌘"
        case .shift: return "⇧"
        case .option: return "⌥"
        case .control: return "⌃"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .period: return "."
        case .comma: return ","
        case .slash: return "/"
        case .backslash: return "\\"
        case .equal: return "="
        case .minus: return "-"
        case .semicolon: return ";"
        case .quote: return "'"
        case .grave: return "`"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        }
    }

    public static func fromString(_ str: String) -> Keycode? {
        let clean = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case ".", "period", "dot": return .period
        case ",", "comma": return .comma
        case "/", "slash": return .slash
        case "\\", "backslash": return .backslash
        case "=", "equal", "equals": return .equal
        case "+", "plus": return .equal
        case "-", "minus", "dash": return .minus
        case ";", "semicolon": return .semicolon
        case "'", "quote": return .quote
        case "\"": return .quote
        case "`", "grave", "backquote", "backtick": return .grave
        case "~": return .grave
        case "[", "leftbracket": return .leftBracket
        case "]", "rightbracket": return .rightBracket
        case "{": return .leftBracket
        case "}": return .rightBracket
        case ":": return .semicolon
        case "<": return .comma
        case ">": return .period
        case "?": return .slash
        case "space", " ", "␣": return .space
        case "return", "enter", "cr", "lf", "↵": return .returnKey
        case "esc", "escape", "⎋": return .escape
        case "tab", "⇥": return .tab
        case "delete", "backspace", "⌫": return .delete
        case "up", "uparrow", "↑": return .upArrow
        case "down", "downarrow", "↓": return .downArrow
        case "left", "leftarrow", "←": return .leftArrow
        case "right", "rightarrow", "→": return .rightArrow
        case "0": return .zero
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "f1": return .f1
        case "f2": return .f2
        case "f3": return .f3
        case "f4": return .f4
        case "f5": return .f5
        case "f6": return .f6
        case "f7": return .f7
        case "f8": return .f8
        case "f9": return .f9
        case "f10": return .f10
        case "f11": return .f11
        case "f12": return .f12
        default: return nil
        }
    }
}
