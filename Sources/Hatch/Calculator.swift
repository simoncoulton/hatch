import Foundation

/// Hand-rolled expression evaluator. `NSExpression` raises ObjC exceptions on bad input, which Swift can't catch.
enum Calculator {
    struct Failure: Error {}

    /// Returns the formatted result, or nil when the input isn't a calculation.
    /// A bare number or constant ("5", "pi") is not treated as one, so it doesn't crowd out app results.
    static func evaluate(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("=") { s.removeFirst() }
        s = s.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
        guard s.contains(where: \.isNumber) else { return nil }
        var parser = Parser(chars: Array(s))
        guard let value = try? parser.parse(), value.isFinite, parser.interesting else { return nil }
        return format(value)
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return String(format: "%.10g", v)
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0
        /// Set once a binary operator or function call is seen.
        var interesting = false

        mutating func parse() throws -> Double {
            let v = try expr()
            guard peek() == nil else { throw Failure() }
            return v
        }

        mutating func skip() { while pos < chars.count, chars[pos] == " " { pos += 1 } }

        mutating func peek() -> Character? {
            skip()
            return pos < chars.count ? chars[pos] : nil
        }

        mutating func expr() throws -> Double {
            var v = try term()
            while let c = peek(), c == "+" || c == "-" {
                pos += 1
                let r = try term()
                v = c == "+" ? v + r : v - r
                interesting = true
            }
            return v
        }

        mutating func term() throws -> Double {
            var v = try unary()
            while let c = peek(), c == "*" || c == "/" || c == "%" {
                pos += 1
                let r = try unary()
                switch c {
                case "*": v *= r
                case "/": v /= r
                default: v = v.truncatingRemainder(dividingBy: r)
                }
                interesting = true
            }
            return v
        }

        mutating func unary() throws -> Double {
            if let c = peek(), c == "-" || c == "+" {
                pos += 1
                let v = try unary()
                return c == "-" ? -v : v
            }
            return try power()
        }

        /// Right-associative, and binds tighter than unary minus: -2^2 == -4.
        mutating func power() throws -> Double {
            let base = try primary()
            if peek() == "^" {
                pos += 1
                interesting = true
                return pow(base, try unary())
            }
            return base
        }

        mutating func primary() throws -> Double {
            guard let c = peek() else { throw Failure() }
            if c == "(" {
                pos += 1
                let v = try expr()
                guard peek() == ")" else { throw Failure() }
                pos += 1
                return v
            }
            if c.isNumber || c == "." { return try number() }
            if c.isLetter {
                var name = ""
                while pos < chars.count, chars[pos].isLetter || chars[pos].isNumber { name.append(chars[pos]); pos += 1 }
                name = name.lowercased()
                if peek() == "(" {
                    pos += 1
                    let arg = try expr()
                    guard peek() == ")" else { throw Failure() }
                    pos += 1
                    interesting = true
                    guard let f = Self.functions[name] else { throw Failure() }
                    return f(arg)
                }
                guard let k = Self.constants[name] else { throw Failure() }
                return k
            }
            throw Failure()
        }

        mutating func number() throws -> Double {
            var text = ""
            while pos < chars.count, chars[pos].isNumber || chars[pos] == "." { text.append(chars[pos]); pos += 1 }
            guard let v = Double(text) else { throw Failure() }
            return v
        }

        static let constants: [String: Double] = ["pi": .pi, "e": M_E, "tau": 2 * .pi]

        static let functions: [String: (Double) -> Double] = [
            "sqrt": sqrt, "abs": abs, "floor": floor, "ceil": ceil, "round": { $0.rounded() },
            "sin": sin, "cos": cos, "tan": tan, "asin": asin, "acos": acos, "atan": atan,
            "ln": log, "log": log10, "log2": log2, "exp": exp,
        ]
    }
}
