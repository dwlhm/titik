import Testing
import TitikParser

@Suite("CommandParser Tests")
struct CommandParserTests {
    let parser = CommandParser()

    @Test("Parse empty query")
    func testEmptyQuery() {
        #expect(parser.parse("") == .empty)
        #expect(parser.parse("   \n\t  ") == .empty)
    }

    @Test("Parse prefix commands")
    func testPrefixCommands() {
        let appAst = parser.parse("app:safari")
        if case .command(let name, let args, let flags) = appAst {
            #expect(name == "app")
            #expect(args == ["safari"])
            #expect(flags.isEmpty)
        } else {
            #expect(Bool(false), "Expected .command, got \(appAst)")
        }

        let cmdAst = parser.parse("cmd:lock")
        if case .command(let name, let args, _) = cmdAst {
            #expect(name == "cmd")
            #expect(args == ["lock"])
        } else {
            #expect(Bool(false), "Expected .command, got \(cmdAst)")
        }

        let flaggedAst = parser.parse("app:terminal --tab --profile=Default")
        if case .command(let name, let args, let flags) = flaggedAst {
            #expect(name == "app")
            #expect(args == ["terminal"])
            #expect(flags["tab"] == "true")
            #expect(flags["profile"] == "Default")
        } else {
            #expect(Bool(false), "Expected .command with flags, got \(flaggedAst)")
        }
    }

    @Test("Parse explicit math commands")
    func testExplicitMathCommands() {
        let ast1 = parser.parse("= 25 * 4")
        if case .expression(let expr) = ast1 {
            #expect(expr == .binary(op: .multiply, left: .number(25), right: .number(4)))
        } else {
            #expect(Bool(false), "Expected .expression, got \(ast1)")
        }

        let ast2 = parser.parse("calc sqrt(144)")
        if case .expression(let expr) = ast2 {
            #expect(expr == .function(name: "sqrt", args: [.number(144)]))
        } else {
            #expect(Bool(false), "Expected .expression, got \(ast2)")
        }

        let ast3 = parser.parse("math 2^8")
        if case .expression(let expr) = ast3 {
            #expect(expr == .binary(op: .power, left: .number(2), right: .number(8)))
        } else {
            #expect(Bool(false), "Expected .expression, got \(ast3)")
        }
    }

    @Test("Parse implicit math expressions")
    func testImplicitMathExpressions() {
        let ast = parser.parse("10 + 20 * 3")
        if case .expression(let expr) = ast {
            #expect(
                expr == .binary(
                    op: .add,
                    left: .number(10),
                    right: .binary(op: .multiply, left: .number(20), right: .number(3))
                )
            )
        } else {
            #expect(Bool(false), "Expected .expression, got \(ast)")
        }
    }

    @Test("Fallback to raw query")
    func testRawQueryFallback() {
        let ast = parser.parse("visual studio code")
        #expect(ast == .raw(query: "visual studio code"))
    }
}
