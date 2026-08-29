import Foundation

public final class CommandParser {
    private var tokens: [CommandToken] = []
    private var position: Int = 0
    private var hasOperatorOrFunc: Bool = false

    public init() {}

    private var current: CommandToken {
        guard position < tokens.count else { return .eof }
        return tokens[position]
    }

    private func advance() -> CommandToken {
        let tok = current
        if position < tokens.count {
            position += 1
        }
        return tok
    }

    private func match(_ token: CommandToken) -> Bool {
        if current == token {
            _ = advance()
            return true
        }
        return false
    }

    public func parse(_ input: String) -> CommandAST {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }

        let lexer = CommandLexer(input: input)
        self.tokens = lexer.tokenize()
        self.position = 0
        self.hasOperatorOrFunc = false

        // 1. Check for bang command (e.g. !e, !emoji, !emoji smile)
        if case .bang(let bangName, let hasTrailingSpace) = current {
            if !hasTrailingSpace && position + 1 >= tokens.count - 1 {
                return .bangSuggestion(prefix: bangName)
            }
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
            return .command(name: bangName, args: args, flags: flags)
        }

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

    private func parseMathExpression() -> MathExpressionAST? {
        return parseExpression()
    }

    private func parseExpression() -> MathExpressionAST? {
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

    private func parseTerm() -> MathExpressionAST? {
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

    private func parsePower() -> MathExpressionAST? {
        guard let base = parseUnary() else { return nil }

        if current == .caret {
            _ = advance()
            guard let exponent = parsePower() else { return nil } // Right-associative
            hasOperatorOrFunc = true
            return .binary(op: .power, left: base, right: exponent)
        }

        return base
    }

    private func parseUnary() -> MathExpressionAST? {
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

    private static let knownConstants: Set<String> = ["pi", "e", "tau"]
    private static let knownFunctions: Set<String> = [
        "sqrt", "cbrt", "abs", "fabs", "sin", "cos", "tan", "asin", "acos", "atan",
        "log", "ln", "log10", "log2", "exp", "floor", "ceil", "round",
        "pow", "atan2", "min", "max"
    ]

    private func parsePrimary() -> MathExpressionAST? {
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
