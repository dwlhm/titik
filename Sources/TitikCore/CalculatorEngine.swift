import Foundation
@preconcurrency import Expression

private typealias MathExpression = NumericExpression

public struct CalculationResult: Sendable, Equatable {
    public let title: String        // e.g. "100", "52.83 gallons", "0xFF = 255"
    public let subtitle: String     // e.g. "25 * 4", "Dec: 255 | Bin: 0b11111111"
    public let copyValue: String    // The value to copy to pasteboard

    public init(title: String, subtitle: String, copyValue: String) {
        self.title = title
        self.subtitle = subtitle
        self.copyValue = copyValue
    }
}

public enum CalculatorEngine {
    // MARK: - Primary Evaluation API

    public static func evaluate(_ query: String) -> CalculationResult? {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("!calc") {
            trimmed = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("=") {
            trimmed = trimmed.dropFirst(1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }

        // 1. Physical & Digital Unit Conversions
        if let result = evaluateUnitConversion(trimmed) {
            return result
        }

        // 2. Programmer Base Conversions
        if let result = evaluateBaseConversion(trimmed) {
            return result
        }

        // 3. Math & Percentage Expressions
        if let result = evaluateMathExpression(trimmed) {
            return result
        }

        return nil
    }

    // MARK: - Unit Conversions

    private enum UnitCategory: Sendable {
        case length
        case mass
        case temperature
        case informationStorage
        case speed
        case duration
        case volume
    }

    private struct UnitDefinition: @unchecked Sendable {
        let category: UnitCategory
        let dimension: Dimension
        let defaultDisplay: String
    }

    private static let durationDaysUnit = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86400))

    private static let unitRegistry: [String: UnitDefinition] = {
        var dict: [String: UnitDefinition] = [:]

        // UnitLength: km, m, cm, mm, mi / miles, yd / yards, ft / feet, in / inches
        let lengthUnits: [(keys: [String], unit: UnitLength, display: String)] = [
            (["km", "kilometer", "kilometers", "kilometre", "kilometres"], .kilometers, "km"),
            (["m", "meter", "meters", "metre", "metres"], .meters, "m"),
            (["cm", "centimeter", "centimeters", "centimetre", "centimetres"], .centimeters, "cm"),
            (["mm", "millimeter", "millimeters", "millimetre", "millimetres"], .millimeters, "mm"),
            (["mi", "mile", "miles"], .miles, "miles"),
            (["yd", "yard", "yards"], .yards, "yards"),
            (["ft", "foot", "feet"], .feet, "feet"),
            (["in", "inch", "inches"], .inches, "inches")
        ]
        for item in lengthUnits {
            let def = UnitDefinition(category: .length, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        // UnitMass: kg, g, mg, lbs / pounds, oz / ounces
        let massUnits: [(keys: [String], unit: UnitMass, display: String)] = [
            (["kg", "kilogram", "kilograms"], .kilograms, "kg"),
            (["g", "gram", "grams"], .grams, "g"),
            (["mg", "milligram", "milligrams"], .milligrams, "mg"),
            (["lb", "lbs", "pound", "pounds"], .pounds, "pounds"),
            (["oz", "ounce", "ounces"], .ounces, "ounces")
        ]
        for item in massUnits {
            let def = UnitDefinition(category: .mass, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        // UnitTemperature: c / celsius, f / fahrenheit, k / kelvin
        let tempUnits: [(keys: [String], unit: UnitTemperature, display: String)] = [
            (["c", "°c", "celsius"], .celsius, "celsius"),
            (["f", "°f", "fahrenheit"], .fahrenheit, "fahrenheit"),
            (["k", "kelvin"], .kelvin, "kelvin")
        ]
        for item in tempUnits {
            let def = UnitDefinition(category: .temperature, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        // UnitInformationStorage: b / bytes, kb, mb, gb, tb
        let storageUnits: [(keys: [String], unit: UnitInformationStorage, display: String)] = [
            (["b", "byte", "bytes"], .bytes, "bytes"),
            (["kb", "kilobyte", "kilobytes"], .kilobytes, "KB"),
            (["mb", "megabyte", "megabytes"], .megabytes, "MB"),
            (["gb", "gigabyte", "gigabytes"], .gigabytes, "GB"),
            (["tb", "terabyte", "terabytes"], .terabytes, "TB")
        ]
        for item in storageUnits {
            let def = UnitDefinition(category: .informationStorage, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        // UnitSpeed: kmh / km/h, mph, ms / m/s
        let speedUnits: [(keys: [String], unit: UnitSpeed, display: String)] = [
            (["kmh", "km/h", "kph"], .kilometersPerHour, "km/h"),
            (["mph"], .milesPerHour, "mph"),
            (["ms", "m/s"], .metersPerSecond, "m/s")
        ]
        for item in speedUnits {
            let def = UnitDefinition(category: .speed, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        // UnitDuration: s / seconds, min / minutes, h / hours, d / days
        let durationUnits: [(keys: [String], unit: UnitDuration, display: String)] = [
            (["s", "sec", "secs", "second", "seconds"], .seconds, "seconds"),
            (["min", "mins", "minute", "minutes"], .minutes, "minutes"),
            (["h", "hr", "hrs", "hour", "hours"], .hours, "hours"),
            (["d", "day", "days"], durationDaysUnit, "days")
        ]
        for item in durationUnits {
            let def = UnitDefinition(category: .duration, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        // UnitVolume: gal / gallons, l / liters, ml
        let volumeUnits: [(keys: [String], unit: UnitVolume, display: String)] = [
            (["gal", "gallon", "gallons"], .gallons, "gallons"),
            (["l", "liter", "liters", "litre", "litres"], .liters, "liters"),
            (["ml", "milliliter", "milliliters", "millilitre", "millilitres"], .milliliters, "ml"),
            (["pt", "pint", "pints"], .pints, "pints"),
            (["cup", "cups"], .cups, "cups"),
            (["floz", "fluidounce", "fluidounces"], .fluidOunces, "fl oz")
        ]
        for item in volumeUnits {
            let def = UnitDefinition(category: .volume, dimension: item.unit, defaultDisplay: item.display)
            for key in item.keys { dict[key.lowercased()] = def }
        }

        return dict
    }()

    private static func evaluateUnitConversion(_ query: String) -> CalculationResult? {
        let pattern = #"^([+-]?\d+(?:\.\d+)?)\s*([a-zA-Z/°]+)\s+(?:to|in|as)\s+([a-zA-Z/°]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, range: range), match.numberOfRanges == 4 else {
            return nil
        }

        guard let valRange = Range(match.range(at: 1), in: query),
              let unit1Range = Range(match.range(at: 2), in: query),
              let unit2Range = Range(match.range(at: 3), in: query) else {
            return nil
        }

        let valStr = String(query[valRange])
        guard let value = Double(valStr) else { return nil }

        let unit1Str = String(query[unit1Range]).lowercased()
        let unit2Str = String(query[unit2Range]).lowercased()

        guard let def1 = unitRegistry[unit1Str],
              let def2 = unitRegistry[unit2Str] else {
            return nil
        }

        guard def1.category == def2.category else {
            return nil
        }

        let convertedVal: Double
        switch def1.category {
        case .length:
            guard let u1 = def1.dimension as? UnitLength, let u2 = def2.dimension as? UnitLength else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        case .mass:
            guard let u1 = def1.dimension as? UnitMass, let u2 = def2.dimension as? UnitMass else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        case .temperature:
            guard let u1 = def1.dimension as? UnitTemperature, let u2 = def2.dimension as? UnitTemperature else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        case .informationStorage:
            guard let u1 = def1.dimension as? UnitInformationStorage, let u2 = def2.dimension as? UnitInformationStorage else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        case .speed:
            guard let u1 = def1.dimension as? UnitSpeed, let u2 = def2.dimension as? UnitSpeed else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        case .duration:
            guard let u1 = def1.dimension as? UnitDuration, let u2 = def2.dimension as? UnitDuration else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        case .volume:
            guard let u1 = def1.dimension as? UnitVolume, let u2 = def2.dimension as? UnitVolume else { return nil }
            let m = Measurement(value: value, unit: u1)
            convertedVal = m.converted(to: u2).value
        }

        let formattedVal = formatUnitNumber(convertedVal)
        let rawUnit2 = String(query[unit2Range])
        let title = "\(formattedVal) \(rawUnit2)"

        return CalculationResult(
            title: title,
            subtitle: query,
            copyValue: title
        )
    }

    // MARK: - Programmer Base Conversions

    private enum ProgrammerBase {
        case hex
        case dec
        case bin
        case oct

        static func from(_ str: String) -> ProgrammerBase? {
            switch str.lowercased() {
            case "hex", "hexadecimal", "base16", "16": return .hex
            case "dec", "decimal", "base10", "10": return .dec
            case "bin", "binary", "base2", "2": return .bin
            case "oct", "octal", "base8", "8": return .oct
            default: return nil
            }
        }
    }

    private static func evaluateBaseConversion(_ query: String) -> CalculationResult? {
        // Natural queries: <val> in/to/as <base>
        let convPattern = #"^([+-]?(?:0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|\d+))\s+(?:in|to|as)\s+([a-zA-Z0-9]+)$"#
        if let regex = try? NSRegularExpression(pattern: convPattern, options: .caseInsensitive) {
            let range = NSRange(query.startIndex..<query.endIndex, in: query)
            if let match = regex.firstMatch(in: query, range: range), match.numberOfRanges == 3,
               let valRange = Range(match.range(at: 1), in: query),
               let baseRange = Range(match.range(at: 2), in: query) {
                let valStr = String(query[valRange])
                let targetBaseStr = String(query[baseRange])
                guard let targetBase = ProgrammerBase.from(targetBaseStr) else {
                    return nil
                }
                return convertBaseValue(valStr, targetBase: targetBase)
            }
        }

        // Standalone prefixed numbers: 0x..., 0b..., 0o...
        let standalonePattern = #"^([+-]?(?:0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+))$"#
        if let regex = try? NSRegularExpression(pattern: standalonePattern, options: .caseInsensitive) {
            let range = NSRange(query.startIndex..<query.endIndex, in: query)
            if let match = regex.firstMatch(in: query, range: range), match.numberOfRanges == 2,
               let valRange = Range(match.range(at: 1), in: query) {
                let valStr = String(query[valRange])
                return convertBaseValue(valStr, targetBase: .dec)
            }
        }

        return nil
    }

    private static func convertBaseValue(_ valStr: String, targetBase: ProgrammerBase) -> CalculationResult? {
        let lower = valStr.lowercased()
        let isNegative = lower.hasPrefix("-")
        let cleanStr = isNegative ? String(lower.dropFirst()) : lower

        let sourceBase: ProgrammerBase
        let parsedVal: UInt64?

        if cleanStr.hasPrefix("0x") {
            sourceBase = .hex
            let hexPart = String(cleanStr.dropFirst(2))
            parsedVal = UInt64(hexPart, radix: 16)
        } else if cleanStr.hasPrefix("0b") {
            sourceBase = .bin
            let binPart = String(cleanStr.dropFirst(2))
            parsedVal = UInt64(binPart, radix: 2)
        } else if cleanStr.hasPrefix("0o") {
            sourceBase = .oct
            let octPart = String(cleanStr.dropFirst(2))
            parsedVal = UInt64(octPart, radix: 8)
        } else {
            sourceBase = .dec
            parsedVal = UInt64(cleanStr, radix: 10)
        }

        guard let value = parsedVal else { return nil }

        let sign = isNegative ? "-" : ""
        let hexRepr = "\(sign)0x\(String(value, radix: 16, uppercase: true))"
        let decRepr = "\(sign)\(String(value, radix: 10))"
        let binRepr = "\(sign)0b\(String(value, radix: 2))"

        let targetRepr: String
        switch targetBase {
        case .hex: targetRepr = hexRepr
        case .dec: targetRepr = decRepr
        case .bin: targetRepr = binRepr
        case .oct: targetRepr = "\(sign)0o\(String(value, radix: 8))"
        }

        // Labeled representations in subtitle: (Hex, Dec, Bin)
        // Excludes the source representation
        var parts: [String] = []
        if sourceBase != .hex {
            parts.append("Hex: \(hexRepr)")
        }
        if sourceBase != .dec {
            parts.append("Dec: \(decRepr)")
        }
        if sourceBase != .bin {
            parts.append("Bin: \(binRepr)")
        }

        let subtitle = parts.joined(separator: " | ")
        let title = "\(valStr) = \(targetRepr)"

        return CalculationResult(
            title: title,
            subtitle: subtitle,
            copyValue: targetRepr
        )
    }

    // MARK: - Math & Percentage Expressions

    private static func makeMathSymbols() -> [MathExpression.Symbol: MathExpression.SymbolEvaluator] {
        var symbols: [MathExpression.Symbol: MathExpression.SymbolEvaluator] = [:]

        // Exponentiation operator ^
        symbols[.infix("^")] = { args in pow(args[0], args[1]) }

        // Division by zero guard
        symbols[.infix("/")] = { args in
            guard args[1] != 0 else { throw MathExpression.Error.message("Division by zero") }
            return args[0] / args[1]
        }

        // Modulo by zero guard
        symbols[.infix("%")] = { args in
            guard args[1] != 0 else { throw MathExpression.Error.message("Modulo by zero") }
            return fmod(args[0], args[1])
        }

        symbols[.infix("mod")] = { args in
            guard args[1] != 0 else { throw MathExpression.Error.message("Modulo by zero") }
            return fmod(args[0], args[1])
        }

        // Additional functions
        symbols[.function("log10", arity: 1)] = { args in
            guard args[0] > 0 else { throw MathExpression.Error.message("Domain error") }
            return Darwin.log10(args[0])
        }
        symbols[.function("log2", arity: 1)] = { args in
            guard args[0] > 0 else { throw MathExpression.Error.message("Domain error") }
            return Darwin.log2(args[0])
        }
        symbols[.function("ln", arity: 1)] = { args in
            guard args[0] > 0 else { throw MathExpression.Error.message("Domain error") }
            return Darwin.log(args[0])
        }
        symbols[.function("cbrt", arity: 1)] = { args in
            Darwin.cbrt(args[0])
        }
        symbols[.function("exp", arity: 1)] = { args in
            Darwin.exp(args[0])
        }

        return symbols
    }

    private static let mathConstants: [String: Double] = [
        "pi": Double.pi,
        "PI": Double.pi,
        "e": Darwin.M_E,
        "E": Darwin.M_E,
        "tau": Double.pi * 2,
        "TAU": Double.pi * 2
    ]

    private static func preprocessMathExpression(_ query: String) -> String {
        var expr = query

        // Replace unicode multiplication / division
        expr = expr.replacingOccurrences(of: "×", with: "*")
        expr = expr.replacingOccurrences(of: "÷", with: "/")

        // Replace percent/percentage word with %
        if let percentWordRegex = try? NSRegularExpression(pattern: #"\b(?:percent|percentage)\b"#, options: .caseInsensitive) {
            expr = percentWordRegex.stringByReplacingMatches(
                in: expr,
                range: NSRange(expr.startIndex..<expr.endIndex, in: expr),
                withTemplate: "%"
            )
        }

        // 1. Percentage 'of': e.g. "15% of 850" -> "15 * 0.01 * 850"
        if let ofRegex = try? NSRegularExpression(pattern: #"%\s*of\s+"#, options: .caseInsensitive) {
            expr = ofRegex.stringByReplacingMatches(
                in: expr,
                range: NSRange(expr.startIndex..<expr.endIndex, in: expr),
                withTemplate: " * 0.01 * "
            )
        }

        // 2. Percentage addition/subtraction: e.g. "1200 - 20%" -> "(1200 - (1200 * (20 / 100)))", "50 + 10%" -> "(50 + (50 * (10 / 100)))"
        let addSubPattern = #"(\d+(?:\.\d+)?)\s*([\+\-])\s*(\d+(?:\.\d+)?)\s*%"#
        if let addSubRegex = try? NSRegularExpression(pattern: addSubPattern, options: .caseInsensitive) {
            expr = addSubRegex.stringByReplacingMatches(
                in: expr,
                range: NSRange(expr.startIndex..<expr.endIndex, in: expr),
                withTemplate: "($1 $2 ($1 * ($3 / 100)))"
            )
        }

        // 3. Standalone percentage: e.g. "50%" -> "(50 / 100)"
        let standalonePctPattern = #"(\d+(?:\.\d+)?)\s*%"#
        if let standalonePctRegex = try? NSRegularExpression(pattern: standalonePctPattern, options: .caseInsensitive) {
            expr = standalonePctRegex.stringByReplacingMatches(
                in: expr,
                range: NSRange(expr.startIndex..<expr.endIndex, in: expr),
                withTemplate: "($1 / 100)"
            )
        }

        return expr
    }

    private static func evaluateMathExpression(_ query: String) -> CalculationResult? {
        let preprocessed = preprocessMathExpression(query)
        do {
            let expr = MathExpression(
                preprocessed,
                constants: mathConstants,
                symbols: makeMathSymbols()
            )
            var val = try expr.evaluate()
            guard !val.isNaN && !val.isInfinite else { return nil }

            // Round small floating point inaccuracies near zero, e.g. sin(pi)
            if abs(val) < 1e-12 {
                val = 0
            }

            let formatted = formatNumber(val)
            return CalculationResult(
                title: formatted,
                subtitle: query,
                copyValue: formatted
            )
        } catch {
            return nil
        }
    }

    // MARK: - Formatting Helpers

    private static func formatNumber(_ val: Double) -> String {
        if val.isNaN || val.isInfinite {
            return ""
        }
        if abs(val) < 1e15 && abs(val - round(val)) < 1e-9 {
            return "\(Int64(round(val)))"
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumSignificantDigits = 10
        formatter.usesGroupingSeparator = false
        if let str = formatter.string(from: NSNumber(value: val)) {
            return str
        }
        return String(format: "%.10g", val)
    }

    private static func formatUnitNumber(_ val: Double) -> String {
        if val.isNaN || val.isInfinite {
            return ""
        }
        if abs(val) < 1e15 && abs(val - round(val)) < 1e-9 {
            return "\(Int64(round(val)))"
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        if abs(val) < 0.01 && abs(val) > 0 {
            formatter.maximumFractionDigits = 6
        } else {
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: val)) ?? String(format: "%.2f", val)
    }
}
