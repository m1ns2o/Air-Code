import LanguageSupport
import RegexBuilder

public extension LanguageConfiguration {
    static func json(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        dataLanguage(
            name: "JSON",
            singleLineComment: nil,
            reservedIdentifiers: ["true", "false", "null"],
            reservedOperators: ["{", "}", "[", "]", ":", ","],
            languageService: languageService
        )
    }

    static func yaml(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        dataLanguage(
            name: "YAML",
            singleLineComment: "#",
            reservedIdentifiers: ["true", "false", "null", "yes", "no", "on", "off"],
            reservedOperators: [":", "-", "---", "...", "|", ">"],
            languageService: languageService
        )
    }

    static func toml(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        dataLanguage(
            name: "TOML",
            singleLineComment: "#",
            reservedIdentifiers: ["true", "false"],
            reservedOperators: ["=", "[", "]", ".", ","],
            languageService: languageService
        )
    }

    static func markdown(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        dataLanguage(
            name: "Markdown",
            singleLineComment: nil,
            reservedIdentifiers: [],
            reservedOperators: ["#", "##", "###", "-", "*", ">", "`", "```", "[", "]", "(", ")"],
            languageService: languageService
        )
    }

    static func html(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        markupLanguage(name: "HTML", languageService: languageService)
    }

    static func css(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "CSS",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            singleLineComment: nil,
            nestedComment: (open: "/*", close: "*/"),
            identifierExtras: "_-",
            reservedIdentifiers: [
                "align-items", "animation", "background", "border", "box-shadow", "color",
                "display", "flex", "font", "font-size", "gap", "grid", "height",
                "justify-content", "margin", "opacity", "padding", "position", "transform",
                "transition", "var", "width", "z-index"
            ],
            reservedOperators: [":", ";", "{", "}", ".", "#", ">", "+", "~", ",", "(", ")"],
            languageService: languageService
        )
    }

    static func shell(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "Shell",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            singleLineComment: "#",
            nestedComment: nil,
            identifierExtras: "_-",
            reservedIdentifiers: [
                "alias", "break", "case", "cd", "continue", "do", "done", "elif", "else",
                "esac", "export", "fi", "for", "function", "if", "in", "local", "read",
                "return", "set", "shift", "then", "unset", "until", "while"
            ],
            reservedOperators: ["|", "||", "&", "&&", ">", ">>", "<", "<<", "=", "$", "${", "}"],
            languageService: languageService
        )
    }

    static func dockerfile(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        dataLanguage(
            name: "Dockerfile",
            singleLineComment: "#",
            reservedIdentifiers: [
                "ADD", "ARG", "CMD", "COPY", "ENTRYPOINT", "ENV", "EXPOSE", "FROM",
                "HEALTHCHECK", "LABEL", "MAINTAINER", "ONBUILD", "RUN", "SHELL",
                "STOPSIGNAL", "USER", "VOLUME", "WORKDIR"
            ],
            reservedOperators: ["=", "\\", "&&", "||"],
            languageService: languageService
        )
    }

    static func rust(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "Rust",
            reservedIdentifiers: [
                "as", "async", "await", "break", "const", "continue", "crate", "dyn",
                "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in",
                "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
                "self", "Self", "static", "struct", "super", "trait", "true", "type",
                "unsafe", "use", "where", "while"
            ],
            languageService: languageService
        )
    }

    static func java(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "Java",
            reservedIdentifiers: [
                "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
                "class", "const", "continue", "default", "do", "double", "else", "enum",
                "extends", "final", "finally", "float", "for", "if", "implements", "import",
                "instanceof", "int", "interface", "long", "native", "new", "null", "package",
                "private", "protected", "public", "return", "short", "static", "strictfp",
                "super", "switch", "synchronized", "this", "throw", "throws", "transient",
                "true", "try", "void", "volatile", "while"
            ],
            languageService: languageService
        )
    }

    static func kotlin(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "Kotlin",
            reservedIdentifiers: [
                "as", "break", "class", "continue", "do", "else", "false", "for", "fun",
                "if", "in", "interface", "is", "null", "object", "package", "return",
                "super", "this", "throw", "true", "try", "typealias", "val", "var",
                "when", "while"
            ],
            languageService: languageService
        )
    }

    static func c(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "C",
            reservedIdentifiers: [
                "auto", "break", "case", "char", "const", "continue", "default", "do",
                "double", "else", "enum", "extern", "float", "for", "goto", "if",
                "inline", "int", "long", "register", "restrict", "return", "short",
                "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
                "unsigned", "void", "volatile", "while"
            ],
            languageService: languageService
        )
    }

    static func cpp(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "C++",
            reservedIdentifiers: [
                "alignas", "auto", "bool", "break", "case", "catch", "class", "concept",
                "const", "constexpr", "continue", "decltype", "default", "delete", "do",
                "double", "else", "enum", "explicit", "export", "extern", "false", "float",
                "for", "friend", "if", "inline", "int", "long", "namespace", "new",
                "noexcept", "nullptr", "operator", "private", "protected", "public",
                "requires", "return", "short", "signed", "sizeof", "static", "struct",
                "switch", "template", "this", "throw", "true", "try", "typedef",
                "typename", "union", "unsigned", "using", "virtual", "void", "while"
            ],
            languageService: languageService
        )
    }

    static func csharp(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "C#",
            reservedIdentifiers: [
                "abstract", "as", "async", "await", "base", "bool", "break", "case",
                "catch", "class", "const", "continue", "decimal", "default", "delegate",
                "do", "double", "else", "enum", "event", "explicit", "extern", "false",
                "finally", "fixed", "float", "for", "foreach", "if", "implicit", "in",
                "int", "interface", "internal", "is", "lock", "long", "namespace", "new",
                "null", "object", "operator", "out", "override", "private", "protected",
                "public", "readonly", "record", "ref", "return", "sealed", "short",
                "sizeof", "static", "string", "struct", "switch", "this", "throw", "true",
                "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "using", "var",
                "virtual", "void", "volatile", "while", "yield"
            ],
            languageService: languageService
        )
    }

    static func php(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "PHP",
            identifierExtras: "_$",
            reservedIdentifiers: [
                "abstract", "and", "array", "as", "break", "callable", "case", "catch",
                "class", "clone", "const", "continue", "declare", "default", "die", "do",
                "echo", "else", "elseif", "empty", "endfor", "endforeach", "endif",
                "endswitch", "endwhile", "eval", "exit", "extends", "final", "finally",
                "fn", "for", "foreach", "function", "global", "if", "implements", "include",
                "instanceof", "interface", "isset", "list", "match", "namespace", "new",
                "or", "print", "private", "protected", "public", "require", "return",
                "static", "switch", "throw", "trait", "try", "use", "var", "while", "xor",
                "yield"
            ],
            languageService: languageService
        )
    }

    static func ruby(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "Ruby",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            singleLineComment: "#",
            nestedComment: nil,
            identifierExtras: "_?!",
            reservedIdentifiers: [
                "BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def",
                "defined?", "do", "else", "elsif", "end", "ensure", "false", "for", "if",
                "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
                "return", "self", "super", "then", "true", "undef", "unless", "until",
                "when", "while", "yield"
            ],
            reservedOperators: ["+", "-", "*", "/", "%", "=", "==", "!=", "=>", "::", ".", "&", "|"],
            languageService: languageService
        )
    }

    static func dart(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
        cLikeLanguage(
            name: "Dart",
            reservedIdentifiers: [
                "abstract", "as", "assert", "async", "await", "base", "break", "case",
                "catch", "class", "const", "continue", "covariant", "default", "deferred",
                "do", "dynamic", "else", "enum", "export", "extends", "extension", "external",
                "factory", "false", "final", "finally", "for", "Function", "get", "hide",
                "if", "implements", "import", "in", "interface", "is", "late", "library",
                "mixin", "new", "null", "of", "on", "operator", "part", "required",
                "rethrow", "return", "sealed", "set", "show", "static", "super", "switch",
                "sync", "this", "throw", "true", "try", "typedef", "var", "void", "when",
                "while", "with", "yield"
            ],
            languageService: languageService
        )
    }

    private static func markupLanguage(name: String, languageService: LanguageService?) -> LanguageConfiguration {
        cLikeLanguage(
            name: name,
            supportsSquareBrackets: false,
            supportsCurlyBrackets: true,
            singleLineComment: nil,
            nestedComment: (open: "<!--", close: "-->"),
            identifierExtras: "_-:",
            reservedIdentifiers: [
                "a", "body", "button", "class", "div", "head", "html", "id", "img",
                "input", "link", "main", "meta", "script", "section", "span", "style",
                "template", "title"
            ],
            reservedOperators: ["<", ">", "</", "/>", "=", "\"", "'", "{", "}"],
            languageService: languageService
        )
    }

    private static func dataLanguage(
        name: String,
        singleLineComment: String?,
        reservedIdentifiers: [String],
        reservedOperators: [String],
        languageService: LanguageService?
    ) -> LanguageConfiguration {
        cLikeLanguage(
            name: name,
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            singleLineComment: singleLineComment,
            nestedComment: nil,
            identifierExtras: "_-",
            reservedIdentifiers: reservedIdentifiers,
            reservedOperators: reservedOperators,
            languageService: languageService
        )
    }

    private static func cLikeLanguage(
        name: String,
        supportsSquareBrackets: Bool = true,
        supportsCurlyBrackets: Bool = true,
        singleLineComment: String? = "//",
        nestedComment: (open: String, close: String)? = (open: "/*", close: "*/"),
        identifierExtras: String = "_",
        reservedIdentifiers: [String],
        reservedOperators: [String] = [
            "=>", "==", "!=", "<", ">", "<=", ">=", "=", "+", "-", "*", "/", "%",
            "++", "--", "&&", "||", "!", "??", "?.", "...", ":", "?", "&", "|",
            "^", "~", "<<", ">>", "+=", "-=", "*=", "/=", "%=", "{", "}", "[", "]"
        ],
        languageService: LanguageService?
    ) -> LanguageConfiguration {
        let identifierStart = CharacterClass("a"..."z", "A"..."Z", .anyOf(identifierExtras))
        let identifierPart = CharacterClass(identifierStart, "0"..."9")
        let identifierRegex: Regex<Substring> = Regex {
            identifierStart
            ZeroOrMore { identifierPart }
        }
        let operatorRegex: Regex<Substring> = Regex {
            OneOrMore { CharacterClass(.anyOf("+-*/%=&|!<>^~?:.#@$\\[]{}(),;")) }
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

        return LanguageConfiguration(
            name: name,
            supportsSquareBrackets: supportsSquareBrackets,
            supportsCurlyBrackets: supportsCurlyBrackets,
            stringRegex: stringRegex,
            characterRegex: /'(?:\\'|[^']|\\[^']*+)'/,
            numberRegex: numberRegex,
            singleLineComment: singleLineComment,
            nestedComment: nestedComment,
            identifierRegex: identifierRegex,
            operatorRegex: operatorRegex,
            reservedIdentifiers: reservedIdentifiers,
            reservedOperators: reservedOperators,
            languageService: languageService
        )
    }
}
