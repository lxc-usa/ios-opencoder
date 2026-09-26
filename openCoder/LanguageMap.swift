import Foundation
import Runestone
import TreeSitterJSON
import TreeSitterAstroRunestone
import TreeSitterBashRunestone
import TreeSitterCRunestone
import TreeSitterCPPRunestone
import TreeSitterCSharpRunestone
import TreeSitterCSSRunestone
import TreeSitterElixirRunestone
import TreeSitterElmRunestone
import TreeSitterGoRunestone
import TreeSitterHaskellRunestone
import TreeSitterHTMLRunestone
import TreeSitterJavaRunestone
import TreeSitterJavaScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterJuliaRunestone
import TreeSitterLaTeXRunestone
import TreeSitterLuaRunestone
import TreeSitterMarkdownRunestone
import TreeSitterOCamlRunestone
import TreeSitterPHPRunestone
import TreeSitterPerlRunestone
import TreeSitterPythonRunestone
import TreeSitterRRunestone
import TreeSitterRubyRunestone
import TreeSitterRustRunestone
import TreeSitterSCSSRunestone
import TreeSitterSQLRunestone
import TreeSitterSvelteRunestone
import TreeSitterSwiftRunestone
import TreeSitterTOMLRunestone
import TreeSitterTSXRunestone
import TreeSitterTypeScriptRunestone
import TreeSitterYAMLRunestone

extension TreeSitterLanguage {
    /// 纯文本语言：用 JSON 语法做解析但不带任何高亮查询，效果等价于无高亮。
    /// Runestone 的 TextViewState 要求 language 非空，因此需要这样一个占位语言。
    static var plainText: TreeSitterLanguage {
        TreeSitterLanguage(tree_sitter_json())
    }

    /// 按文件扩展名选择语法高亮语言。
    static func forFileExtension(_ ext: String) -> TreeSitterLanguage {
        switch ext.lowercased() {
        case "swift": return .swift
        case "py", "pyw": return .python
        case "js", "mjs", "cjs", "jsx": return .javaScript
        case "ts", "mts", "cts": return .typeScript
        case "tsx": return .tsx
        case "json": return .json
        case "json5": return .json5
        case "md", "markdown", "mdown": return .markdown
        case "sh", "bash", "zsh": return .bash
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hh": return .cpp
        case "cs": return .cSharp
        case "java": return .java
        case "go": return .go
        case "rs": return .rust
        case "php": return .php
        case "rb": return .ruby
        case "sql": return .sql
        case "yaml", "yml": return .yaml
        case "toml": return .toml
        case "lua": return .lua
        case "html", "htm": return .html
        case "css": return .css
        case "scss": return .scss
        case "astro": return .astro
        case "svelte": return .svelte
        case "ex", "exs": return .elixir
        case "elm": return .elm
        case "hs": return .haskell
        case "jl": return .julia
        case "tex": return .latex
        case "ml": return .ocaml
        case "pl", "pm": return .perl
        case "r": return .r
        default: return .plainText
        }
    }
}
