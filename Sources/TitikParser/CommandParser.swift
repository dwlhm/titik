import Foundation

public final class CommandParser: Sendable {
    public init() {}

    public func parse(_ input: String) -> CommandAST {
        parse(input, knownSubcommands: [])
    }

    public func parse(_ input: String, knownSubcommands: Set<String>) -> CommandAST {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }

        // 1. Check for command mode (starts with '!')
        if trimmed.hasPrefix("!") {
            return parseBangInvocation(input: input, trimmed: trimmed, knownSubcommands: knownSubcommands)
        }

        let lexer = CommandLexer(input: input)
        let tokens = lexer.tokenize()
        var state = ParserState(tokens: tokens)
        return state.parse(trimmed: trimmed)
    }

    // MARK: - Delimiter-Bounded Segment Parser

    private func parseBangInvocation(input: String, trimmed: String, knownSubcommands: Set<String>) -> CommandAST {
        // Collect trigger name after '!'
        var trigger = ""
        var afterBangIdx = trimmed.index(after: trimmed.startIndex)
        while afterBangIdx < trimmed.endIndex {
            let ch = trimmed[afterBangIdx]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" {
                trigger.append(ch)
                afterBangIdx = trimmed.index(after: afterBangIdx)
            } else {
                break
            }
        }

        let cleanTrigger = trigger.lowercased()
        if cleanTrigger.isEmpty {
            return .bangSuggestion(prefix: "")
        }

        let bangPrefix = "!" + trigger
        guard let bangRange = input.range(of: bangPrefix) else {
            return .bangSuggestion(prefix: cleanTrigger)
        }
        let tailSubstring = input[bangRange.upperBound...]

        // If input is just "!prefix" without trailing space, return suggestion
        if tailSubstring.isEmpty {
            return .bangSuggestion(prefix: cleanTrigger)
        }

        let rawTail = tailSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTail.isEmpty {
            return .pluginInvocation(
                trigger: cleanTrigger,
                action: nil,
                primaryValue: "",
                flags: [:],
                booleanFlags: [],
                rawTail: ""
            )
        }

        var segmentTokens = tokenizeSegments(rawTail)

        // Check if first word is a known subcommand
        var action: String? = nil
        if let first = segmentTokens.first, !first.isFlag {
            let candidate = first.unquoted.lowercased()
            if knownSubcommands.contains(candidate) {
                action = candidate
                segmentTokens.removeFirst()
            }
        }

        var flags: [String: String] = [:]
        var booleanFlags: Set<String> = []
        var primaryTokens: [String] = []
        var trailingPositional: [String] = []

        let firstFlagIdx = segmentTokens.firstIndex(where: { $0.isFlag })

        if let flagIdx = firstFlagIdx {
            primaryTokens = segmentTokens[0..<flagIdx].map(\.unquoted)

            var i = flagIdx
            while i < segmentTokens.count {
                let token = segmentTokens[i]
                if token.isFlag, let flagName = token.flagName {
                    if let inlineVal = token.flagInlineValue {
                        flags[flagName] = inlineVal
                        if ["true", "false"].contains(inlineVal.lowercased()) {
                            booleanFlags.insert(flagName)
                        }
                        i += 1
                    } else {
                        var valTokens: [String] = []
                        var j = i + 1
                        while j < segmentTokens.count && !segmentTokens[j].isFlag {
                            valTokens.append(segmentTokens[j].unquoted)
                            j += 1
                        }
                        if valTokens.isEmpty {
                            booleanFlags.insert(flagName)
                            flags[flagName] = "true"
                            i = j
                        } else {
                            let joinedVal = valTokens.joined(separator: " ")
                            flags[flagName] = joinedVal
                            if ["true", "false"].contains(joinedVal.lowercased()) {
                                booleanFlags.insert(flagName)
                            }
                            i = j
                        }
                    }
                } else {
                    trailingPositional.append(token.unquoted)
                    i += 1
                }
            }
        } else {
            primaryTokens = segmentTokens.map(\.unquoted)
        }

        var primaryValue = primaryTokens.joined(separator: " ")
        if primaryValue.isEmpty && !trailingPositional.isEmpty {
            primaryValue = trailingPositional.joined(separator: " ")
        }

        return .pluginInvocation(
            trigger: cleanTrigger,
            action: action,
            primaryValue: primaryValue,
            flags: flags,
            booleanFlags: booleanFlags,
            rawTail: rawTail
        )
    }

    private struct SegmentToken: Equatable {
        let raw: String
        let unquoted: String
        let isFlag: Bool
        let flagName: String?
        let flagInlineValue: String?
    }

    private func tokenizeSegments(_ input: String) -> [SegmentToken] {
        var tokens: [SegmentToken] = []
        let chars = Array(input)
        var idx = 0

        while idx < chars.count {
            while idx < chars.count && chars[idx].isWhitespace {
                idx += 1
            }
            if idx >= chars.count { break }

            let startIdx = idx
            var tokenStr = ""

            if chars[idx] == "\"" || chars[idx] == "'" {
                let quote = chars[idx]
                idx += 1
                while idx < chars.count && chars[idx] != quote {
                    if chars[idx] == "\\" && idx + 1 < chars.count && chars[idx + 1] == quote {
                        idx += 1
                    }
                    tokenStr.append(chars[idx])
                    idx += 1
                }
                if idx < chars.count && chars[idx] == quote {
                    idx += 1
                }
                tokens.append(SegmentToken(
                    raw: String(chars[startIdx..<idx]),
                    unquoted: tokenStr,
                    isFlag: false,
                    flagName: nil,
                    flagInlineValue: nil
                ))
                continue
            }

            while idx < chars.count && !chars[idx].isWhitespace {
                if chars[idx] == "\"" || chars[idx] == "'" {
                    let quote = chars[idx]
                    idx += 1
                    while idx < chars.count && chars[idx] != quote {
                        if chars[idx] == "\\" && idx + 1 < chars.count && chars[idx + 1] == quote {
                            idx += 1
                        }
                        tokenStr.append(chars[idx])
                        idx += 1
                    }
                    if idx < chars.count && chars[idx] == quote {
                        idx += 1
                    }
                } else {
                    tokenStr.append(chars[idx])
                    idx += 1
                }
            }

            let raw = String(chars[startIdx..<idx])
            let (isFlag, flagName, inlineVal) = parseFlag(tokenStr)
            tokens.append(SegmentToken(
                raw: raw,
                unquoted: tokenStr,
                isFlag: isFlag,
                flagName: flagName,
                flagInlineValue: inlineVal
            ))
        }

        return tokens
    }

    private func parseFlag(_ token: String) -> (isFlag: Bool, flagName: String?, flagInlineValue: String?) {
        guard token.hasPrefix("-") else { return (false, nil, nil) }

        var withoutDashes = token
        if withoutDashes.hasPrefix("--") {
            withoutDashes.removeFirst(2)
        } else {
            withoutDashes.removeFirst(1)
        }

        guard !withoutDashes.isEmpty else { return (false, nil, nil) }
        guard let first = withoutDashes.first, first.isLetter || first == "_" else {
            return (false, nil, nil)
        }

        if let eqIdx = withoutDashes.firstIndex(of: "=") {
            let name = String(withoutDashes[..<eqIdx])
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                return (false, nil, nil)
            }
            let rawVal = String(withoutDashes[withoutDashes.index(after: eqIdx)...])
            let cleanVal = unquote(rawVal)
            return (true, name, cleanVal)
        } else {
            guard withoutDashes.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                return (false, nil, nil)
            }
            return (true, withoutDashes, nil)
        }
    }

    private func unquote(_ s: String) -> String {
        if (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) ||
           (s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private struct ParserState {
        var tokens: [CommandToken]
        var position: Int = 0
        var hasOperatorOrFunc: Bool = false

        private var current: CommandToken {
            guard position < tokens.count else { return .eof }
            return tokens[position]
        }

        private mutating func advance() -> CommandToken {
            let tok = current
            if position < tokens.count {
                position += 1
            }
            return tok
        }

        private mutating func match(_ token: CommandToken) -> Bool {
            if current == token {
                _ = advance()
                return true
            }
            return false
        }

        mutating func parse(trimmed: String) -> CommandAST {
            // 2. Check for command prefix (e.g. app:safari, cmd:lock, clip:1)
            if case .prefix(let prefixName) = current {
                _ = advance()
                var args: [String] = []
                var flags: [String: String] = [:]

                while current != .eof {
                    switch current {
                    case .flag(let name, let value):
                        flags[name] = value ?? "true"
                        _ = advance()
                    case .identifier(let id):
                        args.append(id)
                        _ = advance()
                    case .stringLiteral(let s):
                        args.append(s)
                        _ = advance()
                    case .number(let n):
                        if n.rounded() == n {
                            args.append(String(Int(n)))
                        } else {
                            args.append(String(n))
                        }
                        _ = advance()
                    case .plus:
                        args.append("+")
                        _ = advance()
                    case .minus:
                        args.append("-")
                        _ = advance()
                    case .star:
                        args.append("*")
                        _ = advance()
                    case .slash:
                        args.append("/")
                        _ = advance()
                    case .percent:
                        args.append("%")
                        _ = advance()
                    case .caret:
                        args.append("^")
                        _ = advance()
                    case .equal:
                        args.append("=")
                        _ = advance()
                    case .lparen:
                        args.append("(")
                        _ = advance()
                    case .rparen:
                        args.append(")")
                        _ = advance()
                    case .comma:
                        args.append(",")
                        _ = advance()
                    default:
                        _ = advance()
                    }
                }
                return .command(name: prefixName, args: args, flags: flags)
            }

            // 2. Check for explicit math prefixes: '=', 'calc', 'math', 'calculate'
            var isExplicitMath = false
            if current == .equal {
                _ = advance()
                isExplicitMath = true
            } else if case .identifier(let id) = current, ["calc", "math", "calculate"].contains(id) {
                _ = advance()
                isExplicitMath = true
            }

            // Try parsing as math expression
            if let mathExpr = parseMathExpression() {
                if current == .eof && (isExplicitMath || hasOperatorOrFunc) {
                    return .expression(mathExpr)
                }
            }

            // If not math and not prefix command, check if it looks like command syntax (e.g. `kill --force pid`)
            position = 0
            if case .identifier(let cmdName) = current {
                _ = advance()
                var args: [String] = []
                var flags: [String: String] = [:]
                var hasFlags = false

                while current != .eof {
                    switch current {
                    case .flag(let name, let value):
                        flags[name] = value ?? "true"
                        hasFlags = true
                        _ = advance()
                    case .identifier(let id):
                        args.append(id)
                        _ = advance()
                    case .stringLiteral(let s):
                        args.append(s)
                        _ = advance()
                    case .number(let n):
                        if n.rounded() == n {
                            args.append(String(Int(n)))
                        } else {
                            args.append(String(n))
                        }
                        _ = advance()
                    default:
                        _ = advance()
                    }
                }

                if hasFlags {
                    return .command(name: cmdName, args: args, flags: flags)
                }
            }

            // Fallback to raw query
            return .raw(query: trimmed)
        }

        // MARK: - Math Recursive Descent Parser

        private mutating func parseMathExpression() -> MathExpressionAST? {
            return parseExpression()
        }

        private mutating func parseExpression() -> MathExpressionAST? {
            guard var left = parseTerm() else { return nil }

            while current == .plus || current == .minus {
                let opToken = advance()
                guard let right = parseTerm() else { return nil }
                let op: MathBinaryOp = (opToken == .plus) ? .add : .subtract
                hasOperatorOrFunc = true
                left = .binary(op: op, left: left, right: right)
            }

            return left
        }

        private mutating func parseTerm() -> MathExpressionAST? {
            guard var left = parsePower() else { return nil }

            while current == .star || current == .slash || current == .percent {
                let opToken = advance()
                guard let right = parsePower() else { return nil }
                let op: MathBinaryOp
                switch opToken {
                case .star: op = .multiply
                case .slash: op = .divide
                case .percent: op = .modulo
                default: return nil
                }
                hasOperatorOrFunc = true
                left = .binary(op: op, left: left, right: right)
            }

            return left
        }

        private mutating func parsePower() -> MathExpressionAST? {
            guard let base = parseUnary() else { return nil }

            if current == .caret {
                _ = advance()
                guard let exponent = parsePower() else { return nil } // Right-associative
                hasOperatorOrFunc = true
                return .binary(op: .power, left: base, right: exponent)
            }

            return base
        }

        private mutating func parseUnary() -> MathExpressionAST? {
            if current == .plus {
                _ = advance()
                guard let operand = parseUnary() else { return nil }
                return .unary(op: .plus, operand: operand)
            }
            if current == .minus {
                _ = advance()
                guard let operand = parseUnary() else { return nil }
                return .unary(op: .minus, operand: operand)
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> MathExpressionAST? {
            switch current {
            case .number(let val):
                _ = advance()
                return .number(val)

            case .lparen:
                _ = advance()
                guard let expr = parseExpression() else { return nil }
                guard match(.rparen) else { return nil }
                return expr

            case .identifier(let name):
                _ = advance()

                // Check if constant
                if CommandParser.knownConstants.contains(name) {
                    hasOperatorOrFunc = true
                    return .constant(name)
                }

                // Check if function call: name(...)
                if current == .lparen {
                    _ = advance()
                    var args: [MathExpressionAST] = []
                    if current != .rparen {
                        guard let firstArg = parseExpression() else { return nil }
                        args.append(firstArg)
                        while match(.comma) {
                            guard let nextArg = parseExpression() else { return nil }
                            args.append(nextArg)
                        }
                    }
                    guard match(.rparen) else { return nil }
                    hasOperatorOrFunc = true
                    return .function(name: name, args: args)
                }

                return nil

            default:
                return nil
            }
        }
    }

    private static let knownConstants: Set<String> = ["pi", "e", "tau"]
    private static let knownFunctions: Set<String> = [
        "sqrt", "cbrt", "abs", "fabs", "sin", "cos", "tan", "asin", "acos", "atan",
        "log", "ln", "log10", "log2", "exp", "floor", "ceil", "round",
        "pow", "atan2", "min", "max"
    ]
}
