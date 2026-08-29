import Foundation
import TitikParser

public enum MathEvaluatorError: Error, Equatable, LocalizedError {
    case divisionByZero
    case moduloByZero
    case domainError(String)
    case unknownFunction(String)
    case unknownConstant(String)
    case invalidArgumentCount(funcName: String, expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .divisionByZero: return "Division by zero"
        case .moduloByZero: return "Modulo by zero"
        case .domainError(let msg): return "Domain error: \(msg)"
        case .unknownFunction(let name): return "Unknown function: \(name)"
        case .unknownConstant(let name): return "Unknown constant: \(name)"
        case .invalidArgumentCount(let name, let exp, let got):
            return "Function '\(name)' expects \(exp) arguments, got \(got)"
        }
    }
}

public enum MathEvaluator {
    public static func evaluate(_ ast: MathExpressionAST) throws -> Double {
        switch ast {
        case .number(let val):
            return val

        case .constant(let name):
            switch name.lowercased() {
            case "pi": return Double.pi
            case "e": return 2.71828182845904523536
            case "tau": return 6.28318530717958647692
            default:
                throw MathEvaluatorError.unknownConstant(name)
            }

        case .unary(let op, let operand):
            let val = try evaluate(operand)
            switch op {
            case .plus: return +val
            case .minus: return -val
            }

        case .binary(let op, let left, let right):
            let lVal = try evaluate(left)
            let rVal = try evaluate(right)

            switch op {
            case .add:
                return lVal + rVal
            case .subtract:
                return lVal - rVal
            case .multiply:
                return lVal * rVal
            case .divide:
                guard rVal != 0 else { throw MathEvaluatorError.divisionByZero }
                return lVal / rVal
            case .modulo:
                guard rVal != 0 else { throw MathEvaluatorError.moduloByZero }
                return lVal.truncatingRemainder(dividingBy: rVal)
            case .power:
                return pow(lVal, rVal)
            }

        case .function(let name, let args):
            let evaluatedArgs = try args.map { try evaluate($0) }
            return try evaluateFunction(name: name.lowercased(), args: evaluatedArgs)
        }
    }

    private static func evaluateFunction(name: String, args: [Double]) throws -> Double {
        switch name {
        case "sqrt":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            guard args[0] >= 0 else { throw MathEvaluatorError.domainError("sqrt of negative number") }
            return sqrt(args[0])

        case "cbrt":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return cbrt(args[0])

        case "abs", "fabs":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return abs(args[0])

        case "sin":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return sin(args[0])

        case "cos":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return cos(args[0])

        case "tan":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return tan(args[0])

        case "asin":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            guard args[0] >= -1.0 && args[0] <= 1.0 else { throw MathEvaluatorError.domainError("asin input must be between -1 and 1") }
            return asin(args[0])

        case "acos":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            guard args[0] >= -1.0 && args[0] <= 1.0 else { throw MathEvaluatorError.domainError("acos input must be between -1 and 1") }
            return acos(args[0])

        case "atan":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return atan(args[0])

        case "log", "ln":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            guard args[0] > 0 else { throw MathEvaluatorError.domainError("log input must be > 0") }
            return log(args[0])

        case "log10":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            guard args[0] > 0 else { throw MathEvaluatorError.domainError("log10 input must be > 0") }
            return log10(args[0])

        case "log2":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            guard args[0] > 0 else { throw MathEvaluatorError.domainError("log2 input must be > 0") }
            return log2(args[0])

        case "exp":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return exp(args[0])

        case "floor":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return floor(args[0])

        case "ceil":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return ceil(args[0])

        case "round":
            guard args.count == 1 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: args.count) }
            return round(args[0])

        case "pow":
            guard args.count == 2 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 2, got: args.count) }
            return pow(args[0], args[1])

        case "atan2":
            guard args.count == 2 else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 2, got: args.count) }
            return atan2(args[0], args[1])

        case "min":
            guard !args.isEmpty else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: 0) }
            return args.min()!

        case "max":
            guard !args.isEmpty else { throw MathEvaluatorError.invalidArgumentCount(funcName: name, expected: 1, got: 0) }
            return args.max()!

        default:
            throw MathEvaluatorError.unknownFunction(name)
        }
    }

    public static func formatResult(_ val: Double) -> String {
        if val.isNaN || val.isInfinite {
            return "Error"
        }
        if abs(val) < 1e15 && abs(val - round(val)) < 1e-9 {
            return "\(Int64(round(val)))"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumSignificantDigits = 10
        formatter.usesGroupingSeparator = false
        if let str = formatter.string(from: NSNumber(value: val)) {
            return str
        }
        return String(format: "%.10g", val)
    }
}
