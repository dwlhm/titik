import Testing
import TitikParser
import TitikPlugins
import TitikSearch

@Suite("MathEvaluator Tests")
struct MathEvaluatorTests {
    let parser = CommandParser()

    func eval(_ expr: String) throws -> Double {
        let ast = parser.parse("= " + expr)
        guard case .expression(let mathAST) = ast else {
            throw MathEvaluatorError.domainError("Failed to parse math expression")
        }
        return try MathEvaluator.evaluate(mathAST)
    }

    @Test("Basic arithmetic precedence")
    func testBasicArithmetic() throws {
        #expect(try eval("2 + 3 * 4") == 14.0)
        #expect(try eval("(2 + 3) * 4") == 20.0)
        #expect(try eval("100 / 4 - 5") == 20.0)
        #expect(try eval("10 % 3") == 1.0)
    }

    @Test("Powers and unary operators")
    func testPowersAndUnary() throws {
        #expect(try eval("2 ^ 3") == 8.0)
        #expect(try eval("-5 + 10") == 5.0)
        #expect(try eval("2 ^ 2 ^ 3") == 256.0) // Right-associative: 2^(2^3) = 2^8 = 256
    }

    @Test("Mathematical constants")
    func testConstants() throws {
        #expect(abs(try eval("pi") - Double.pi) < 1e-6)
        #expect(abs(try eval("e") - 2.718281828459) < 1e-6)
        #expect(abs(try eval("tau") - 6.283185307179) < 1e-6)
    }

    @Test("Mathematical functions")
    func testFunctions() throws {
        #expect(try eval("sqrt(144)") == 12.0)
        #expect(try eval("abs(-42)") == 42.0)
        #expect(try eval("min(10, 20)") == 10.0)
        #expect(try eval("max(10, 20)") == 20.0)
        #expect(try eval("floor(3.9)") == 3.0)
        #expect(try eval("ceil(3.1)") == 4.0)
        #expect(try eval("round(3.5)") == 4.0)
    }

    @Test("Division by zero error")
    func testDivisionByZero() {
        #expect(throws: MathEvaluatorError.divisionByZero) {
            _ = try eval("10 / 0")
        }
    }
}
