import LanguageSupport
import RegexBuilder

public extension LanguageConfiguration {
    static func go(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        let identifierStart = CharacterClass("a"..."z", "A"..."Z", .anyOf("_"))
        let identifierPart = CharacterClass(identifierStart, "0"..."9")
        let identifierRegex: Regex<Substring> = Regex {
            identifierStart
            ZeroOrMore {
                identifierPart
            }
        }
        let operatorRegex: Regex<Substring> = Regex {
            OneOrMore {
                CharacterClass(.anyOf("+-*/%&|^<>=!:.~"))
            }
        }
        let numberRegex: Regex<Substring> = Regex {
            optNegation
            ChoiceOf {
                Regex { /0[bB]/; binaryLit }
                Regex { /0[oO]/; octalLit }
                Regex { /0[xX]/; hexalLit }
                Regex { decimalLit; "."; decimalLit; Optionally { exponentLit } }
                Regex { decimalLit; exponentLit }
                decimalLit
            }
            Optionally {
                "i"
            }
        }
        let reservedIdentifiers = [
            "break", "default", "func", "interface", "select",
            "case", "defer", "go", "map", "struct",
            "chan", "else", "goto", "package", "switch",
            "const", "fallthrough", "if", "range", "type",
            "continue", "for", "import", "return", "var",
            "nil", "true", "false", "iota",
            "bool", "byte", "complex64", "complex128", "error",
            "float32", "float64", "int", "int8", "int16", "int32", "int64",
            "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
            "any", "comparable"
        ]

        return LanguageConfiguration(
            name: "Go",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            stringRegex: Regex {
                ChoiceOf {
                    /"(?:\\"|\\\\|[^"])*+"/
                    /`[^`]*`/
                }
            },
            characterRegex: /'(?:\\'|[^']|\\[^']*+)'/,
            numberRegex: numberRegex,
            singleLineComment: "//",
            nestedComment: (open: "/*", close: "*/"),
            identifierRegex: identifierRegex,
            operatorRegex: operatorRegex,
            reservedIdentifiers: reservedIdentifiers,
            reservedOperators: [],
            languageService: languageService
        )
    }
}
