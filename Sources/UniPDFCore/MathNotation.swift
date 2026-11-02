import AppKit

/// A deliberately small, offline notation renderer. Unknown commands remain visible.
public enum MathNotation {
    public static func formatted(_ source: String, size: CGFloat = 19) -> NSAttributedString {
        render(source, size: size, depth: 0)
    }

    private static func render(_ source: String, size: CGFloat, depth: Int) -> NSAttributedString {
        let font = NSFont(name: "STIXTwoMath-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
        guard depth < 12 else {
            return NSAttributedString(string: source, attributes: [.font: font, .foregroundColor: NSColor.black])
        }
        let result = NSMutableAttributedString()
        let chars = Array(source)
        var index = 0
        let symbols = ["alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "theta": "θ",
                       "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "omega": "ω",
                       "Delta": "Δ", "Sigma": "Σ", "sum": "∑", "int": "∫", "infty": "∞",
                       "times": "×", "cdot": "·", "pm": "±", "leq": "≤", "geq": "≥",
                       "neq": "≠", "approx": "≈", "rightarrow": "→"]
        func append(_ text: String, scale: CGFloat = 1, baseline: CGFloat = 0) {
            result.append(NSAttributedString(string: text, attributes: [
                .font: NSFont(name: "STIXTwoMath-Regular", size: size * scale) ?? NSFont.systemFont(ofSize: size * scale),
                .baselineOffset: baseline, .foregroundColor: NSColor.black
            ]))
        }
        func appendGroup(_ text: String, scale: CGFloat = 1, baseline: CGFloat = 0) {
            let nested = NSMutableAttributedString(attributedString: render(text, size: size * scale, depth: depth + 1))
            nested.enumerateAttribute(.baselineOffset, in: NSRange(location: 0, length: nested.length)) { value, range, _ in
                nested.addAttribute(.baselineOffset, value: (value as? CGFloat ?? 0) + baseline, range: range)
            }
            result.append(nested)
        }
        func group() -> String {
            guard index < chars.count else { return "" }
            guard chars[index] == "{" else { defer { index += 1 }; return String(chars[index]) }
            index += 1
            let start = index
            var depth = 1
            while index < chars.count {
                if chars[index] == "{" { depth += 1 }
                if chars[index] == "}" { depth -= 1 }
                if depth == 0 {
                    let value = String(chars[start..<index]); index += 1; return value
                }
                index += 1
            }
            return "{" + String(chars[start..<index])
        }
        // Nested groups are bounded to keep malformed imported formulas safe to display.
        while index < chars.count {
            let character = chars[index]
            index += 1
            if character == "^" || character == "_" {
                let value = group()
                appendGroup(value, scale: 0.72, baseline: character == "^" ? size * 0.4 : -size * 0.22)
            } else if character == "\\" {
                let start = index
                while index < chars.count && chars[index].isLetter { index += 1 }
                let command = String(chars[start..<index])
                if command == "frac" {
                    let numerator = group(), denominator = group()
                    append("(")
                    appendGroup(numerator, scale: 0.85, baseline: size * 0.22)
                    append(" ⁄ ")
                    appendGroup(denominator, scale: 0.85, baseline: -size * 0.12)
                    append(")")
                } else if command == "sqrt" { append("√("); appendGroup(group()); append(")") }
                else if let symbol = symbols[command] { append(symbol) }
                else { append("\\" + command) }
            } else { append(String(character)) }
        }
        return result
    }
}
