import Foundation

enum HtmlFormParser {
    static func deEntitize(_ raw: String) -> String {
        var s = raw
        let named: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        for (k, v) in named {
            s = s.replacingOccurrences(of: k, with: v)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") {
            let ns = s as NSString
            let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let code = ns.substring(with: m.range(at: 1))
                let val: UInt32?
                if code.lowercased().hasPrefix("x") {
                    val = UInt32(code.dropFirst(), radix: 16)
                } else {
                    val = UInt32(code, radix: 10)
                }
                if let val, let scalar = UnicodeScalar(val) {
                    s = (s as NSString).replacingCharacters(in: m.range, with: String(scalar))
                }
            }
        }
        return s
    }

    static func stripTags(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = deEntitize(noTags)
        return decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasLoginForm(_ html: String) -> Bool {
        return html.range(of: #"id\s*=\s*["']login-form["']"#, options: .regularExpression) != nil
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let patterns = [
            "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]*)\"",
            "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*'([^']*)'",
            "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*([^\\s>\"']+)"
        ]
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat),
               let m = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) {
                return deEntitize((tag as NSString).substring(with: m.range(at: 1)))
            }
        }
        return nil
    }

    static func hasBooleanAttribute(_ name: String, in tag: String) -> Bool {
        let pat = "(?i)(?:^|\\s)\(NSRegularExpression.escapedPattern(for: name))(?:\\s*=|\\s|>|/|$)"
        return tag.range(of: pat, options: .regularExpression) != nil
    }

    static func elementTextOrValue(id: String, in html: String) -> String {
        let escapedId = NSRegularExpression.escapedPattern(for: id)
        // Input or element with id="..."
        let tagPat = "(?is)<([a-zA-Z0-9]+)\\b([^>]*\\bid\\s*=\\s*[\"']\(escapedId)[\"'][^>]*)>(?:(.*?)</\\1>)?"
        guard let regex = try? NSRegularExpression(pattern: tagPat),
              let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else {
            return ""
        }
        let ns = html as NSString
        let attrs = ns.substring(with: m.range(at: 2))
        if let val = attribute("value", in: attrs), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if m.range(at: 3).location != NSNotFound {
            return stripTags(ns.substring(with: m.range(at: 3)))
        }
        return ""
    }

    static func productName(in html: String) -> String? {
        let pat = #"(?is)<([a-zA-Z0-9]+)\b[^>]*\bclass\s*=\s*["'][^"']*\bproductName\b[^"']*["'][^>]*>(.*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pat),
              let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else {
            return nil
        }
        let text = stripTags((html as NSString).substring(with: m.range(at: 2)))
        return text.isEmpty ? nil : text
    }

    static func anchorLinks(in html: String) -> [(href: String, meta: String)] {
        let pat = #"(?is)<a\b([^>]*)>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pat) else { return [] }
        let ns = html as NSString
        var out: [(String, String)] = []
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let attrs = ns.substring(with: m.range(at: 1))
            let body = stripTags(ns.substring(with: m.range(at: 2)))
            guard let href = attribute("href", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  href.hasPrefix("/"), !href.hasPrefix("//") else {
                continue
            }
            let cls = attribute("class", in: attrs) ?? ""
            out.append((href, "\(cls) \(body)".trimmingCharacters(in: .whitespaces)))
        }
        return out
    }

    static func findAnchorHref(withClass className: String, in html: String) -> String? {
        let pat = #"(?is)<a\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pat) else { return nil }
        let ns = html as NSString
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let attrs = ns.substring(with: m.range(at: 1))
            let cls = attribute("class", in: attrs) ?? ""
            if cls.contains(className), let href = attribute("href", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty {
                return href
            }
        }
        return nil
    }

    struct ParsedForm {
        var action: String
        var rawHtml: String
        var pairs: [(String, String)]
    }

    static func extractForm(idOrName: String, in html: String) -> ParsedForm? {
        let escaped = NSRegularExpression.escapedPattern(for: idOrName)
        let specificPat = "(?is)<form\\b([^>]*\\b(?:id|name)\\s*=\\s*[\"']\(escaped)[\"'][^>]*)>(.*?)</form>"
        let anyPat = #"(?is)<form\b([^>]*)>(.*?)</form>"#

        let ns = html as NSString
        var match: NSTextCheckingResult?
        if let reg = try? NSRegularExpression(pattern: specificPat) {
            match = reg.firstMatch(in: html, range: NSRange(location: 0, length: ns.length))
        }
        if match == nil, let reg = try? NSRegularExpression(pattern: anyPat) {
            match = reg.firstMatch(in: html, range: NSRange(location: 0, length: ns.length))
        }
        guard let m = match else { return nil }

        let formAttrs = ns.substring(with: m.range(at: 1))
        let body = ns.substring(with: m.range(at: 2))
        let action = attribute("action", in: formAttrs) ?? ""
        let pairs = parseFormPairs(formHtml: body)
        return ParsedForm(action: action, rawHtml: ns.substring(with: m.range), pairs: pairs)
    }

    static func parseFormPairs(formHtml: String) -> [(String, String)] {
        var pairs: [(String, String)] = []
        let ns = formHtml as NSString

        if let inputReg = try? NSRegularExpression(pattern: #"(?is)<input\b([^>]*)/?>"#) {
            for m in inputReg.matches(in: formHtml, range: NSRange(location: 0, length: ns.length)) {
                let attrs = ns.substring(with: m.range(at: 1))
                guard let name = attribute("name", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    continue
                }
                let type = (attribute("type", in: attrs) ?? "text").lowercased()
                if ["submit", "button", "reset", "image"].contains(type) { continue }
                if type == "checkbox" || type == "radio" {
                    guard hasBooleanAttribute("checked", in: attrs) else { continue }
                    let val = attribute("value", in: attrs) ?? "on"
                    pairs.append((name, val))
                } else {
                    pairs.append((name, attribute("value", in: attrs) ?? ""))
                }
            }
        }

        if let selectReg = try? NSRegularExpression(pattern: #"(?is)<select\b([^>]*)>(.*?)</select>"#) {
            for m in selectReg.matches(in: formHtml, range: NSRange(location: 0, length: ns.length)) {
                let attrs = ns.substring(with: m.range(at: 1))
                let inner = ns.substring(with: m.range(at: 2))
                guard let name = attribute("name", in: attrs)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    continue
                }
                let options = parseSelectOptions(in: inner)
                if let selected = options.first(where: { $0.selected }) ?? options.first {
                    pairs.append((name, selected.value))
                }
            }
        }

        return pairs
    }

    struct SelectOption {
        var value: String
        var label: String
        var selected: Bool
    }

    static func parseSelectOptions(in selectHtml: String) -> [SelectOption] {
        guard let optReg = try? NSRegularExpression(pattern: #"(?is)<option\b([^>]*)>(.*?)</option>"#) else {
            return []
        }
        let ns = selectHtml as NSString
        var out: [SelectOption] = []
        for m in optReg.matches(in: selectHtml, range: NSRange(location: 0, length: ns.length)) {
            let attrs = ns.substring(with: m.range(at: 1))
            let label = stripTags(ns.substring(with: m.range(at: 2)))
            let val = (attribute("value", in: attrs) ?? label).trimmingCharacters(in: .whitespacesAndNewlines)
            let isSelected = hasBooleanAttribute("selected", in: attrs)
            out.append(SelectOption(value: val, label: label, selected: isSelected))
        }
        return out
    }

    static func extractSecurityQuestions(in formHtml: String) -> (questions: [SecurityQuestion], selected: String) {
        let pat = #"(?is)<select\b[^>]*\bname\s*=\s*["']securityQuestion["'][^>]*>(.*?)</select>"#
        guard let reg = try? NSRegularExpression(pattern: pat),
              let m = reg.firstMatch(in: formHtml, range: NSRange(location: 0, length: (formHtml as NSString).length)) else {
            return ([], "")
        }
        let inner = (formHtml as NSString).substring(with: m.range(at: 1))
        let opts = parseSelectOptions(in: inner)
        var questions: [SecurityQuestion] = []
        var selected = ""
        for opt in opts where !opt.value.isEmpty || !opt.label.isEmpty {
            questions.append(SecurityQuestion(value: opt.value, label: opt.label))
            if opt.selected {
                selected = opt.value
            }
        }
        if selected.isEmpty, let first = questions.first {
            selected = first.value
        }
        return (questions, selected)
    }

    static func extractErrorMessages(in html: String) -> [String] {
        let pat = #"(?is)<([a-zA-Z0-9]+)\b[^>]*\bclass\s*=\s*["']([^"']*)["'][^>]*>(.*?)</\1>"#
        guard let reg = try? NSRegularExpression(pattern: pat) else { return [] }
        let ns = html as NSString
        var msgs: [String] = []
        for m in reg.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let cls = ns.substring(with: m.range(at: 2)).lowercased()
            let isError = cls.contains("inline_error") || (cls.contains("notification") && cls.contains("error"))
            if isError {
                let text = stripTags(ns.substring(with: m.range(at: 3)))
                if !text.isEmpty {
                    msgs.append(text)
                }
            }
        }
        return msgs
    }
}
