import AppKit

/// A deliberately small, offline notation renderer. Unknown commands remain visible.
public enum MathNotation {
    public static func formatted(_ source: String, size: CGFloat = 19, color: NSColor = .black) -> NSAttributedString {
        render(source, size: size, color: color, depth: 0)
    }

    /// Commands and the characters they stand for. The formula palette inserts the characters directly,
    /// so typed LaTeX and picked symbols look the same.
    public static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "phi": "φ", "varphi": "φ", "chi": "χ",
        "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators and relations
        "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "oint": "∮", "partial": "∂", "nabla": "∇", "infty": "∞",
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥",
        "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝", "ll": "≪", "gg": "≫",
        "circ": "∘", "ast": "∗", "dots": "…", "ldots": "…", "cdots": "⋯", "degree": "°",
        // Arrows and logic
        "rightarrow": "→", "to": "→", "leftarrow": "←", "leftrightarrow": "↔", "Rightarrow": "⇒", "implies": "⇒",
        "Leftarrow": "⇐", "Leftrightarrow": "⇔", "iff": "⇔", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "neg": "¬", "lnot": "¬", "forall": "∀", "exists": "∃",
        "nexists": "∄", "top": "⊤", "bot": "⊥", "vdash": "⊢", "models": "⊨", "oplus": "⊕", "otimes": "⊗",
        // Sets
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇",
        "nsubseteq": "⊈", "cup": "∪", "cap": "∩", "setminus": "∖", "emptyset": "∅", "varnothing": "∅",
        "bigcup": "⋃", "bigcap": "⋂", "mid": "∣", "complement": "∁", "aleph": "ℵ",
        // Geometry and linear algebra
        "angle": "∠", "perp": "⊥", "parallel": "∥", "triangle": "△", "langle": "⟨", "rangle": "⟩",
        "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "hbar": "ℏ", "ell": "ℓ",
        // Spacing and sizing that the renderer leaves to the font
        "quad": "  ", "qquad": "    ", "left": "", "right": "", "displaystyle": ""
    ]

    /// Named functions are upright, as in LaTeX.
    private static let functions: Set<String> = ["sin", "cos", "tan", "cot", "arcsin", "arccos", "arctan", "sinh", "cosh",
                                                 "tanh", "log", "ln", "lg", "exp", "lim", "max", "min", "sup", "inf",
                                                 "det", "dim", "ker", "rank", "deg", "gcd", "mod", "Var", "Cov", "Pr"]

    private static let doubleStruck: [Character: String] = ["N": "ℕ", "Z": "ℤ", "Q": "ℚ", "R": "ℝ", "C": "ℂ", "P": "ℙ",
                                                            "H": "ℍ", "E": "𝔼", "K": "𝕂", "1": "𝟙"]

    private static func render(_ source: String, size: CGFloat, color: NSColor, depth: Int) -> NSAttributedString {
        let font = NSFont(name: "STIXTwoMath-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
        guard depth < 12 else {
            return NSAttributedString(string: source, attributes: [.font: font, .foregroundColor: color])
        }
        let result = NSMutableAttributedString()
        let chars = Array(source)
        var index = 0
        func append(_ text: String, scale: CGFloat = 1, baseline: CGFloat = 0) {
            result.append(NSAttributedString(string: text, attributes: [
                .font: NSFont(name: "STIXTwoMath-Regular", size: size * scale) ?? NSFont.systemFont(ofSize: size * scale),
                .baselineOffset: baseline, .foregroundColor: color
            ]))
        }
        func appendGroup(_ text: String, scale: CGFloat = 1, baseline: CGFloat = 0) {
            let nested = NSMutableAttributedString(attributedString: render(text, size: size * scale, color: color, depth: depth + 1))
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
                } else if command == "binom" {
                    let n = group(), k = group()
                    append("(")
                    appendGroup(n, scale: 0.8, baseline: size * 0.25)
                    append(" ")
                    appendGroup(k, scale: 0.8, baseline: -size * 0.15)
                    append(")")
                } else if command == "sqrt" {
                    // \sqrt[n]{x}: the degree sits small in front of the root sign.
                    if index < chars.count, chars[index] == "[", let close = chars[index...].firstIndex(of: "]") {
                        appendGroup(String(chars[(index + 1)..<close]), scale: 0.6, baseline: size * 0.35)
                        index = close + 1
                    }
                    append("√("); appendGroup(group()); append(")")
                }
                else if command == "mathbb" { append(group().map { doubleStruck[$0] ?? String($0) }.joined()) }
                else if command == "text" || command == "mathrm" || command == "operatorname" {
                    result.append(NSAttributedString(string: group(), attributes: [
                        .font: NSFont.systemFont(ofSize: size * 0.9), .foregroundColor: color
                    ]))
                }
                else if command == "vec" { appendGroup(group()); append("\u{20D7}") }
                else if command == "overline" || command == "bar" { appendGroup(group()); append("\u{0305}") }
                else if command == "hat" { appendGroup(group()); append("\u{0302}") }
                else if functions.contains(command) {
                    result.append(NSAttributedString(string: command, attributes: [
                        .font: NSFont.systemFont(ofSize: size * 0.92), .foregroundColor: color
                    ]))
                }
                else if let symbol = symbols[command] { append(symbol) }
                else if command.isEmpty, index < chars.count {
                    // \{, \} and \, : an escaped brace or a thin space.
                    let next = chars[index]; index += 1
                    append(next == "," || next == ";" || next == " " ? "\u{2009}" : next == "|" ? "‖" : String(next))
                }
                else { append("\\" + command) }
            } else { append(String(character)) }
        }
        return result
    }
}
