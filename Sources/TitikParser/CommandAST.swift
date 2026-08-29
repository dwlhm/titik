import Foundation

public enum MathUnaryOp: String, Equatable, Sendable {
    case plus = "+"
    case minus = "-"
}

public enum MathBinaryOp: String, Equatable, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case power = "^"
}

public indirect enum MathExpressionAST: Equatable, Sendable {
    case number(Double)
    case constant(String)
    case unary(op: MathUnaryOp, operand: MathExpressionAST)
    case binary(op: MathBinaryOp, left: MathExpressionAST, right: MathExpressionAST)
    case function(name: String, args: [MathExpressionAST])
}

public enum CommandAST: Equatable, Sendable {
    case empty
    case expression(MathExpressionAST)
    case command(name: String, args: [String], flags: [String: String])
    case bangSuggestion(prefix: String)
    case raw(query: String)
}
