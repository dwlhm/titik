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

    @Test("Parse bang commands and suggestions")
    func testBangCommandsAndSuggestions() {
        #expect(parser.parse("!") == .bangSuggestion(prefix: ""))
        #expect(parser.parse("!e") == .bangSuggestion(prefix: "e"))
        #expect(parser.parse("!emoji") == .bangSuggestion(prefix: "emoji"))
        #expect(parser.parse("!e ") == .pluginInvocation(trigger: "e", action: nil, primaryValue: "", flags: [:], booleanFlags: [], rawTail: ""))
        #expect(parser.parse("!emoji ") == .pluginInvocation(trigger: "emoji", action: nil, primaryValue: "", flags: [:], booleanFlags: [], rawTail: ""))
        #expect(parser.parse("!emoji smile") == .pluginInvocation(trigger: "emoji", action: nil, primaryValue: "smile", flags: [:], booleanFlags: [], rawTail: "smile"))
    }

    @Test("Parse note bang command and suggestions (ADR 5)")
    func testNoteBangCommandAndSuggestions() {
        #expect(parser.parse("!note") == .bangSuggestion(prefix: "note"))
        #expect(parser.parse("!notes") == .bangSuggestion(prefix: "notes"))
        #expect(parser.parse("!note ") == .pluginInvocation(trigger: "note", action: nil, primaryValue: "", flags: [:], booleanFlags: [], rawTail: ""))
        #expect(parser.parse("!note my title") == .pluginInvocation(trigger: "note", action: nil, primaryValue: "my title", flags: [:], booleanFlags: [], rawTail: "my title"))
    }

    @Test("Parse delimiter-bounded segment parsing with multi-word values and flags")
    func testDelimiterBoundedSegmentParsing() {
        let ast = parser.parse("!zen open swift docs --profile work --private", knownSubcommands: ["open", "new-tab"])
        if case .pluginInvocation(let trigger, let action, let primaryValue, let flags, let booleanFlags, _) = ast {
            #expect(trigger == "zen")
            #expect(action == "open")
            #expect(primaryValue == "swift docs")
            #expect(flags["profile"] == "work")
            #expect(booleanFlags.contains("private"))
        } else {
            #expect(Bool(false), "Expected .pluginInvocation, got \(ast)")
        }

        let inlineAst = parser.parse("!calc 42 * 1024 --format=hex")
        if case .pluginInvocation(let trigger, let action, let primaryValue, let flags, _, _) = inlineAst {
            #expect(trigger == "calc")
            #expect(action == nil)
            #expect(primaryValue == "42 * 1024")
            #expect(flags["format"] == "hex")
        } else {
            #expect(Bool(false), "Expected .pluginInvocation, got \(inlineAst)")
        }
    }
}
