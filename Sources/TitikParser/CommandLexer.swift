import Foundation

public enum CommandToken: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case flag(name: String, value: String?)
    case prefix(String)
    case equal
    case plus
    case minus
    case star
    case slash
    case percent
    case caret
    case lparen
    case rparen
    case comma
    case stringLiteral(String)
    case eof
}

public final class CommandLexer {
    private let chars: [Character]
    private var index: Int = 0

    public init(input: String) {
        self.chars = Array(input)
        self.index = 0
    }

    private var isAtEnd: Bool {
        index >= chars.count
    }

    private var current: Character {
        guard !isAtEnd else { return "\0" }
        return chars[index]
    }

    private var peekNext: Character {
        guard index + 1 < chars.count else { return "\0" }
        return chars[index + 1]
    }

    private func advance() -> Character {
        let ch = current
        index += 1
        return ch
    }

    private func skipWhitespace() {
        while !isAtEnd && current.isWhitespace {
            _ = advance()
        }
    }

    public func nextToken() -> CommandToken {
        skipWhitespace()

        guard !isAtEnd else { return .eof }

        let ch = current

        // Number: starts with digit, or '.' followed by digit
        if ch.isNumber || (ch == "." && peekNext.isNumber) {
            return readNumber()
        }

        // Flags: starts with '-' or '--'
        if ch == "-" && (peekNext.isLetter || peekNext == "-") {
            let startIdx = index
            _ = advance()
            if current == "-" {
                _ = advance()
            }
            if current.isLetter {
                var flagName = ""
                while !isAtEnd && (current.isLetter || current.isNumber || current == "-" || current == "_") {
                    flagName.append(advance())
                }
                var flagValue: String? = nil
                if current == "=" {
                    _ = advance()
                    var val = ""
                    if current == "\"" || current == "'" {
                        val = readQuotedString(quote: advance())
                    } else {
                        while !isAtEnd && !current.isWhitespace {
                            val.append(advance())
                        }
                    }
                    flagValue = val
                }
                return .flag(name: flagName, value: flagValue)
            } else {
                // Was just a minus sign
                index = startIdx
            }
        }

        // Quoted string
        if ch == "\"" || ch == "'" {
            _ = advance()
            let str = readQuotedString(quote: ch)
            return .stringLiteral(str)
        }

        // UTF-8 Math symbols: π, ×, ÷
        if ch == "π" {
            _ = advance()
            return .identifier("pi")
        }
        if ch == "×" {
            _ = advance()
            return .star
        }
        if ch == "÷" {
            _ = advance()
            return .slash
        }

        // Identifiers and prefixes (e.g. app:safari, cmd:lock, clip:copy, calc, math)
        if ch.isLetter || ch == "_" {
            var ident = ""
            while !isAtEnd && (current.isLetter || current.isNumber || current == "_" || current == ".") {
                ident.append(advance())
            }
            if current == ":" {
                _ = advance()
                return .prefix(ident.lowercased())
            }
            return .identifier(ident.lowercased())
        }

        // Single and multi-character operators
        _ = advance()
        switch ch {
        case "+": return .plus
        case "-": return .minus
        case "*":
            if current == "*" {
                _ = advance()
                return .caret
            }
            return .star
        case "/": return .slash
        case "%": return .percent
        case "^": return .caret
        case "=": return .equal
        case "(": return .lparen
        case ")": return .rparen
        case ",": return .comma
        default:
            return .identifier(String(ch))
        }
    }

    private func readNumber() -> CommandToken {
        var str = ""
        while !isAtEnd && (current.isNumber || current == ".") {
            str.append(advance())
        }
        // Check exponent part (e.g. 1e5, 1.2e-3)
        if (current == "e" || current == "E") && (peekNext.isNumber || peekNext == "+" || peekNext == "-") {
            str.append(advance())
            if current == "+" || current == "-" {
                str.append(advance())
            }
            while !isAtEnd && current.isNumber {
                str.append(advance())
            }
        }
        if let val = Double(str) {
            return .number(val)
        }
        return .identifier(str)
    }

    private func readQuotedString(quote: Character) -> String {
        var str = ""
        while !isAtEnd && current != quote {
            if current == "\\" && peekNext == quote {
                _ = advance()
            }
            str.append(advance())
        }
        if !isAtEnd && current == quote {
            _ = advance()
        }
        return str
    }

    public func tokenize() -> [CommandToken] {
        var tokens: [CommandToken] = []
        while true {
            let tok = nextToken()
            tokens.append(tok)
            if tok == .eof {
                break
            }
        }
        return tokens
    }
}
