import Foundation

struct CalculatorResult: Equatable, Sendable {
    let value: String
    let detail: String
}

enum Calculator {
    static func evaluate(_ rawQuery: String) -> CalculatorResult? {
        let prepared = prepare(rawQuery)
        guard prepared.isExplicit || looksLikeMath(prepared.expression) else { return nil }

        if let conversion = UnitConverter.convert(prepared.expression) {
            return conversion
        }

        guard var parser = try? ArithmeticParser(prepared.expression),
              let value = try? parser.evaluate(),
              value.isFinite else {
            return nil
        }
        return CalculatorResult(
            value: format(value),
            detail: "Press Return to copy"
        )
    }

    fileprivate static func arithmeticValue(_ expression: String) -> Double? {
        guard var parser = try? ArithmeticParser(expression),
              let value = try? parser.evaluate(),
              value.isFinite,
              let realValue = value.realValue else {
            return nil
        }
        return realValue
    }

    fileprivate static func format(_ value: Double) -> String {
        let normalized = abs(value) < 1e-14 ? 0 : value
        let locale = Locale(identifier: "en_US_POSIX")
        if normalized.rounded() == normalized, abs(normalized) < 1e15 {
            return String(format: "%.0f", locale: locale, normalized)
        }
        return String(format: "%.12g", locale: locale, normalized)
            .replacingOccurrences(of: "e+", with: "e")
    }

    private static func format(_ value: Complex) -> String {
        let real = abs(value.real) < 1e-12 ? 0 : value.real
        let imaginary = abs(value.imaginary) < 1e-12 ? 0 : value.imaginary
        if imaginary == 0 {
            return format(real)
        }

        let imaginaryMagnitude = abs(imaginary)
        let imaginaryText = abs(imaginaryMagnitude - 1) < 1e-12
            ? "i"
            : "\(format(imaginaryMagnitude))i"
        if real == 0 {
            return imaginary < 0 ? "-\(imaginaryText)" : imaginaryText
        }
        let operation = imaginary < 0 ? "−" : "+"
        return "\(format(real)) \(operation) \(imaginaryText)"
    }

    private static func prepare(_ rawQuery: String) -> (expression: String, isExplicit: Bool) {
        var expression = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var explicit = false

        if expression.hasPrefix("=") {
            expression.removeFirst()
            explicit = true
        }

        let prefixes = ["calculate ", "calc ", "what is ", "what's "]
        let lowercase = expression.lowercased()
        if let prefix = prefixes.first(where: { lowercase.hasPrefix($0) }) {
            expression.removeFirst(prefix.count)
            explicit = true
        }

        expression = expression
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "π", with: "pi")
            .replacingOccurrences(of: "τ", with: "tau")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (expression, explicit)
    }

    private static func looksLikeMath(_ expression: String) -> Bool {
        let lowercase = expression.lowercased()
        guard !lowercase.isEmpty else { return false }

        let mathWords = [
            "plus", "minus", "times", "multiplied", "divided", "mod",
            "percent", "sqrt", "cbrt", "sin", "cos", "tan", "log",
            "ln", "abs", "floor", "ceil", "round", "min", "max", "pow",
            "squared", "cubed"
        ]
        if mathWords.contains(where: { lowercase.contains($0) }) {
            return true
        }
        if ["pi", "e", "tau", "i"].contains(lowercase) {
            return true
        }
        if lowercase.range(
            of: #"(?:\d\s*(?:pi|tau|e|i)\b|\b(?:pi|tau|e|i)\s*\d)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if lowercase.range(
            of: #"\b(?:pi|tau|e|i)\b"#,
            options: .regularExpression
        ) != nil,
           lowercase.contains(where: { "+-*/^%=!()√".contains($0) }) {
            return true
        }
        if UnitConverter.looksLikeConversion(lowercase) {
            return true
        }

        guard lowercase.contains(where: \.isNumber) else { return false }
        if lowercase.contains(where: { "+*/^%=!()√".contains($0) }) {
            return true
        }
        return lowercase.range(
            of: #"\d\s*-\s*\d"#,
            options: .regularExpression
        ) != nil
    }
}

private enum ArithmeticError: Error {
    case invalidExpression
    case invalidOperation
}

private struct Complex: Equatable {
    let real: Double
    let imaginary: Double

    init(_ real: Double, _ imaginary: Double = 0) {
        self.real = real
        self.imaginary = imaginary
    }

    static let zero = Complex(0)
    static let one = Complex(1)
    static let i = Complex(0, 1)

    var isFinite: Bool {
        real.isFinite && imaginary.isFinite
    }

    var magnitude: Double {
        Foundation.hypot(real, imaginary)
    }

    var realValue: Double? {
        abs(imaginary) < 1e-12 ? real : nil
    }

    static prefix func - (value: Complex) -> Complex {
        Complex(-value.real, -value.imaginary)
    }

    static func + (left: Complex, right: Complex) -> Complex {
        Complex(left.real + right.real, left.imaginary + right.imaginary)
    }

    static func - (left: Complex, right: Complex) -> Complex {
        Complex(left.real - right.real, left.imaginary - right.imaginary)
    }

    static func * (left: Complex, right: Complex) -> Complex {
        Complex(
            left.real * right.real - left.imaginary * right.imaginary,
            left.real * right.imaginary + left.imaginary * right.real
        )
    }

    static func * (left: Complex, right: Double) -> Complex {
        Complex(left.real * right, left.imaginary * right)
    }

    static func / (left: Complex, right: Complex) -> Complex {
        let denominator = right.real * right.real + right.imaginary * right.imaginary
        return Complex(
            (left.real * right.real + left.imaginary * right.imaginary) / denominator,
            (left.imaginary * right.real - left.real * right.imaginary) / denominator
        )
    }

    static func / (left: Complex, right: Double) -> Complex {
        Complex(left.real / right, left.imaginary / right)
    }

    func exponential() -> Complex {
        let scale = Foundation.exp(real)
        return Complex(scale * Foundation.cos(imaginary), scale * Foundation.sin(imaginary))
    }

    func logarithm() -> Complex {
        Complex(Foundation.log(magnitude), Foundation.atan2(imaginary, real))
    }

    func raised(to exponent: Complex) -> Complex {
        if self == .zero {
            return exponent == .zero ? .one : .zero
        }
        return (exponent * logarithm()).exponential()
    }

    func squareRoot() -> Complex {
        if self == .zero { return .zero }
        let realPart = Foundation.sqrt(max(0, (magnitude + real) / 2))
        let imaginaryMagnitude = Foundation.sqrt(max(0, (magnitude - real) / 2))
        return Complex(
            realPart,
            imaginary < 0 ? -imaginaryMagnitude : imaginaryMagnitude
        )
    }

    func sine() -> Complex {
        Complex(
            Foundation.sin(real) * Foundation.cosh(imaginary),
            Foundation.cos(real) * Foundation.sinh(imaginary)
        )
    }

    func cosine() -> Complex {
        Complex(
            Foundation.cos(real) * Foundation.cosh(imaginary),
            -Foundation.sin(real) * Foundation.sinh(imaginary)
        )
    }

    func hyperbolicSine() -> Complex {
        Complex(
            Foundation.sinh(real) * Foundation.cos(imaginary),
            Foundation.cosh(real) * Foundation.sin(imaginary)
        )
    }

    func hyperbolicCosine() -> Complex {
        Complex(
            Foundation.cosh(real) * Foundation.cos(imaginary),
            Foundation.sinh(real) * Foundation.sin(imaginary)
        )
    }
}

private enum ArithmeticToken: Equatable {
    case number(Double)
    case identifier(String)
    case plus
    case minus
    case multiply
    case divide
    case power
    case modulo
    case leftParenthesis
    case rightParenthesis
    case comma
    case percent
    case factorial
    case degrees
    case squareRoot
    case squared
    case cubed
    case end
}

private struct ArithmeticLexer {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) {
        let withoutGroupingSeparators = expression.replacingOccurrences(
            of: #"(?<=\d),(?=\d{3}(?:\D|$))"#,
            with: "",
            options: .regularExpression
        )
        characters = Array(withoutGroupingSeparators)
    }

    mutating func tokenize() throws -> [ArithmeticToken] {
        var tokens: [ArithmeticToken] = []
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isNumber || character == "." {
                tokens.append(.number(try readNumber()))
                continue
            }
            if character.isLetter {
                if let token = readWord() {
                    tokens.append(token)
                }
                continue
            }
            index += 1
            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*":
                if index < characters.count, characters[index] == "*" {
                    index += 1
                    tokens.append(.power)
                } else {
                    tokens.append(.multiply)
                }
            case "/": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "(": tokens.append(.leftParenthesis)
            case ")": tokens.append(.rightParenthesis)
            case ",": tokens.append(.comma)
            case "%": tokens.append(.percent)
            case "!": tokens.append(.factorial)
            case "°": tokens.append(.degrees)
            case "√": tokens.append(.squareRoot)
            default: throw ArithmeticError.invalidExpression
            }
        }
        tokens.append(.end)
        return tokens
    }

    private mutating func readNumber() throws -> Double {
        let start = index
        var sawDecimal = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                index += 1
            } else if character == ".", !sawDecimal {
                sawDecimal = true
                index += 1
            } else {
                break
            }
        }
        if index < characters.count, characters[index].lowercased() == "e" {
            index += 1
            if index < characters.count,
               (characters[index] == "+" || characters[index] == "-") {
                index += 1
            }
            let exponentStart = index
            while index < characters.count, characters[index].isNumber {
                index += 1
            }
            guard index > exponentStart else { throw ArithmeticError.invalidExpression }
        }
        let text = String(characters[start..<index])
        guard let value = Double(text) else { throw ArithmeticError.invalidExpression }
        return value
    }

    private mutating func readWord() -> ArithmeticToken? {
        let start = index
        while index < characters.count, characters[index].isLetter || characters[index].isNumber {
            index += 1
        }
        let word = String(characters[start..<index]).lowercased()
        switch word {
        case "plus": return .plus
        case "minus": return .minus
        case "times", "multiplied", "x", "of": return .multiply
        case "divided", "over": return .divide
        case "mod", "modulo": return .modulo
        case "percent": return .percent
        case "degrees", "degree", "deg": return .degrees
        case "squared": return .squared
        case "cubed": return .cubed
        case "by": return nil
        default: return .identifier(word)
        }
    }
}

private struct ArithmeticParser {
    private var tokens: [ArithmeticToken]
    private var index = 0

    init(_ expression: String) throws {
        var lexer = ArithmeticLexer(expression)
        tokens = try lexer.tokenize()
    }

    mutating func evaluate() throws -> Complex {
        let value = try parseExpression()
        guard current == .end, value.isFinite else {
            throw ArithmeticError.invalidExpression
        }
        return value
    }

    private var current: ArithmeticToken {
        tokens[index]
    }

    private mutating func advance() {
        index += 1
    }

    private mutating func parseExpression() throws -> Complex {
        var value = try parseProduct()
        while true {
            switch current {
            case .plus:
                advance()
                value = value + (try parseProduct())
            case .minus:
                advance()
                value = value - (try parseProduct())
            default:
                return value
            }
        }
    }

    private mutating func parseProduct() throws -> Complex {
        var value = try parseUnary()
        while true {
            switch current {
            case .multiply:
                advance()
                value = value * (try parseUnary())
            case .divide:
                advance()
                let divisor = try parseUnary()
                guard divisor.magnitude != 0 else { throw ArithmeticError.invalidOperation }
                value = value / divisor
            case .modulo:
                advance()
                let divisor = try parseUnary()
                guard let left = value.realValue,
                      let right = divisor.realValue,
                      right != 0 else {
                    throw ArithmeticError.invalidOperation
                }
                value = Complex(left.truncatingRemainder(dividingBy: right))
            case .number, .identifier, .leftParenthesis, .squareRoot:
                value = value * (try parseUnary())
            default:
                return value
            }
        }
    }

    private mutating func parseUnary() throws -> Complex {
        switch current {
        case .plus:
            advance()
            return try parseUnary()
        case .minus:
            advance()
            return -(try parseUnary())
        case .squareRoot:
            advance()
            return try parseUnary().squareRoot()
        default:
            return try parsePower()
        }
    }

    private mutating func parsePower() throws -> Complex {
        var value = try parsePostfix()
        if current == .power {
            advance()
            value = value.raised(to: try parseUnary())
        }
        return value
    }

    private mutating func parsePostfix() throws -> Complex {
        var value = try parsePrimary()
        while true {
            switch current {
            case .percent:
                advance()
                value = value / 100
            case .factorial:
                advance()
                guard let real = value.realValue,
                      real >= 0,
                      real <= 170,
                      real.rounded() == real else {
                    throw ArithmeticError.invalidOperation
                }
                let factorial = real == 0
                    ? 1
                    : (1...Int(real)).reduce(1) { $0 * Double($1) }
                value = Complex(factorial)
            case .degrees:
                advance()
                value = value * (Double.pi / 180)
            case .squared:
                advance()
                value = value * value
            case .cubed:
                advance()
                value = value * value * value
            default:
                return value
            }
        }
    }

    private mutating func parsePrimary() throws -> Complex {
        switch current {
        case let .number(value):
            advance()
            return Complex(value)
        case let .identifier(name):
            advance()
            if let constant = constant(named: name) {
                return constant
            }
            guard current == .leftParenthesis else {
                throw ArithmeticError.invalidExpression
            }
            advance()
            var arguments: [Complex] = []
            if current != .rightParenthesis {
                while true {
                    arguments.append(try parseExpression())
                    if current != .comma { break }
                    advance()
                }
            }
            guard current == .rightParenthesis else {
                throw ArithmeticError.invalidExpression
            }
            advance()
            return try apply(function: name, arguments: arguments)
        case .leftParenthesis:
            advance()
            let value = try parseExpression()
            guard current == .rightParenthesis else {
                throw ArithmeticError.invalidExpression
            }
            advance()
            return value
        default:
            throw ArithmeticError.invalidExpression
        }
    }

    private func constant(named name: String) -> Complex? {
        switch name {
        case "pi": Complex(.pi)
        case "tau": Complex(.pi * 2)
        case "e": Complex(M_E)
        case "i": .i
        default: nil
        }
    }

    private func apply(function name: String, arguments: [Complex]) throws -> Complex {
        func one(_ operation: (Complex) -> Complex) throws -> Complex {
            guard arguments.count == 1 else { throw ArithmeticError.invalidExpression }
            return operation(arguments[0])
        }
        func two(_ operation: (Complex, Complex) -> Complex) throws -> Complex {
            guard arguments.count == 2 else { throw ArithmeticError.invalidExpression }
            return operation(arguments[0], arguments[1])
        }
        func oneReal(_ operation: (Double) -> Double) throws -> Complex {
            guard arguments.count == 1, let value = arguments[0].realValue else {
                throw ArithmeticError.invalidOperation
            }
            return Complex(operation(value))
        }
        func twoReal(_ operation: (Double, Double) -> Double) throws -> Complex {
            guard arguments.count == 2,
                  let first = arguments[0].realValue,
                  let second = arguments[1].realValue else {
                throw ArithmeticError.invalidOperation
            }
            return Complex(operation(first, second))
        }

        let value: Complex
        switch name {
        case "sqrt": value = try one { $0.squareRoot() }
        case "cbrt":
            value = try one {
                if let real = $0.realValue {
                    return Complex(Foundation.cbrt(real))
                }
                return $0.raised(to: Complex(1 / 3))
            }
        case "abs": value = try one { Complex($0.magnitude) }
        case "sin": value = try one { $0.sine() }
        case "cos": value = try one { $0.cosine() }
        case "tan": value = try one { $0.sine() / $0.cosine() }
        case "asin":
            value = try one {
                -.i * ((.i * $0) + (.one - ($0 * $0)).squareRoot()).logarithm()
            }
        case "acos":
            value = try one {
                Complex(.pi / 2) - (
                    -.i * ((.i * $0) + (.one - ($0 * $0)).squareRoot()).logarithm()
                )
            }
        case "atan":
            value = try one {
                (.i / 2) * ((.one - (.i * $0)).logarithm()
                    - (.one + (.i * $0)).logarithm())
            }
        case "sinh": value = try one { $0.hyperbolicSine() }
        case "cosh": value = try one { $0.hyperbolicCosine() }
        case "tanh": value = try one { $0.hyperbolicSine() / $0.hyperbolicCosine() }
        case "ln": value = try one { $0.logarithm() }
        case "log": value = try one { $0.logarithm() / Foundation.log(10) }
        case "log2": value = try one { $0.logarithm() / Foundation.log(2) }
        case "exp": value = try one { $0.exponential() }
        case "floor": value = try oneReal(Foundation.floor)
        case "ceil": value = try oneReal(Foundation.ceil)
        case "round": value = try oneReal { $0.rounded() }
        case "min":
            let realArguments = arguments.compactMap(\.realValue)
            guard !arguments.isEmpty, realArguments.count == arguments.count else {
                throw ArithmeticError.invalidOperation
            }
            value = Complex(realArguments.min()!)
        case "max":
            let realArguments = arguments.compactMap(\.realValue)
            guard !arguments.isEmpty, realArguments.count == arguments.count else {
                throw ArithmeticError.invalidOperation
            }
            value = Complex(realArguments.max()!)
        case "pow": value = try two { $0.raised(to: $1) }
        case "hypot": value = try twoReal(Foundation.hypot)
        default: throw ArithmeticError.invalidExpression
        }
        guard value.isFinite else { throw ArithmeticError.invalidOperation }
        return value
    }
}

private enum UnitDimension {
    case length
    case area
    case volume
    case mass
    case temperature
    case speed
    case time
    case storage
    case angle
    case energy
    case power
    case pressure
    case frequency
}

private struct UnitDefinition {
    let dimension: UnitDimension
    let symbol: String
    let factor: Double
    let aliases: [String]
    let toBase: ((Double) -> Double)?
    let fromBase: ((Double) -> Double)?

    init(
        _ dimension: UnitDimension,
        _ symbol: String,
        _ factor: Double,
        _ aliases: [String],
        toBase: ((Double) -> Double)? = nil,
        fromBase: ((Double) -> Double)? = nil
    ) {
        self.dimension = dimension
        self.symbol = symbol
        self.factor = factor
        self.aliases = aliases
        self.toBase = toBase
        self.fromBase = fromBase
    }
}

private enum UnitConverter {
    private static let units: [UnitDefinition] = [
        UnitDefinition(.length, "mm", 0.001, ["mm", "millimeter", "millimeters", "millimetre", "millimetres"]),
        UnitDefinition(.length, "µm", 0.000001, ["um", "µm", "micrometer", "micrometers", "micrometre", "micrometres"]),
        UnitDefinition(.length, "cm", 0.01, ["cm", "centimeter", "centimeters", "centimetre", "centimetres"]),
        UnitDefinition(.length, "m", 1, ["m", "meter", "meters", "metre", "metres"]),
        UnitDefinition(.length, "km", 1_000, ["km", "kilometer", "kilometers", "kilometre", "kilometres"]),
        UnitDefinition(.length, "in", 0.0254, ["in", "inch", "inches", "\""]),
        UnitDefinition(.length, "ft", 0.3048, ["ft", "foot", "feet", "'"]),
        UnitDefinition(.length, "yd", 0.9144, ["yd", "yard", "yards"]),
        UnitDefinition(.length, "mi", 1_609.344, ["mi", "mile", "miles"]),
        UnitDefinition(.length, "nmi", 1_852, ["nmi", "nautical mile", "nautical miles"]),

        UnitDefinition(.area, "mm²", 0.000001, ["mm2", "mm²", "square millimeter", "square millimeters"]),
        UnitDefinition(.area, "cm²", 0.0001, ["cm2", "cm²", "square centimeter", "square centimeters"]),
        UnitDefinition(.area, "m²", 1, ["m2", "m²", "square meter", "square meters"]),
        UnitDefinition(.area, "km²", 1_000_000, ["km2", "km²", "square kilometer", "square kilometers"]),
        UnitDefinition(.area, "ft²", 0.09290304, ["ft2", "ft²", "sq ft", "square foot", "square feet"]),
        UnitDefinition(.area, "in²", 0.00064516, ["in2", "in²", "sq in", "square inch", "square inches"]),
        UnitDefinition(.area, "acre", 4_046.8564224, ["acre", "acres"]),
        UnitDefinition(.area, "ha", 10_000, ["ha", "hectare", "hectares"]),

        UnitDefinition(.volume, "mL", 0.001, ["ml", "milliliter", "milliliters", "millilitre", "millilitres"]),
        UnitDefinition(.volume, "L", 1, ["l", "liter", "liters", "litre", "litres"]),
        UnitDefinition(.volume, "m³", 1_000, ["m3", "m³", "cubic meter", "cubic meters"]),
        UnitDefinition(.volume, "fl oz", 0.0295735295625, ["fl oz", "fluid ounce", "fluid ounces"]),
        UnitDefinition(.volume, "cup", 0.2365882365, ["cup", "cups"]),
        UnitDefinition(.volume, "pt", 0.473176473, ["pt", "pint", "pints"]),
        UnitDefinition(.volume, "qt", 0.946352946, ["qt", "quart", "quarts"]),
        UnitDefinition(.volume, "gal", 3.785411784, ["gal", "gallon", "gallons"]),
        UnitDefinition(.volume, "imp gal", 4.54609, ["imp gal", "imperial gallon", "imperial gallons"]),
        UnitDefinition(.volume, "tbsp", 0.01478676478125, ["tbsp", "tablespoon", "tablespoons"]),
        UnitDefinition(.volume, "tsp", 0.00492892159375, ["tsp", "teaspoon", "teaspoons"]),

        UnitDefinition(.mass, "mg", 0.000001, ["mg", "milligram", "milligrams"]),
        UnitDefinition(.mass, "g", 0.001, ["g", "gram", "grams"]),
        UnitDefinition(.mass, "kg", 1, ["kg", "kilogram", "kilograms"]),
        UnitDefinition(.mass, "oz", 0.028349523125, ["oz", "ounce", "ounces"]),
        UnitDefinition(.mass, "lb", 0.45359237, ["lb", "lbs", "pound", "pounds"]),
        UnitDefinition(.mass, "st", 6.35029318, ["st", "stone", "stones"]),
        UnitDefinition(.mass, "t", 1_000, ["t", "tonne", "tonnes", "metric ton", "metric tons"]),
        UnitDefinition(.mass, "US ton", 907.18474, ["us ton", "us tons", "short ton", "short tons"]),

        UnitDefinition(
            .temperature, "°C", 1, ["c", "°c", "celsius"],
            toBase: { $0 },
            fromBase: { $0 }
        ),
        UnitDefinition(
            .temperature, "°F", 1, ["f", "°f", "fahrenheit"],
            toBase: { ($0 - 32) * 5 / 9 },
            fromBase: { $0 * 9 / 5 + 32 }
        ),
        UnitDefinition(
            .temperature, "K", 1, ["k", "kelvin"],
            toBase: { $0 - 273.15 },
            fromBase: { $0 + 273.15 }
        ),

        UnitDefinition(.speed, "m/s", 1, ["m/s", "mps", "meter per second", "meters per second"]),
        UnitDefinition(.speed, "km/h", 1 / 3.6, ["km/h", "kmh", "kph", "kilometers per hour"]),
        UnitDefinition(.speed, "mph", 0.44704, ["mph", "miles per hour"]),
        UnitDefinition(.speed, "ft/s", 0.3048, ["ft/s", "fps", "feet per second"]),
        UnitDefinition(.speed, "kn", 0.5144444444, ["kn", "knot", "knots"]),

        UnitDefinition(.time, "ms", 0.001, ["ms", "millisecond", "milliseconds"]),
        UnitDefinition(.time, "s", 1, ["s", "sec", "second", "seconds"]),
        UnitDefinition(.time, "min", 60, ["min", "minute", "minutes"]),
        UnitDefinition(.time, "h", 3_600, ["h", "hr", "hour", "hours"]),
        UnitDefinition(.time, "day", 86_400, ["day", "days"]),
        UnitDefinition(.time, "week", 604_800, ["week", "weeks"]),

        UnitDefinition(.storage, "bit", 0.125, ["bit", "bits"]),
        UnitDefinition(.storage, "B", 1, ["b", "byte", "bytes"]),
        UnitDefinition(.storage, "KB", 1_000, ["kb", "kilobyte", "kilobytes"]),
        UnitDefinition(.storage, "MB", 1_000_000, ["mb", "megabyte", "megabytes"]),
        UnitDefinition(.storage, "GB", 1_000_000_000, ["gb", "gigabyte", "gigabytes"]),
        UnitDefinition(.storage, "TB", 1_000_000_000_000, ["tb", "terabyte", "terabytes"]),
        UnitDefinition(.storage, "KiB", 1_024, ["kib", "kibibyte", "kibibytes"]),
        UnitDefinition(.storage, "MiB", 1_048_576, ["mib", "mebibyte", "mebibytes"]),
        UnitDefinition(.storage, "GiB", 1_073_741_824, ["gib", "gibibyte", "gibibytes"]),
        UnitDefinition(.storage, "TiB", 1_099_511_627_776, ["tib", "tebibyte", "tebibytes"]),

        UnitDefinition(.angle, "rad", 1, ["rad", "radian", "radians"]),
        UnitDefinition(.angle, "°", .pi / 180, ["deg", "degree", "degrees", "°"]),

        UnitDefinition(.energy, "J", 1, ["j", "joule", "joules"]),
        UnitDefinition(.energy, "kJ", 1_000, ["kj", "kilojoule", "kilojoules"]),
        UnitDefinition(.energy, "cal", 4.184, ["cal", "calorie", "calories"]),
        UnitDefinition(.energy, "kcal", 4_184, ["kcal", "kilocalorie", "kilocalories"]),
        UnitDefinition(.energy, "Wh", 3_600, ["wh", "watt hour", "watt hours"]),
        UnitDefinition(.energy, "kWh", 3_600_000, ["kwh", "kilowatt hour", "kilowatt hours"]),
        UnitDefinition(.energy, "BTU", 1_055.05585262, ["btu", "british thermal unit", "british thermal units"]),

        UnitDefinition(.power, "W", 1, ["w", "watt", "watts"]),
        UnitDefinition(.power, "kW", 1_000, ["kw", "kilowatt", "kilowatts"]),
        UnitDefinition(.power, "MW", 1_000_000, ["mw", "megawatt", "megawatts"]),
        UnitDefinition(.power, "hp", 745.699871582, ["hp", "horsepower"]),

        UnitDefinition(.pressure, "Pa", 1, ["pa", "pascal", "pascals"]),
        UnitDefinition(.pressure, "kPa", 1_000, ["kpa", "kilopascal", "kilopascals"]),
        UnitDefinition(.pressure, "MPa", 1_000_000, ["mpa", "megapascal", "megapascals"]),
        UnitDefinition(.pressure, "bar", 100_000, ["bar", "bars"]),
        UnitDefinition(.pressure, "psi", 6_894.757293168, ["psi", "pounds per square inch"]),
        UnitDefinition(.pressure, "atm", 101_325, ["atm", "atmosphere", "atmospheres"]),
        UnitDefinition(.pressure, "mmHg", 133.322387415, ["mmhg", "torr"]),

        UnitDefinition(.frequency, "Hz", 1, ["hz", "hertz"]),
        UnitDefinition(.frequency, "kHz", 1_000, ["khz", "kilohertz"]),
        UnitDefinition(.frequency, "MHz", 1_000_000, ["mhz", "megahertz"]),
        UnitDefinition(.frequency, "GHz", 1_000_000_000, ["ghz", "gigahertz"])
    ]

    static func looksLikeConversion(_ expression: String) -> Bool {
        conversionParts(expression) != nil
    }

    static func convert(_ expression: String) -> CalculatorResult? {
        guard let (sourceText, targetText) = conversionParts(expression),
              let target = unit(matching: targetText) else {
            return nil
        }

        let sourceValue: Double
        let source: UnitDefinition
        if let feetAndInches = parseFeetAndInches(sourceText) {
            sourceValue = feetAndInches
            source = unit(matching: "m")!
        } else {
            guard let parsed = parseSource(sourceText) else { return nil }
            sourceValue = parsed.value
            source = parsed.unit
        }

        guard source.dimension == target.dimension else { return nil }
        let baseValue = source.toBase?(sourceValue) ?? sourceValue * source.factor
        let converted = target.fromBase?(baseValue) ?? baseValue / target.factor
        guard converted.isFinite else { return nil }

        let value = "\(Calculator.format(converted)) \(target.symbol)"
        return CalculatorResult(value: value, detail: "Press Return to copy")
    }

    private static func conversionParts(_ expression: String) -> (String, String)? {
        let lowercase = expression.lowercased()
        for separator in [" into ", " to ", " as ", " in "] {
            guard let range = lowercase.range(of: separator, options: .backwards) else {
                continue
            }
            let left = String(expression[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(expression[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !left.isEmpty, !right.isEmpty, unit(matching: right) != nil {
                return (left, right)
            }
        }
        return nil
    }

    private static func parseSource(_ text: String) -> (value: Double, unit: UnitDefinition)? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for candidate in allAliasesByLength {
            guard normalized.hasSuffix(candidate.alias) else { continue }
            let boundary = normalized.index(normalized.endIndex, offsetBy: -candidate.alias.count)
            let expression = String(normalized[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expression.isEmpty,
                  let value = Calculator.arithmeticValue(expression) else {
                continue
            }
            return (value, candidate.unit)
        }
        return nil
    }

    private static func parseFeetAndInches(_ text: String) -> Double? {
        let pattern = #"^\s*(\d+(?:\.\d+)?)\s*(?:ft|foot|feet|')\s*(\d+(?:\.\d+)?)?\s*(?:in|inch|inches|")?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let feetRange = Range(match.range(at: 1), in: text),
              let feet = Double(text[feetRange]) else {
            return nil
        }
        var inches = 0.0
        if match.range(at: 2).location != NSNotFound,
           let inchesRange = Range(match.range(at: 2), in: text) {
            inches = Double(text[inchesRange]) ?? 0
        }
        return feet * 0.3048 + inches * 0.0254
    }

    private static func unit(matching text: String) -> UnitDefinition? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return allAliasesByLength.first(where: { $0.alias == normalized })?.unit
    }

    private static let allAliasesByLength: [(alias: String, unit: UnitDefinition)] = {
        units.flatMap { unit in
            unit.aliases.map { ($0.lowercased(), unit) }
        }
        .sorted { $0.alias.count > $1.alias.count }
    }()
}
