import Foundation

/// Powers the main search bar's inline calculator: typing something like "12 * (4 + 1)"
/// shows the answer as a result, and pressing Enter copies it to the clipboard (see the
/// `.calculator` result built in `SearchEngine`).
///
/// Deliberately hand-rolled instead of `NSExpression(format:)` — `NSExpression` raises an
/// uncatchable Objective-C exception on malformed input, which would crash the app on
/// every mistyped or half-typed search, and this is evaluated on nearly every keystroke.
enum CalculatorEngine {
    /// Every character a calculator expression could legitimately contain.
    private static let allowedCharacters = CharacterSet(charactersIn: "0123456789+-*/%^(). \t")
    private static let operatorCharacters = CharacterSet(charactersIn: "+-*/%^")

    /// Recognizes strings that are plausibly a math expression, so ordinary searches
    /// (app names, file names, etc.) never risk being misread as one: anything containing
    /// a letter or other non-calculator character is rejected outright, and a bare number
    /// with no operator (e.g. "5") is left alone so it still falls through to normal
    /// search rather than being hijacked into showing itself as its own "answer".
    static func looksLikeExpression(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.rangeOfCharacter(from: allowedCharacters.inverted) == nil else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        guard trimmed.rangeOfCharacter(from: operatorCharacters) != nil else { return false }
        return true
    }

    /// Evaluates a math expression, or returns `nil` for anything malformed (unbalanced
    /// parentheses, a trailing operator, division by zero, etc.) — callers see a query
    /// that just hasn't resolved to an answer yet rather than a crash.
    static func evaluate(_ input: String) -> Double? {
        guard looksLikeExpression(input) else { return nil }
        var parser = Parser(input)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// Formats a result the way a pocket calculator would: whole numbers with no decimal
    /// point, everything else rounded to a sane number of digits with trailing zeros
    /// trimmed off.
    static func format(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Hand-rolled recursive-descent parser for `+ - * / % ^ ( )` with standard
    /// precedence, right-associative `^`, and unary `+`/`-`.
    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ input: String) {
            characters = Array(input.trimmingCharacters(in: .whitespaces))
        }

        var isAtEnd: Bool {
            mutating get {
                skipWhitespace()
                return index >= characters.count
            }
        }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while true {
                skipWhitespace()
                guard let op = peek(), op == "+" || op == "-" else { break }
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while true {
                skipWhitespace()
                guard let op = peek(), op == "*" || op == "/" || op == "%" else { break }
                index += 1
                guard let rhs = parsePower() else { return nil }
                switch op {
                case "*":
                    value *= rhs
                case "/":
                    guard rhs != 0 else { return nil }
                    value /= rhs
                default: // "%"
                    guard rhs != 0 else { return nil }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            skipWhitespace()
            guard let op = peek(), op == "^" else { return base }
            index += 1
            guard let exponent = parsePower() else { return nil } // right-associative
            return pow(base, exponent)
        }

        private mutating func parseUnary() -> Double? {
            skipWhitespace()
            if let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return op == "-" ? -value : value
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Double? {
            skipWhitespace()
            guard let char = peek() else { return nil }
            if char == "(" {
                index += 1
                guard let value = parseExpression() else { return nil }
                skipWhitespace()
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            skipWhitespace()
            let start = index
            var sawDigit = false
            var sawDot = false
            while let char = peek() {
                if char.isNumber {
                    sawDigit = true
                    index += 1
                } else if char == "." && !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard sawDigit, let value = Double(String(characters[start..<index])) else { return nil }
            return value
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func skipWhitespace() {
            while let char = peek(), char == " " || char == "\t" {
                index += 1
            }
        }
    }
}
