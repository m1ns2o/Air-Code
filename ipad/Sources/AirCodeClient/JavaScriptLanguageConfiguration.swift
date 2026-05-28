import LanguageSupport
import RegexBuilder

public extension LanguageConfiguration {
    static func javascript(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        webScriptLanguage(name: "JavaScript", languageService: languageService)
    }

    static func typescript(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        webScriptLanguage(name: "TypeScript", languageService: languageService)
    }

    static func vue(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        webScriptLanguage(name: "Vue", languageService: languageService)
    }

    private static func webScriptLanguage(name: String, languageService: LanguageService?) -> LanguageConfiguration {
        let identifierStart = CharacterClass("a"..."z", "A"..."Z", .anyOf("_$"))
        let identifierPart = CharacterClass(identifierStart, "0"..."9")
        let identifierRegex: Regex<Substring> = Regex {
            identifierStart
            ZeroOrMore {
                identifierPart
            }
        }
        let operatorRegex: Regex<Substring> = Regex {
            OneOrMore {
                CharacterClass(.anyOf("+-*/%=&|!<>^~?:."))
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
        }
        let stringRegex: Regex<Substring> = Regex {
            ChoiceOf {
                /"(?:\\"|\\\\|[^"])*+"/
                /'(?:\\'|\\\\|[^'])*+'/
                /`(?:\\`|\\\\|[^`])*+`/
            }
        }
        let reservedIdentifiers = [
            "abstract", "any", "as", "async", "await", "boolean", "break", "case", "catch", "class",
            "const", "constructor", "continue", "debugger", "declare", "default", "delete", "do",
            "else", "enum", "export", "extends", "false", "finally", "for", "from", "function",
            "get", "if", "implements", "import", "in", "infer", "instanceof", "interface", "is",
            "keyof", "let", "module", "namespace", "never", "new", "null", "number", "object",
            "of", "package", "private", "protected", "public", "readonly", "require", "return",
            "satisfies", "set", "static", "string", "super", "switch", "symbol", "this", "throw",
            "true", "try", "type", "typeof", "undefined", "unique", "unknown", "var", "void",
            "while", "with", "yield"
        ]
        let reservedOperators = [
            "=>", "==", "===", "!=", "!==", "<", ">", "<=", ">=", "=", "+", "-", "*", "/",
            "%", "**", "++", "--", "&&", "||", "!", "??", "?.", "...", ":", "?", "&", "|",
            "^", "~", "<<", ">>", ">>>", "+=", "-=", "*=", "/=", "%=", "**=", "&&=", "||=", "??="
        ]

        return LanguageConfiguration(
            name: name,
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            stringRegex: stringRegex,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: "//",
            nestedComment: (open: "/*", close: "*/"),
            identifierRegex: identifierRegex,
            operatorRegex: operatorRegex,
            reservedIdentifiers: reservedIdentifiers,
            reservedOperators: reservedOperators,
            languageService: languageService
        )
    }
}
