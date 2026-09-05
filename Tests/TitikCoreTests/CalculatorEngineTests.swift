import Testing
import TitikCore

@Suite("CalculatorEngine Tests")
struct CalculatorEngineTests {
    // MARK: - Arithmetic & Standard Math

    @Test("Basic arithmetic operations")
    func testBasicArithmetic() {
        let resMul = CalculatorEngine.evaluate("25 * 4")
        #expect(resMul != nil)
        #expect(resMul?.title == "100")
        #expect(resMul?.subtitle == "25 * 4")
        #expect(resMul?.copyValue == "100")

        let resAdd = CalculatorEngine.evaluate("12 + 34")
        #expect(resAdd?.title == "46")
        #expect(resAdd?.copyValue == "46")

        let resSub = CalculatorEngine.evaluate("100 - 45.5")
        #expect(resSub?.title == "54.5")
        #expect(resSub?.copyValue == "54.5")

        let resDiv = CalculatorEngine.evaluate("100 / 8")
        #expect(resDiv?.title == "12.5")
        #expect(resDiv?.copyValue == "12.5")

        let resPrecedence = CalculatorEngine.evaluate("10 + 20 * 3")
        #expect(resPrecedence?.title == "70")

        let resParens = CalculatorEngine.evaluate("(10 + 20) * 3")
        #expect(resParens?.title == "90")
    }

    @Test("Exponentiation and unicode math symbols")
    func testExponentiationAndUnicode() {
        let resExp = CalculatorEngine.evaluate("2^8")
        #expect(resExp != nil)
        #expect(resExp?.title == "256")
        #expect(resExp?.copyValue == "256")

        let resUnicodeMul = CalculatorEngine.evaluate("25 × 4")
        #expect(resUnicodeMul?.title == "100")

        let resUnicodeDiv = CalculatorEngine.evaluate("100 ÷ 4")
        #expect(resUnicodeDiv?.title == "25")

        let resMod = CalculatorEngine.evaluate("10 mod 3")
        #expect(resMod?.title == "1")
    }

    @Test("Trigonometry and advanced math functions")
    func testAdvancedMath() {
        let resSin = CalculatorEngine.evaluate("sin(pi/2)")
        #expect(resSin != nil)
        #expect(resSin?.title == "1")
        #expect(resSin?.copyValue == "1")

        let resSinPi = CalculatorEngine.evaluate("sin(pi)")
        #expect(resSinPi?.title == "0")

        let resCos = CalculatorEngine.evaluate("cos(0)")
        #expect(resCos?.title == "1")

        let resSqrt = CalculatorEngine.evaluate("sqrt(144)")
        #expect(resSqrt != nil)
        #expect(resSqrt?.title == "12")
        #expect(resSqrt?.copyValue == "12")

        let resLog = CalculatorEngine.evaluate("log(10)")
        #expect(resLog != nil)
        #expect(resLog?.title.hasPrefix("2.302585") == true)

        let resLog10 = CalculatorEngine.evaluate("log10(100)")
        #expect(resLog10?.title == "2")

        let resCbrt = CalculatorEngine.evaluate("cbrt(27)")
        #expect(resCbrt?.title == "3")
    }

    // MARK: - Percentages

    @Test("Percentage expressions")
    func testPercentages() {
        // Pattern 1: X% of Y
        let resOf800 = CalculatorEngine.evaluate("15% of 800")
        #expect(resOf800 != nil)
        #expect(resOf800?.title == "120")
        #expect(resOf800?.copyValue == "120")

        let resOf850 = CalculatorEngine.evaluate("15% of 850")
        #expect(resOf850 != nil)
        #expect(resOf850?.title == "127.5")
        #expect(resOf850?.copyValue == "127.5")

        // Pattern 2: Percentage addition / subtraction
        let resSubPct = CalculatorEngine.evaluate("1200 - 20%")
        #expect(resSubPct != nil)
        #expect(resSubPct?.title == "960")
        #expect(resSubPct?.copyValue == "960")

        let resAddPct = CalculatorEngine.evaluate("50 + 10%")
        #expect(resAddPct != nil)
        #expect(resAddPct?.title == "55")
        #expect(resAddPct?.copyValue == "55")

        // Pattern 3: Standalone percentage
        let resStandalone = CalculatorEngine.evaluate("50%")
        #expect(resStandalone?.title == "0.5")

        let resMulPct = CalculatorEngine.evaluate("200 * 15%")
        #expect(resMulPct?.title == "30")
    }

    // MARK: - Programmer Base Conversions

    @Test("Programmer base conversions")
    func testProgrammerBases() {
        // Hex to dec
        let resHexToDec = CalculatorEngine.evaluate("0xFF to dec")
        #expect(resHexToDec != nil)
        #expect(resHexToDec?.title == "0xFF = 255")
        #expect(resHexToDec?.subtitle == "Dec: 255 | Bin: 0b11111111")
        #expect(resHexToDec?.copyValue == "255")

        let resHexInDec = CalculatorEngine.evaluate("0xFF in dec")
        #expect(resHexInDec?.title == "0xFF = 255")
        #expect(resHexInDec?.copyValue == "255")

        // Dec to bin
        let resDecToBin = CalculatorEngine.evaluate("255 in bin")
        #expect(resDecToBin != nil)
        #expect(resDecToBin?.title == "255 = 0b11111111")
        #expect(resDecToBin?.subtitle == "Hex: 0xFF | Bin: 0b11111111")
        #expect(resDecToBin?.copyValue == "0b11111111")

        // Bin to hex
        let resBinToHex = CalculatorEngine.evaluate("0b1011 in hex")
        #expect(resBinToHex != nil)
        #expect(resBinToHex?.title == "0b1011 = 0xB")
        #expect(resBinToHex?.subtitle == "Hex: 0xB | Dec: 11")
        #expect(resBinToHex?.copyValue == "0xB")

        // Hex to bin
        let resHexToBin = CalculatorEngine.evaluate("0xFF to bin")
        #expect(resHexToBin != nil)
        #expect(resHexToBin?.title == "0xFF = 0b11111111")
        #expect(resHexToBin?.copyValue == "0b11111111")

        // Standalone hex
        let resStandaloneHex = CalculatorEngine.evaluate("0xFF")
        #expect(resStandaloneHex?.title == "0xFF = 255")
        #expect(resStandaloneHex?.copyValue == "255")

        // Standalone binary
        let resStandaloneBin = CalculatorEngine.evaluate("0b1011")
        #expect(resStandaloneBin?.title == "0b1011 = 11")
        #expect(resStandaloneBin?.copyValue == "11")
    }

    // MARK: - Unit Conversions

    @Test("Physical and digital unit conversions")
    func testUnitConversions() {
        // Length: km to miles
        let resKm = CalculatorEngine.evaluate("50 km to miles")
        #expect(resKm != nil)
        #expect(resKm?.title == "31.07 miles")
        #expect(resKm?.copyValue == "31.07 miles")

        let resMeters = CalculatorEngine.evaluate("1000 m to km")
        #expect(resMeters?.title == "1 km")

        // Volume: liters to gallons
        let resVolume = CalculatorEngine.evaluate("200 liters in gallons")
        #expect(resVolume != nil)
        #expect(resVolume?.title == "52.83 gallons")
        #expect(resVolume?.copyValue == "52.83 gallons")

        // Temperature: celsius / fahrenheit
        let resTempCtoF = CalculatorEngine.evaluate("100 c to f")
        #expect(resTempCtoF?.title == "212 f")

        let resTempFtoC = CalculatorEngine.evaluate("32 f to c")
        #expect(resTempFtoC?.title == "0 c")

        // Mass: kg to lbs
        let resMass = CalculatorEngine.evaluate("1 kg to lbs")
        #expect(resMass != nil)
        #expect(resMass?.title.contains("lbs") == true)

        // Speed: km/h to mph
        let resSpeed = CalculatorEngine.evaluate("100 km/h to mph")
        #expect(resSpeed != nil)
        #expect(resSpeed?.title.contains("mph") == true)

        // Duration: hours to minutes
        let resDuration = CalculatorEngine.evaluate("2 hours to minutes")
        #expect(resDuration?.title == "120 minutes")

        let resDays = CalculatorEngine.evaluate("1 day to hours")
        #expect(resDays?.title == "24 hours")

        // Storage: gb to mb
        let resStorage = CalculatorEngine.evaluate("1 gb to mb")
        #expect(resStorage != nil)
        #expect(resStorage?.title.contains("mb") == true)
    }

    // MARK: - Boundary Conditions

    @Test("Boundary conditions: invalid expressions and malformed queries")
    func testBoundaryConditionsInvalidExpressions() {
        #expect(CalculatorEngine.evaluate("") == nil)
        #expect(CalculatorEngine.evaluate("   ") == nil)
        #expect(CalculatorEngine.evaluate("foo bar") == nil)
        #expect(CalculatorEngine.evaluate("invalid") == nil)
        #expect(CalculatorEngine.evaluate("2 + + 3") == nil)
        #expect(CalculatorEngine.evaluate("sin(") == nil)
        #expect(CalculatorEngine.evaluate("10 +") == nil)
        #expect(CalculatorEngine.evaluate("+ * 5") == nil)
    }

    @Test("Boundary conditions: division and modulo by zero")
    func testBoundaryConditionsDivisionByZero() {
        #expect(CalculatorEngine.evaluate("10 / 0") == nil)
        #expect(CalculatorEngine.evaluate("5 / (2 - 2)") == nil)
        #expect(CalculatorEngine.evaluate("10 % 0") == nil)
        #expect(CalculatorEngine.evaluate("10 mod 0") == nil)
    }

    @Test("Boundary conditions: unknown and incompatible units")
    func testBoundaryConditionsUnits() {
        #expect(CalculatorEngine.evaluate("10 widgets to flubs") == nil)
        #expect(CalculatorEngine.evaluate("50 km to kg") == nil)
        #expect(CalculatorEngine.evaluate("100 f to meters") == nil)
        #expect(CalculatorEngine.evaluate("10 km to") == nil)
    }

    @Test("Boundary conditions: invalid base conversions")
    func testBoundaryConditionsBases() {
        #expect(CalculatorEngine.evaluate("0xZZ to dec") == nil)
        #expect(CalculatorEngine.evaluate("0b102 in hex") == nil)
        #expect(CalculatorEngine.evaluate("255 in base99") == nil)
    }

    @Test("Leading bang or equals prefix compatibility")
    func testPrefixCompatibility() {
        let res1 = CalculatorEngine.evaluate("= 25 * 4")
        #expect(res1?.title == "100")

        let res2 = CalculatorEngine.evaluate("!calc 25 * 4")
        #expect(res2?.title == "100")
    }
}
