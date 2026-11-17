import Foundation
import CryptoKit

final class NvtlApi {
    static let shared = NvtlApi()

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) InseegoManager/1.0"
    private static let loginPagePaths = ["/login/", "/"]
    private static let knownPaths: [String: [String]] = [
        "wifi_primary_settings": ["/wifi/"],
        "lan": ["/lan/"],
        "set_passcode": ["/adminpassword/"]
    ]
    private static let menuClasses: [String: String] = [
        "wifi_primary_settings": "settings-hotspot-primary",
        "lan": "settings-advanced-lan"
    ]
    private static let secretKeys: Set<String> = [
        "newpasscode", "confirmPasscode".lowercased(), "wifiprimarypassword",
        "securityanswer", "shapassword", "password"
    ]

    static let lteBandsAll: [Int] = [1, 2, 3, 4, 5, 7, 8, 12, 13, 14, 17, 20, 25, 26, 28, 30, 38, 39, 40, 41, 42, 48, 66, 71]
    static let m2000NrNsaBands: [Int] = [1, 3, 28, 41, 77, 78]

    static let vietnamApnPresets: [ApnPreset] = [
        ApnPreset(carrier: "Viettel", apn: "v-internet", user: "", pass: "", auth: 0, mccMncs: ["45204"]),
        ApnPreset(carrier: "MobiFone", apn: "m-wap", user: "mms", pass: "mms", auth: 0, mccMncs: ["45201"]),
        ApnPreset(carrier: "VinaPhone", apn: "m3-world", user: "mms", pass: "mms", auth: 0, mccMncs: ["45202"]),
        ApnPreset(carrier: "Vietnamobile", apn: "internet", user: "", pass: "", auth: 0, mccMncs: ["45205"]),
        ApnPreset(carrier: "Gmobile", apn: "internet", user: "", pass: "", auth: 0, mccMncs: ["45207"]),
        ApnPreset(carrier: "iTel", apn: "e-internet", user: "", pass: "", auth: 0, mccMncs: [])
    ]

    static let profileM2000 = BandProfile(name: "M2000", lteBands: lteBandsAll, nrNsaBands: [], nrSaBands: [])
    static let profileM3000B = BandProfile(
        name: "M3000B",
        lteBands: [1, 2, 3, 4, 5, 7, 8, 12, 13, 14, 17, 18, 19, 20, 25, 26, 28, 38, 39, 40, 41, 46, 48, 66, 71],
        nrNsaBands: [1, 2, 3, 5, 7, 20, 25, 28, 40, 41, 48, 66, 71, 77, 78],
        nrSaBands: [1, 3, 5, 7, 20, 25, 28, 40, 41, 48, 66, 71, 77, 78]
    )
    static let profileM3100 = BandProfile(
        name: "M3100",
        lteBands: [1, 2, 3, 4, 5, 7, 8, 12, 13, 17, 18, 19, 20, 25, 26, 28, 42, 46, 48, 66],
        nrNsaBands: [1, 2, 3, 5, 25, 41, 48, 66, 70, 71, 77, 78],
        nrSaBands: [2, 5, 25, 41, 48, 66, 70, 71, 77, 78, 258, 260, 261]
    )
    static let profileM3200 = BandProfile(
        name: "M3200",
        lteBands: [1, 2, 3, 4, 5, 7, 8, 12, 13, 17, 18, 19, 20, 25, 26, 28, 40, 42, 43, 48, 66],
        nrNsaBands: [2, 5, 25, 41, 48, 66, 70, 71, 77, 78],
        nrSaBands: [2, 5, 25, 41, 48, 66, 70, 71, 77, 78, 258, 260, 261]
    )
    static let profileFx3100 = BandProfile(
        name: "FX3100",
        lteBands: [1, 2, 3, 4, 5, 7, 8, 12, 13, 14, 17, 18, 19, 20, 25, 26, 28, 29, 30, 38, 39, 40, 41, 46, 48, 66, 71],
        nrNsaBands: [1, 2, 3, 5, 7, 12, 25, 26, 38, 41, 48, 66, 71, 77, 78],
        nrSaBands: [2, 5, 7, 12, 25, 26, 38, 41, 48, 66, 71, 77]
    )

    private init() {}

    // MARK: - Validation & Crypto

    func isValidApn(_ apn: String) -> Bool {
        let trimmed = apn.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^[A-Za-z0-9._-]{1,63}$"#, options: .regularExpression) != nil
    }

    func isValidImei(_ imei: String) -> Bool {
        let trimmed = imei.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d{15}$"#, options: .regularExpression) != nil
    }

    func bandProfile(for session: NvtlSession) -> BandProfile {
        let combined = [
            session.deviceName ?? "",
            session.identity?.model ?? "",
            session.identity?.marketingModel ?? "",
            session.identity?.productName ?? ""
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " ")
        .uppercased()

        if combined.contains("FX3100") || combined.contains("FX 3100") { return Self.profileFx3100 }
        if combined.contains("M3000") { return Self.profileM3000B }
        if combined.contains("M3200") { return Self.profileM3200 }
        if combined.contains("M3100") { return Self.profileM3100 }
        return Self.profileM2000
    }

    static func sha1Hex(_ input: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func secretFor(password: String, html: String, secToken: String) -> (secret: String, formula: String) {
        if html.contains("Bcrypt.hashpw") {
            var cost = 10
            if let reg = try? NSRegularExpression(pattern: #"BCRYPT_COST\s*=\s*(\d+)"#),
               let m = reg.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
               let parsed = Int((html as NSString).substring(with: m.range(at: 1))) {
                cost = min(max(parsed, 4), 16)
            }
            let hashed = BCrypt.hashWithSecToken(password: password, secToken: secToken, cost: cost)
            return (hashed, "Bcrypt(cost=\(cost), secToken[0..16])")
        }
        let sha1 = sha1Hex(password + secToken)
        return (sha1, "SHA1(password + secToken[\(secToken.count)])")
    }

    // MARK: - HTTP Transport

    private struct PageResponse {
        var code: Int
        var finalUrl: String
        var html: String
    }

    private struct RawResponse {
        var code: Int
        var finalUrl: String
        var body: String
    }

    private func baseURL(for ip: String) throws -> URL {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: "http://\(trimmed)/") else {
            throw NvtlError.api("Địa chỉ IP không hợp lệ: \(ip)")
        }
        return url
    }

    private func resolveURL(base: URL, pathOrUrl: String) throws -> URL {
        guard let url = URL(string: pathOrUrl, relativeTo: base)?.absoluteURL else {
            throw NvtlError.api("Đường dẫn không hợp lệ: \(pathOrUrl)")
        }
        return url
    }

    private func formEncode(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func maskPairs(_ pairs: [(String, String)]) -> String {
        pairs.map { k, v in
            Self.secretKeys.contains(k.lowercased()) ? "\(k)=***(\(v.count))" : "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private func sanitize(_ text: String?, maxLen: Int = 500) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "(rỗng)"
        }
        let clean = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= maxLen { return clean }
        return String(clean.prefix(maxLen)) + "..."
    }

    private func fetchPage(session: NvtlSession, pathOrUrl: String, timeout: TimeInterval? = nil) async throws -> PageResponse {
        let base = try baseURL(for: session.ip)
        let url = try resolveURL(base: base, pathOrUrl: pathOrUrl)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let timeout { req.timeoutInterval = timeout }
        session.applyCookies(to: &req)

        do {
            let (data, resp) = try await session.normalSession.data(for: req)
            session.captureCookies(from: resp)
            let http = resp as? HTTPURLResponse
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let finalUrl = resp.url?.absoluteString ?? url.absoluteString
            return PageResponse(code: http?.statusCode ?? 0, finalUrl: finalUrl, html: html)
        } catch {
            throw NvtlError.api("Không kết nối được tới \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    private func postForm(
        session: NvtlSession,
        url: URL,
        pairs: [(String, String)],
        xmlHttpRequest: Bool = true,
        referer: URL? = nil,
        quiet: Bool = false,
        useLongTimeout: Bool = false
    ) async throws -> RawResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = formEncode(pairs)
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if xmlHttpRequest {
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        let base = try baseURL(for: session.ip)
        if let scheme = base.scheme, let host = base.host {
            let portPart = base.port.map { ":\($0)" } ?? ""
            req.setValue("\(scheme)://\(host)\(portPart)", forHTTPHeaderField: "Origin")
        }
        if let referer {
            req.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        session.applyCookies(to: &req)

        let client = useLongTimeout ? session.longSession : session.normalSession
        do {
            let (data, resp) = try await client.data(for: req)
            session.captureCookies(from: resp)
            let http = resp as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let finalUrl = resp.url?.absoluteString ?? url.absoluteString
            if !quiet {
                DebugLog.shared.add("POST \(url.path) -> \(code)",
                                    "Cookie: \(session.cookieDebugSummary)\nBody gửi: \(maskPairs(pairs))\nPhản hồi: \(sanitize(body))")
            }
            return RawResponse(code: code, finalUrl: finalUrl, body: body)
        } catch {
            if !quiet {
                DebugLog.shared.add("POST \(url.path) -> Lỗi", error.localizedDescription)
            }
            throw NvtlError.api("Lỗi kết nối khi gửi tới \(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Token & JSON Helpers

    private func loginSecToken(in html: String) -> String? {
        guard let reg = try? NSRegularExpression(pattern: #"var\s+secToken\s*=\s*["']([^"']*)["']"#) else {
            return nil
        }
        let ns = html as NSString
        let matches = reg.matches(in: html, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return nil }
        if matches.count == 1 { return ns.substring(with: matches[0].range(at: 1)) }

        var anchor = ns.range(of: "Bcrypt.hashpw").location
        if anchor == NSNotFound { anchor = ns.range(of: "shaPassword").location }
        if anchor != NSNotFound {
            for m in matches.reversed() where m.range.location < anchor {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return ns.substring(with: matches[0].range(at: 1))
    }

    private func secureToken(in html: String) -> String? {
        if let reg = try? NSRegularExpression(pattern: #"gSecureToken\s*[:=]\s*["']([^"']+)["']"#),
           let m = reg.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) {
            let val = (html as NSString).substring(with: m.range(at: 1))
            if !val.isEmpty { return val }
        }
        if let reg = try? NSRegularExpression(pattern: #"(?is)<input\b([^>]*\bname\s*=\s*["']gSecureToken["'][^>]*)>"#),
           let m = reg.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) {
            let attrs = (html as NSString).substring(with: m.range(at: 1))
            if let val = HtmlFormParser.attribute("value", in: attrs), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val
            }
        }
        return nil
    }

    private func findAjaxUrl(in html: String, contextPattern: String) -> String? {
        guard let ajaxReg = try? NSRegularExpression(pattern: #"(?:\burl\s*:|\bvar\s+url\s*=)\s*["']([^"']+)["']"#),
              let ctxReg = try? NSRegularExpression(pattern: contextPattern) else {
            return nil
        }
        let ns = html as NSString
        for m in ajaxReg.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let end = m.range.location + m.range.length
            let start = max(0, m.range.location - 250)
            let winEnd = min(ns.length, end + 600)
            let window = ns.substring(with: NSRange(location: start, length: winEnd - start))
            if ctxReg.firstMatch(in: window, range: NSRange(location: 0, length: (window as NSString).length)) != nil {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }

    private func jsonObject(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func boolVal(_ dict: [String: Any], _ key: String) -> Bool? {
        guard let v = dict[key], !(v is NSNull) else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.intValue != 0 }
        if let s = v as? String {
            let low = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if low == "true" { return true }
            if low == "false" { return false }
            if let i = Int(low) { return i != 0 }
        }
        return nil
    }

    private func intVal(_ dict: [String: Any], _ key: String) -> Int? {
        guard let v = dict[key], !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func int64Val(_ dict: [String: Any], _ key: String, default def: Int64 = 0) -> Int64 {
        guard let v = dict[key], !(v is NSNull) else { return def }
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String, let parsed = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return parsed }
        return def
    }

    private func doubleVal(_ dict: [String: Any], _ key: String) -> Double? {
        guard let v = dict[key], !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func strVal(_ dict: [String: Any], _ key: String, default def: String = "") -> String {
        guard let v = dict[key], !(v is NSNull) else { return def }
        if let s = v as? String { return s }
        return "\(v)"
    }

    // MARK: - Probe & Login

    func probe(ip: String) async -> Bool {
        let probeSession = NvtlSession(ip: ip, userAgent: Self.userAgent)
        for path in Self.loginPagePaths {
            if let page = try? await fetchPage(session: probeSession, pathOrUrl: path, timeout: 4),
               (200..<400).contains(page.code) {
                if loginSecToken(in: page.html) != nil ||
                    page.html.contains("gSecureToken") ||
                    HtmlFormParser.hasLoginForm(page.html) ||
                    page.html.localizedCaseInsensitiveContains("Inseego") ||
                    page.html.localizedCaseInsensitiveContains("MiFi") {
                    return true
                }
            }
        }
        return false
    }

    func login(ip: String, password: String) async throws -> NvtlSession {
        let session = NvtlSession(ip: ip, userAgent: Self.userAgent)
        var loginPage: PageResponse?
        var secToken: String?

        for path in Self.loginPagePaths {
            let page = try await fetchPage(session: session, pathOrUrl: path)
            if let tok = loginSecToken(in: page.html), !tok.isEmpty {
                loginPage = page
                secToken = tok
                break
            }
            if loginPage == nil { loginPage = page }
        }

        guard let loginPage, let secToken else {
            throw NvtlError.api("Không tìm thấy trang đăng nhập hoặc secToken trên thiết bị.")
        }
        guard let gToken = secureToken(in: loginPage.html) else {
            throw NvtlError.api("Không tìm thấy gSecureToken trên trang đăng nhập.")
        }

        let (secret, formula) = Self.secretFor(password: password, html: loginPage.html, secToken: secToken)
        DebugLog.shared.add("Đăng nhập", "Công thức: \(formula) | Cookie: \(session.cookieDebugSummary) | gToken: \(gToken.prefix(8))...")

        let candidates = await loginSubmitCandidates(session: session, loginPage: loginPage)
        guard let loginUrl = URL(string: loginPage.finalUrl) else {
            throw NvtlError.api("URL đăng nhập không hợp lệ.")
        }

        var lastResp: RawResponse?
        for cand in candidates {
            guard let submitUrl = URL(string: cand, relativeTo: loginUrl)?.absoluteURL else { continue }
            let resp = try await postForm(
                session: session,
                url: submitUrl,
                pairs: [("shaPassword", secret), ("gSecureToken", gToken)],
                xmlHttpRequest: true,
                referer: loginUrl
            )
            lastResp = resp

            if resp.code == 500 && resp.body.localizedCaseInsensitiveContains("noOfRemainingLoginAttempts") {
                throw NvtlError.wrongPassword(nil)
            }

            if (200..<300).contains(resp.code) {
                if let passReg = try? NSRegularExpression(pattern: #"if\s*\(\s*url\s*==\s*"([^"]+)""#),
                   let pm = passReg.firstMatch(in: loginPage.html, range: NSRange(location: 0, length: (loginPage.html as NSString).length)) {
                    session.discovered["set_passcode"] = (loginPage.html as NSString).substring(with: pm.range(at: 1))
                }

                var redir = "/"
                if let rReg = try? NSRegularExpression(pattern: #"(?is)<input\b([^>]*\bid\s*=\s*["']gRedirectUrl["'][^>]*)>"#),
                   let rm = rReg.firstMatch(in: loginPage.html, range: NSRange(location: 0, length: (loginPage.html as NSString).length)) {
                    let attrs = (loginPage.html as NSString).substring(with: rm.range(at: 1))
                    if let v = HtmlFormParser.attribute("value", in: attrs), !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        redir = v
                    }
                }

                if let home = try? await fetchPage(session: session, pathOrUrl: redir) {
                    if let pn = HtmlFormParser.productName(in: home.html) {
                        session.deviceName = pn
                    }
                    for (key, cls) in Self.menuClasses {
                        if let href = HtmlFormParser.findAnchorHref(withClass: cls, in: home.html) {
                            session.appPaths[key] = href
                        }
                    }
                }
                return session
            }
        }

        if lastResp?.code == 500 {
            throw NvtlError.wrongPassword(nil)
        }
        throw NvtlError.api("Đăng nhập thất bại (HTTP \(lastResp?.code ?? 0)).")
    }

    private func loginSubmitCandidates(session: NvtlSession, loginPage: PageResponse) async -> [String] {
        var result: [String] = []
        func addUnique(_ path: String?) {
            guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.contains(path) else { return }
            result.append(path)
        }

        let html = loginPage.html
        let ns = html as NSString
        var uriKey: String?

        if let getUriReg = try? NSRegularExpression(pattern: #"url\s*:\s*GET_URI\(\s*["']([A-Za-z0-9_]+)["']\s*\)"#) {
            let matches = getUriReg.matches(in: html, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                let start = max(0, m.range.location - 200)
                let end = min(ns.length, m.range.location + m.range.length + 300)
                let slice = ns.substring(with: NSRange(location: start, length: end - start))
                if slice.contains("shaPassword") {
                    uriKey = ns.substring(with: m.range(at: 1))
                    break
                }
            }
            if uriKey == nil, let first = matches.first {
                uriKey = ns.substring(with: first.range(at: 1))
            }
        }

        if let uriKey, !uriKey.isEmpty {
            let escapedKey = NSRegularExpression.escapedPattern(for: uriKey)
            let pat = "[\"']?\(escapedKey)[\"']?\\s*[:=,]\\s*[\"'](/[^\"'\\s]*)[\"']"
            func resolveInText(_ text: String) -> String? {
                guard let reg = try? NSRegularExpression(pattern: pat),
                      let m = reg.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
                    return nil
                }
                return (text as NSString).substring(with: m.range(at: 1))
            }

            addUnique(resolveInText(html))

            if let loginUrl = URL(string: loginPage.finalUrl),
               let scriptReg = try? NSRegularExpression(pattern: #"(?i)<script[^>]+src\s*=\s*["']([^"']+)["']"#) {
                for m in scriptReg.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                    let src = ns.substring(with: m.range(at: 1))
                    if let jsUrl = URL(string: src, relativeTo: loginUrl)?.absoluteURL,
                       jsUrl.host?.caseInsensitiveCompare(loginUrl.host ?? "") == .orderedSame,
                       let (data, resp) = try? await session.normalSession.data(from: jsUrl),
                       let http = resp as? HTTPURLResponse,
                       (200..<300).contains(http.statusCode),
                       let jsText = String(data: data, encoding: .utf8) {
                        addUnique(resolveInText(jsText))
                    }
                }
            }
        }

        addUnique("/submitLogin/")
        addUnique("/submit_login/")
        addUnique("/submitLogin")
        return result
    }

    // MARK: - CGI Calls

    private func callCgi(
        session: NvtlSession,
        cgiName: String,
        params: [(String, String)],
        quiet: Bool = false,
        useLongTimeout: Bool = false
    ) async throws -> [String: Any] {
        let base = try baseURL(for: session.ip)
        let url = try resolveURL(base: base, pathOrUrl: "/cgi/\(cgiName)")
        let raw = try await postForm(
            session: session,
            url: url,
            pairs: params,
            xmlHttpRequest: true,
            referer: base,
            quiet: quiet,
            useLongTimeout: useLongTimeout
        )

        if raw.code == 401 || raw.code == 403 {
            throw NvtlError.sessionExpired
        }
        guard (200..<300).contains(raw.code) else {
            throw NvtlError.api("Lỗi CGI \(cgiName): HTTP \(raw.code)")
        }
        guard let root = jsonObject(raw.body) else {
            throw NvtlError.api("CGI \(cgiName) trả dữ liệu không hợp lệ.")
        }

        let err = strVal(root, "error")
        let failed = strVal(root, "failed")
        if let ok = boolVal(root, "ok"), !ok {
            let msg = !err.isEmpty ? err : failed
            throw NvtlError.api(msg.isEmpty ? "Lệnh \(cgiName) thất bại." : msg)
        }
        if !err.isEmpty || !failed.isEmpty {
            throw NvtlError.api(!err.isEmpty ? err : failed)
        }
        return root
    }

    // MARK: - Telemetry & Info

    func getRadio5gEnabled(session: NvtlSession) async throws -> Bool? {
        do {
            let r = try await callCgi(session: session, cgiName: "powermode.cgi", params: [("action", "get")], quiet: true)
            switch intVal(r, "radio_enabled") {
            case 1: return true
            case 0: return false
            default: return nil
            }
        } catch NvtlError.sessionExpired {
            throw NvtlError.sessionExpired
        } catch {
            return nil
        }
    }

    func setPowerMode(session: NvtlSession, mode: PowerMode) async throws {
        _ = try await callCgi(session: session, cgiName: "powermode.cgi", params: [("action", "set_mode"), ("mode", mode.rawValue)])
    }

    func getSignal(session: NvtlSession) async throws -> SignalInfo {
        let r = try await callCgi(session: session, cgiName: "signalstat.cgi", params: [("action", "get")], quiet: true)
        var oper = strVal(r, "oper")
        if oper == "?" { oper = "" }
        var cell = strVal(r, "cell")
        if cell == "0" { cell = "" }
        var batt = intVal(r, "batt")
        if let b = batt, (b < 0 || b > 100) { batt = nil }
        return SignalInfo(
            tech: strVal(r, "tech"),
            band: strVal(r, "band"),
            ca: intVal(r, "ca") == 1,
            carrier: oper,
            bars: intVal(r, "bars"),
            rssi: intVal(r, "rssi"),
            rsrp: intVal(r, "rsrp"),
            rsrq: intVal(r, "rsrq"),
            snr: intVal(r, "snr"),
            cellId: cell,
            battery: batt
        )
    }

    func getNrInfo(session: NvtlSession) async throws -> NrInfo {
        let r = try await callCgi(session: session, cgiName: "5gstat.cgi", params: [("action", "get")], quiet: true)
        let radioInt = intVal(r, "radio_enabled")
        let radioEnabled: Bool? = radioInt == 1 ? true : (radioInt == 0 ? false : nil)
        var mode = strVal(r, "mode")
        if mode.caseInsensitiveCompare("unknown") == .orderedSame || mode.count > 16 { mode = "" }
        return NrInfo(
            radioEnabled: radioEnabled,
            serviceAvailable: intVal(r, "service_available") == 1,
            dataConnected: intVal(r, "data_connected") == 1,
            band: strVal(r, "band"),
            activeBand: strVal(r, "active_band"),
            endc: intVal(r, "endc") == 1,
            pci: strVal(r, "pci"),
            mode: mode,
            bars: intVal(r, "bars"),
            rsrp: intVal(r, "rsrp"),
            rsrq: intVal(r, "rsrq"),
            snr: intVal(r, "snr"),
            disableMode: intVal(r, "disable_mode")
        )
    }

    func set5gRadio(session: NvtlSession, enabled: Bool) async throws {
        _ = try await callCgi(session: session, cgiName: "5gstat.cgi", params: [("action", "setradio"), ("val", enabled ? "1" : "0")])
    }

    func set5gMode(session: NvtlSession, disableMode: Int) async throws {
        guard (0...2).contains(disableMode) else {
            throw NvtlError.api("Chế độ 5G không hợp lệ (chỉ 0, 1 hoặc 2).")
        }
        _ = try await callCgi(session: session, cgiName: "5gstat.cgi", params: [("action", "setmode"), ("val", "\(disableMode)")])
    }

    func getTemperature(session: NvtlSession) async throws -> TempInfo {
        let r = try await callCgi(session: session, cgiName: "temp.cgi", params: [("action", "get")], quiet: true)
        return TempInfo(
            device: readTemp(r["device"] as? [String: Any]),
            battery: readTemp(r["battery"] as? [String: Any])
        )
    }

    private func readTemp(_ dict: [String: Any]?) -> TempReading {
        guard let dict else { return TempReading() }
        var state = strVal(dict, "state", default: "normal")
        if state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state = "normal" }
        return TempReading(
            tempC: doubleVal(dict, "tempC"),
            warnC: doubleVal(dict, "warnC"),
            hotC: doubleVal(dict, "hotC"),
            monitorEnabled: boolVal(dict, "monitorEnabled") ?? false,
            state: state
        )
    }

    func getDataUsage(session: NvtlSession) async throws -> DataUsage {
        let r = try await callCgi(session: session, cgiName: "datausage.cgi", params: [("action", "get")], quiet: true)
        let avail = boolVal(r, "available") ?? true
        return DataUsage(available: avail, todayBytes: int64Val(r, "todayBytes"), date: strVal(r, "date"))
    }

    func getDeviceIdentity(session: NvtlSession) async throws -> DeviceIdentity {
        if let cached = session.identity { return cached }

        var productName = session.deviceName ?? ""
        var links: [(href: String, meta: String)] = []

        do {
            let home = try await fetchPage(session: session, pathOrUrl: "/")
            if home.code == 401 || HtmlFormParser.hasLoginForm(home.html) {
                throw NvtlError.sessionExpired
            }
            if let pn = HtmlFormParser.productName(in: home.html) {
                productName = pn
            }
            links = HtmlFormParser.anchorLinks(in: home.html)
        } catch NvtlError.sessionExpired {
            throw NvtlError.sessionExpired
        } catch {
            // continue
        }

        var candidates: [String] = []
        func addCand(_ p: String?) {
            guard let p, !p.isEmpty, !candidates.contains(p) else { return }
            candidates.append(p)
        }
        addCand(session.discovered["device_info"])
        addCand("/mifiinfo/")
        addCand("/device_info/")
        addCand("/deviceinfo/")

        let unsafePattern = #"logout|signout|shutdown|restart|reboot|reset|factory|backup|restore|update|install|delete|remove|upload|sideload"#
        let infoPattern = #"info|device|about|mifi|thiet|thông|status"#
        for link in links {
            let combined = "\(link.href) \(link.meta)"
            if combined.range(of: unsafePattern, options: [.regularExpression, .caseInsensitive]) == nil &&
                combined.range(of: infoPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                addCand(link.href)
            }
        }

        for path in candidates {
            do {
                let p = try await fetchPage(session: session, pathOrUrl: path)
                if p.code == 401 || HtmlFormParser.hasLoginForm(p.html) {
                    throw NvtlError.sessionExpired
                }
                guard (200..<300).contains(p.code) else { continue }

                let model = HtmlFormParser.elementTextOrValue(id: "model", in: p.html)
                let mfg = HtmlFormParser.elementTextOrValue(id: "manufacturer", in: p.html)
                let imei = HtmlFormParser.elementTextOrValue(id: "imei", in: p.html)
                let radioTech = HtmlFormParser.elementTextOrValue(id: "radioTech", in: p.html)
                let hw = HtmlFormParser.elementTextOrValue(id: "hwVersion", in: p.html)
                let os = HtmlFormParser.elementTextOrValue(id: "osVersion", in: p.html)
                let app = HtmlFormParser.elementTextOrValue(id: "appVersion", in: p.html)
                let webUi = HtmlFormParser.elementTextOrValue(id: "webUiVersion", in: p.html)
                let modem = HtmlFormParser.elementTextOrValue(id: "modemVersion", in: p.html)
                let marketing = HtmlFormParser.elementTextOrValue(id: "marketingModel", in: p.html)
                if let pn = HtmlFormParser.productName(in: p.html) {
                    productName = pn
                }

                if !model.isEmpty || !imei.isEmpty || !mfg.isEmpty || !productName.isEmpty {
                    session.discovered["device_info"] = path
                    let id = DeviceIdentity(
                        productName: productName,
                        manufacturer: mfg,
                        model: model,
                        marketingModel: marketing,
                        radioTech: radioTech,
                        imei: imei,
                        hwVersion: hw,
                        osVersion: os,
                        appVersion: app,
                        webUiVersion: webUi,
                        modemVersion: modem
                    )
                    session.identity = id
                    if let disp = id.displayName { session.deviceName = disp }
                    return id
                }
            } catch NvtlError.sessionExpired {
                throw NvtlError.sessionExpired
            } catch {
                // try next
            }
        }

        let fallback = DeviceIdentity(productName: productName)
        session.identity = fallback
        return fallback
    }

    // MARK: - Band Locking, IMEI, TTL, APN & Power Actions

    static func parseBandCsv(_ csv: String?) -> Set<Int> {
        guard let csv, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var out = Set<Int>()
        for part in csv.split(separator: ",") {
            if let b = Int(part.trimmingCharacters(in: .whitespacesAndNewlines)), b > 0 {
                out.insert(b)
            }
        }
        return out
    }

    func getEnabledLteBands(session: NvtlSession) async throws -> Set<Int> {
        let r = try await callCgi(session: session, cgiName: "bandset.cgi", params: [("action", "getmask")], useLongTimeout: true)
        return Self.parseBandCsv(strVal(r, "bands"))
    }

    func setEnabledLteBands(session: NvtlSession, bands: Set<Int>) async throws {
        let valid = bands.filter { $0 > 0 && $0 < 301 }.sorted()
        guard !valid.isEmpty else {
            throw NvtlError.api("Phải bật ít nhất một băng LTE.")
        }
        let csv = valid.map(String.init).joined(separator: ",")
        _ = try await callCgi(session: session, cgiName: "bandset.cgi", params: [("action", "set"), ("bands", csv)], useLongTimeout: true)
    }

    func getNrBands(session: NvtlSession) async throws -> NrBands? {
        let base = try baseURL(for: session.ip)
        let url = try resolveURL(base: base, pathOrUrl: "/cgi/nr5gband.cgi")
        let raw = try await postForm(session: session, url: url, pairs: [("action", "get")], xmlHttpRequest: true, referer: base, useLongTimeout: true)
        if raw.code == 401 || raw.code == 403 { throw NvtlError.sessionExpired }

        if (200..<300).contains(raw.code), let r = jsonObject(raw.body), boolVal(r, "ok") == true {
            if r["nsa"] != nil || r["sa"] != nil {
                let nsaStr = strVal(r, "nsa")
                return NrBands(nsa: Self.parseBandCsv(nsaStr), sa: Self.parseBandCsv(strVal(r, "sa")), isMaskMode: false, rawBands: nsaStr)
            }
            if r["bands"] != nil {
                let bandsStr = strVal(r, "bands")
                return NrBands(nsa: Self.parseBandCsv(bandsStr), sa: [], isMaskMode: true, rawBands: bandsStr)
            }
        } else if raw.code == 404 {
            return nil
        }

        let maskRaw = try await postForm(session: session, url: url, pairs: [("action", "getmask")], xmlHttpRequest: true, referer: base, useLongTimeout: true)
        if maskRaw.code == 401 || maskRaw.code == 403 { throw NvtlError.sessionExpired }
        guard (200..<300).contains(maskRaw.code), let mr = jsonObject(maskRaw.body), boolVal(mr, "ok") == true else {
            return nil
        }
        let rawBands = strVal(mr, "bands")
        return NrBands(nsa: Self.parseBandCsv(rawBands), sa: [], isMaskMode: true, rawBands: rawBands)
    }

    func setNrBands(session: NvtlSession, sa: Bool, bands: Set<Int>, isMaskMode: Bool) async throws -> NrBandSaveResult {
        guard !bands.isEmpty else {
            throw NvtlError.api("Phải bật ít nhất một băng 5G NR.")
        }
        let csv = bands.sorted().map(String.init).joined(separator: ",")
        let payload: [(String, String)] = isMaskMode
            ? [("action", "set"), ("bands", csv)]
            : [("action", "set"), ("mode", sa ? "sa" : "nsa"), ("bands", csv)]
        let r = try await callCgi(session: session, cgiName: "nr5gband.cgi", params: payload, useLongTimeout: true)
        let rawList = strVal(r, "bands")
        let doneStr = strVal(r, "done")
        var parsed = Self.parseBandCsv(!rawList.isEmpty ? rawList : doneStr)
        if parsed.isEmpty { parsed = bands }
        let needsReboot = boolVal(r, "needs_reboot") ?? false
        return NrBandSaveResult(bands: parsed, needsReboot: needsReboot, doneText: doneStr.isEmpty ? rawList : doneStr)
    }

    func restoreNrBands(session: NvtlSession) async throws -> NrBandSaveResult {
        let r = try await callCgi(session: session, cgiName: "nr5gband.cgi", params: [("action", "restore")], useLongTimeout: true)
        let rawList = strVal(r, "bands")
        let doneStr = strVal(r, "done")
        let parsed = Self.parseBandCsv(!rawList.isEmpty ? rawList : doneStr)
        let needsReboot = boolVal(r, "needs_reboot") ?? false
        return NrBandSaveResult(bands: parsed, needsReboot: needsReboot, doneText: doneStr.isEmpty ? rawList : doneStr)
    }

    func getImei(session: NvtlSession) async throws -> ImeiInfo {
        let r = try await callCgi(session: session, cgiName: "imei.cgi", params: [("action", "get")])
        return ImeiInfo(imei: strVal(r, "imei"), orig: strVal(r, "orig"))
    }

    func setImei(session: NvtlSession, imei: String) async throws -> ImeiWriteResult {
        guard isValidImei(imei) else { throw NvtlError.api("IMEI phải gồm đúng 15 chữ số.") }
        let r = try await callCgi(session: session, cgiName: "imei.cgi", params: [("action", "set"), ("value", imei.trimmingCharacters(in: .whitespacesAndNewlines))], useLongTimeout: true)
        return ImeiWriteResult(oldImei: strVal(r, "old_imei"), newImei: strVal(r, "new_imei"), verified: boolVal(r, "verified") ?? false)
    }

    func restoreImei(session: NvtlSession) async throws -> ImeiWriteResult {
        let r = try await callCgi(session: session, cgiName: "imei.cgi", params: [("action", "restore")], useLongTimeout: true)
        return ImeiWriteResult(oldImei: strVal(r, "old_imei"), newImei: strVal(r, "new_imei"), verified: boolVal(r, "verified") ?? false)
    }

    func getTtl(session: NvtlSession) async throws -> TtlInfo {
        let r = try await callCgi(session: session, cgiName: "ttl.cgi", params: [("action", "get")])
        var ttl = intVal(r, "ttl")
        if let t = ttl, (t < 1 || t > 255) { ttl = nil }
        return TtlInfo(active: boolVal(r, "active") ?? false, ttl: ttl)
    }

    func setTtl(session: NvtlSession, ttl: Int) async throws -> TtlInfo {
        guard (1...255).contains(ttl) else { throw NvtlError.api("TTL phải là số từ 1 đến 255.") }
        _ = try await callCgi(session: session, cgiName: "ttl.cgi", params: [("action", "set"), ("value", "\(ttl)")])
        return try await getTtl(session: session)
    }

    func resetTtl(session: NvtlSession) async throws -> TtlInfo {
        _ = try await callCgi(session: session, cgiName: "ttl.cgi", params: [("action", "reset")])
        return try await getTtl(session: session)
    }

    func getApn(session: NvtlSession) async throws -> ApnInfo {
        let r = try await callCgi(session: session, cgiName: "apn.cgi", params: [("action", "get")])
        var apn = strVal(r, "apn")
        if apn.caseInsensitiveCompare("unknown") == .orderedSame { apn = "" }
        return ApnInfo(apn: apn, carrier: strVal(r, "oper"), mccMnc: strVal(r, "mccmnc"))
    }

    func setApn(session: NvtlSession, apn: String) async throws -> ApnInfo {
        guard isValidApn(apn) else { throw NvtlError.api("APN chỉ gồm chữ, số, dấu chấm, gạch ngang, gạch dưới.") }
        _ = try await callCgi(session: session, cgiName: "apn.cgi", params: [("action", "set"), ("apn", apn.trimmingCharacters(in: .whitespacesAndNewlines))])
        return try await getApn(session: session)
    }

    func powerAction(session: NvtlSession, action: PowerAction) async throws -> String {
        let path = action == .restart ? "/restarting/" : "/shutdown/"
        let doPath = action == .restart ? "reboot" : "doshutdown"
        let resultKey = action == .restart ? "rebooting" : "shutdown"
        let label = action == .restart ? "Khởi động lại" : "Tắt máy"

        let page = try await fetchPage(session: session, pathOrUrl: path)
        if page.code == 401 || HtmlFormParser.hasLoginForm(page.html) {
            throw NvtlError.sessionExpired
        }
        guard (200..<300).contains(page.code) else {
            throw NvtlError.api("Không mở được trang \(path) (HTTP \(page.code)).")
        }
        guard let gToken = secureToken(in: page.html) else {
            throw NvtlError.api("Không tìm thấy gSecureToken trên trang \(path).")
        }

        let cleanDo = doPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var relUrl = doPath
        if let reg = try? NSRegularExpression(pattern: "url\\s*:\\s*[\"']([^\"']*\(NSRegularExpression.escapedPattern(for: cleanDo))[^\"']*)[\"']"),
           let m = reg.firstMatch(in: page.html, range: NSRange(location: 0, length: (page.html as NSString).length)) {
            relUrl = (page.html as NSString).substring(with: m.range(at: 1))
        }

        guard let pageUrl = URL(string: page.finalUrl),
              let submitUrl = URL(string: relUrl, relativeTo: pageUrl)?.absoluteURL else {
            throw NvtlError.api("Địa chỉ lệnh không hợp lệ: \(relUrl)")
        }

        do {
            let raw = try await postForm(session: session, url: submitUrl, pairs: [("gSecureToken", gToken)], xmlHttpRequest: true, referer: pageUrl)
            if raw.code == 401 { throw NvtlError.sessionExpired }
            guard (200..<300).contains(raw.code) else {
                throw NvtlError.api("Máy trả lỗi HTTP \(raw.code).")
            }
            if let doc = jsonObject(raw.body), boolVal(doc, resultKey) == true {
                return sentMessage(action)
            }
            throw NvtlError.api("Máy không xác nhận lệnh \(label.lowercased()).")
        } catch NvtlError.api(let msg) where msg.localizedCaseInsensitiveContains("Lỗi kết nối") {
            DebugLog.shared.add("\(label): kết quả", "Máy ngắt kết nối ngay sau khi nhận lệnh (bình thường).")
            return sentMessage(action)
        }
    }

    private func sentMessage(_ action: PowerAction) -> String {
        action == .restart
            ? "Đã gửi lệnh khởi động lại. Thiết bị sẽ mất kết nối 1-2 phút rồi tự bật lại."
            : "Đã gửi lệnh tắt nguồn. Thiết bị sẽ tắt hẳn."
    }

    // MARK: - Settings Forms (Wi-Fi, LAN IP, Admin Password)

    private func openAppForm(session: NvtlSession, key: String, formId: String) async throws -> (PageResponse, HtmlFormParser.ParsedForm) {
        var candidates: [String] = []
        func addCand(_ p: String?) {
            guard let p, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !candidates.contains(p) else { return }
            candidates.append(p)
        }
        addCand(session.appPaths[key])
        Self.knownPaths[key]?.forEach { addCand($0) }
        addCand(session.discovered[key])
        addCand("/\(key)/")

        for path in candidates {
            let page = try await fetchPage(session: session, pathOrUrl: path)
            if page.code == 401 || HtmlFormParser.hasLoginForm(page.html) {
                throw NvtlError.sessionExpired
            }
            if (200..<300).contains(page.code), let form = HtmlFormParser.extractForm(idOrName: formId, in: page.html) {
                session.discovered[key] = path
                return (page, form)
            }
        }
        throw NvtlError.api("Không mở được form cài đặt (\(key)).")
    }

    private func getField(_ pairs: [(String, String)], _ key: String) -> String? {
        pairs.first(where: { $0.0 == key })?.1
    }

    private func setField(_ pairs: inout [(String, String)], _ key: String, _ value: String) {
        if let idx = pairs.firstIndex(where: { $0.0 == key }) {
            pairs[idx] = (key, value)
        } else {
            pairs.append((key, value))
        }
    }

    private func submitSettingsForm(
        session: NvtlSession,
        actionUrl: URL,
        pairs: [(String, String)],
        refererUrl: URL
    ) async throws -> SaveResult {
        do {
            let raw = try await postForm(session: session, url: actionUrl, pairs: pairs, xmlHttpRequest: false, referer: refererUrl)
            if raw.code == 401 || HtmlFormParser.hasLoginForm(raw.body) {
                throw NvtlError.sessionExpired
            }
            let errs = HtmlFormParser.extractErrorMessages(in: raw.body)
            if !errs.isEmpty {
                throw NvtlError.api(errs.joined(separator: "; "))
            }
            if (200..<300).contains(raw.code) {
                return .confirmed
            }
            throw NvtlError.api("Máy trả lỗi HTTP \(raw.code).")
        } catch NvtlError.api(let msg) where msg.localizedCaseInsensitiveContains("Lỗi kết nối") {
            return .sentConnectionLost
        }
    }

    func getWifiInfo(session: NvtlSession) async throws -> WifiInfo {
        let (_, form) = try await openAppForm(session: session, key: "wifi_primary_settings", formId: "wifi_primary_settings_form")
        let ssid = getField(form.pairs, "WifiPrimarySsid") ?? ""
        let sec = getField(form.pairs, "WifiPrimarySecurity") ?? ""
        return WifiInfo(ssid: ssid, isOpen: sec == "0")
    }

    func setWifi(session: NvtlSession, newSsid: String, newPassword: String?) async throws -> SaveResult {
        let (page, form) = try await openAppForm(session: session, key: "wifi_primary_settings", formId: "wifi_primary_settings_form")
        var pairs = form.pairs
        setField(&pairs, "WifiPrimarySsid", newSsid)
        if let newPassword, !newPassword.isEmpty {
            setField(&pairs, "WifiPrimaryPassword", newPassword)
        } else {
            pairs.removeAll { $0.0 == "WifiPrimaryPassword" }
        }
        guard let pageUrl = URL(string: page.finalUrl),
              let actionUrl = form.action.isEmpty ? pageUrl : URL(string: form.action, relativeTo: pageUrl)?.absoluteURL else {
            throw NvtlError.api("Action form Wi-Fi không hợp lệ.")
        }
        return try await submitSettingsForm(session: session, actionUrl: actionUrl, pairs: pairs, refererUrl: pageUrl)
    }

    func getLanInfo(session: NvtlSession) async throws -> LanInfo {
        let (_, form) = try await openAppForm(session: session, key: "lan", formId: "adv_lan_form")
        return LanInfo(
            ip: getField(form.pairs, "ipAddress") ?? session.ip,
            subnetMask: getField(form.pairs, "subnetMask") ?? ""
        )
    }

    func setLanIp(session: NvtlSession, newIp: String) async throws -> SaveResult {
        let (page, form) = try await openAppForm(session: session, key: "lan", formId: "adv_lan_form")
        var pairs = form.pairs

        guard getField(pairs, "ipAddress") != nil else {
            throw NvtlError.api("Trang LAN không có trường IP.")
        }
        if form.rawHtml.range(of: #"(?is)<input\b[^>]*\bname\s*=\s*["']ipAddress["'][^>]*\btype\s*=\s*["']hidden["']"#, options: .regularExpression) != nil {
            throw NvtlError.api("Máy đang để IP LAN ở chế độ chỉ đọc.")
        }
        if getField(pairs, "isIpPassthroughActive") == "on" {
            throw NvtlError.api("Đang bật IP Passthrough - hãy tắt trên WebUI trước khi đổi IP LAN.")
        }

        let subnetMask = getField(pairs, "subnetMask") ?? ""
        setField(&pairs, "ipAddress", newIp)

        if subnetMask == "255.255.255.0", let dotIdx = newIp.lastIndex(of: ".") {
            let prefix = String(newIp[..<dotIdx])
            let lastPart = String(newIp[newIp.index(after: dotIdx)...])
            if let lastOctet = Int(lastPart),
               let bStr = getField(pairs, "dhcpRangeBegin"),
               let eStr = getField(pairs, "dhcpRangeEnd"),
               let bOctet = bStr.split(separator: ".").last.flatMap({ Int($0) }),
               let eOctet = eStr.split(separator: ".").last.flatMap({ Int($0) }),
               lastOctet >= bOctet && lastOctet <= eOctet {
                throw NvtlError.api("IP mới (.\(lastOctet)) nằm trong dải DHCP (.\(bOctet) - .\(eOctet)). Hãy chọn số cuối khác, ví dụ .1")
            }

            let ipReg = try? NSRegularExpression(pattern: #"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$"#)
            for idx in pairs.indices {
                if pairs[idx].0 == "dhcpRangeBegin" || pairs[idx].0 == "dhcpRangeEnd" {
                    let v = pairs[idx].1
                    if let m = ipReg?.firstMatch(in: v, range: NSRange(location: 0, length: (v as NSString).length)) {
                        let last = (v as NSString).substring(with: m.range(at: 4))
                        pairs[idx] = (pairs[idx].0, "\(prefix).\(last)")
                    }
                }
            }
        }

        guard let pageUrl = URL(string: page.finalUrl),
              let actionUrl = form.action.isEmpty ? pageUrl : URL(string: form.action, relativeTo: pageUrl)?.absoluteURL else {
            throw NvtlError.api("Action form LAN không hợp lệ.")
        }
        let res = try await submitSettingsForm(session: session, actionUrl: actionUrl, pairs: pairs, refererUrl: pageUrl)
        session.ip = newIp
        return res
    }

    func getPasscodeForm(session: NvtlSession) async throws -> PasscodeFormInfo {
        let (_, form) = try await openAppForm(session: session, key: "set_passcode", formId: "setPasscodeForm")
        let extracted = HtmlFormParser.extractSecurityQuestions(in: form.rawHtml)
        return PasscodeFormInfo(questions: extracted.questions, selectedValue: extracted.selected)
    }

    func changeAdminPassword(
        session: NvtlSession,
        currentPassword: String,
        newPassword: String,
        confirmPassword: String,
        securityAnswer: String,
        securityQuestion: String
    ) async throws {
        let (page, _) = try await openAppForm(session: session, key: "set_passcode", formId: "setPasscodeForm")
        guard let secToken = loginSecToken(in: page.html) else {
            throw NvtlError.api("Không tìm thấy secToken trên trang đổi mật khẩu.")
        }
        guard let gToken = secureToken(in: page.html) else {
            throw NvtlError.api("Không tìm thấy gSecureToken trên trang đổi mật khẩu.")
        }
        guard let verifyPath = findAjaxUrl(in: page.html, contextPattern: #"password\s*:\s*shaPass\b"#) else {
            throw NvtlError.api("Không tìm thấy địa chỉ kiểm tra mật khẩu hiện tại.")
        }
        guard let changePath = findAjaxUrl(in: page.html, contextPattern: #"newPasscode"#) else {
            throw NvtlError.api("Không tìm thấy địa chỉ đổi mật khẩu.")
        }
        guard let pageUrl = URL(string: page.finalUrl),
              let verifyUrl = URL(string: verifyPath, relativeTo: pageUrl)?.absoluteURL,
              let changeUrl = URL(string: changePath, relativeTo: pageUrl)?.absoluteURL else {
            throw NvtlError.api("Đường dẫn đổi mật khẩu không hợp lệ.")
        }

        let (secret, formula) = Self.secretFor(password: currentPassword, html: page.html, secToken: secToken)
        DebugLog.shared.add("Đổi mật khẩu", "Công thức: \(formula)")

        let verifyResp = try await postForm(session: session, url: verifyUrl, pairs: [("gSecureToken", gToken), ("password", secret)], xmlHttpRequest: true, referer: pageUrl)
        if verifyResp.code == 500 {
            throw NvtlError.wrongPassword("Mật khẩu quản lý hiện tại không đúng.")
        }
        guard (200..<300).contains(verifyResp.code) else {
            throw NvtlError.api("Lỗi HTTP \(verifyResp.code) khi kiểm tra mật khẩu hiện tại.")
        }

        let changeResp = try await postForm(
            session: session,
            url: changeUrl,
            pairs: [
                ("gSecureToken", gToken),
                ("shaPassword", secret),
                ("newPasscode", newPassword),
                ("confirmPasscode", confirmPassword),
                ("securityAnswer", securityAnswer),
                ("securityQuestion", securityQuestion)
            ],
            xmlHttpRequest: true,
            referer: pageUrl
        )

        if (200..<300).contains(changeResp.code) { return }
        if changeResp.code == 500 {
            if let dict = jsonObject(changeResp.body) {
                let msgs = dict.values.compactMap { v -> String? in
                    let raw = (v as? String) ?? "\(v)"
                    let clean = HtmlFormParser.stripTags(raw)
                    return clean.isEmpty ? nil : clean
                }
                if !msgs.isEmpty {
                    throw NvtlError.api(msgs.joined(separator: "; "))
                }
            }
            throw NvtlError.api("Máy từ chối đổi mật khẩu.")
        }
        throw NvtlError.api("Lỗi HTTP \(changeResp.code) khi đổi mật khẩu.")
    }

    // MARK: - 4G Band Scan, Battery Health, SMS, Boot Mode & Logout

    static func findMatchingApnPreset(mccMnc: String?) -> ApnPreset? {
        guard let mccMnc, !mccMnc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let clean = mccMnc.trimmingCharacters(in: .whitespacesAndNewlines)
        return vietnamApnPresets.first { preset in
            preset.mccMncs.contains { $0.caseInsensitiveCompare(clean) == .orderedSame }
        }
    }

    func startBandScan(session: NvtlSession, band: Int) async throws {
        guard (1...300).contains(band) else { throw NvtlError.api("Băng tần B\(band) không hợp lệ.") }
        _ = try await callCgi(session: session, cgiName: "bandscan.cgi", params: [("action", "start"), ("band", "\(band)")], useLongTimeout: true)
    }

    func pollBandScan(session: NvtlSession) async throws -> BandScanPollResult {
        let r = try await callCgi(session: session, cgiName: "bandscan.cgi", params: [("action", "poll")], quiet: true)
        let running = strVal(r, "status").caseInsensitiveCompare("running") == .orderedSame
        return BandScanPollResult(isRunning: running, found: boolVal(r, "found") ?? false, rsrp: intVal(r, "rsrp"))
    }

    func stopBandScan(session: NvtlSession) async throws {
        _ = try await callCgi(session: session, cgiName: "bandscan.cgi", params: [("action", "restore")], useLongTimeout: true)
    }

    func getBatteryHealth(session: NvtlSession) async throws -> BatteryHealthInfo {
        let r = try await callCgi(session: session, cgiName: "battery.cgi", params: [("action", "get")], quiet: true)
        return parseBatteryHealth(r)
    }

    func setBatteryManualCharge(session: NvtlSession, stopCharging: Bool) async throws -> BatteryHealthInfo {
        let r = try await callCgi(session: session, cgiName: "battery.cgi", params: [("action", stopCharging ? "stop_charging" : "resume_charging")])
        return parseBatteryHealth(r)
    }

    func setBatteryHealthEnabled(session: NvtlSession, enabled: Bool) async throws -> BatteryHealthInfo {
        let r = try await callCgi(session: session, cgiName: "battery.cgi", params: [("action", "set_enabled"), ("value", enabled ? "1" : "0")])
        return parseBatteryHealth(r)
    }

    func activateBatteryHealthNow(session: NvtlSession) async throws -> BatteryHealthInfo {
        let r = try await callCgi(session: session, cgiName: "battery.cgi", params: [("action", "activate_now")])
        return parseBatteryHealth(r)
    }

    func resetBatteryTimer(session: NvtlSession) async throws -> BatteryHealthInfo {
        let r = try await callCgi(session: session, cgiName: "battery.cgi", params: [("action", "reset_timer")])
        return parseBatteryHealth(r)
    }

    func restoreBatteryDefault(session: NvtlSession) async throws -> BatteryHealthInfo {
        let r = try await callCgi(session: session, cgiName: "battery.cgi", params: [("action", "restore_default")])
        return parseBatteryHealth(r)
    }

    func setBatteryCapability(session: NvtlSession, durationSeconds: Int, minPercent: Int, maxPercent: Int) async throws -> BatteryHealthInfo {
        guard durationSeconds >= 1 else { throw NvtlError.api("Thời gian chờ tối thiểu là 1 giây.") }
        guard (1...100).contains(minPercent), (1...100).contains(maxPercent) else {
            throw NvtlError.api("Ngưỡng pin phải nằm trong khoảng 1–100%.")
        }
        guard minPercent < maxPercent else {
            throw NvtlError.api("Ngưỡng sạc lại (Min) phải nhỏ hơn ngưỡng dừng sạc (Max).")
        }
        let r = try await callCgi(
            session: session,
            cgiName: "battery.cgi",
            params: [
                ("action", "set_capability"),
                ("duration", "\(durationSeconds)"),
                ("min", "\(minPercent)"),
                ("max", "\(maxPercent)")
            ]
        )
        return parseBatteryHealth(r)
    }

    private func parseBatteryHealth(_ r: [String: Any]) -> BatteryHealthInfo {
        BatteryHealthInfo(
            enabled: boolVal(r, "enabled") ?? false,
            online: boolVal(r, "online") ?? false,
            capacity: intVal(r, "capacity"),
            elapsedSeconds: int64Val(r, "elapsed", default: 0),
            min: intVal(r, "min") ?? 70,
            max: intVal(r, "max") ?? 80,
            durationSeconds: intVal(r, "duration") ?? 57600,
            manualStop: boolVal(r, "manual_stop") ?? false,
            inputSuspended: boolVal(r, "input_suspended") ?? false,
            note: r["note"] as? String
        )
    }

    static func ucs2Hex(_ text: String) -> String {
        text.utf16.map { String(format: "%04X", $0) }.joined()
    }

    static func formatSmsTime(_ rawTime: String) -> String {
        let trimmed = rawTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let reg = try? NSRegularExpression(pattern: #"^\w+\s+(\w+)\s+(\d{1,2})\s+(\d{1,2}):(\d{2}):\d{2}\s+(\d{4})$"#),
              let m = reg.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return rawTime
        }
        let ns = trimmed as NSString
        let monStr = ns.substring(with: m.range(at: 1)).lowercased()
        let monthMap = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        guard let month = monthMap[monStr],
              let day = Int(ns.substring(with: m.range(at: 2))),
              let hour = Int(ns.substring(with: m.range(at: 3))) else {
            return rawTime
        }
        let min = ns.substring(with: m.range(at: 4))
        let year = ns.substring(with: m.range(at: 5))
        return String(format: "%02d/%02d/%@ %02d:%@", day, month, year, hour, min)
    }

    func getSmsList(session: NvtlSession) async throws -> [SmsMessage] {
        let r = try await callCgi(session: session, cgiName: "sms.cgi", params: [("action", "list")], quiet: true, useLongTimeout: true)
        guard let arr = r["messages"] as? [[String: Any]] else { return [] }
        return arr.map { item in
            SmsMessage(
                id: intVal(item, "id") ?? 0,
                wasUnread: boolVal(item, "wasUnread") ?? false,
                hasDetail: boolVal(item, "hasDetail") ?? false,
                address: strVal(item, "address"),
                time: Self.formatSmsTime(strVal(item, "time")),
                body: strVal(item, "body")
            )
        }
    }

    func readSms(session: NvtlSession, id: Int) async throws -> SmsMessage {
        let r = try await callCgi(session: session, cgiName: "sms.cgi", params: [("action", "read"), ("id", "\(id)")], quiet: true)
        return SmsMessage(
            id: id,
            wasUnread: false,
            hasDetail: true,
            address: strVal(r, "address"),
            time: Self.formatSmsTime(strVal(r, "time")),
            body: strVal(r, "body")
        )
    }

    func deleteSms(session: NvtlSession, id: Int) async throws {
        _ = try await callCgi(session: session, cgiName: "sms.cgi", params: [("action", "delete"), ("id", "\(id)")])
    }

    func sendSms(session: NvtlSession, number: String, body: String) async throws {
        let cleanNumber = number.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard cleanNumber.range(of: #"^\+?[0-9]{8,15}$"#, options: .regularExpression) != nil else {
            throw NvtlError.api("Số điện thoại không hợp lệ (cần 8–15 chữ số, có thể có dấu +).")
        }
        guard !body.isEmpty else {
            throw NvtlError.api("Vui lòng nhập nội dung tin nhắn.")
        }
        guard body.count <= 70 else {
            throw NvtlError.api("Nội dung vượt quá 70 ký tự (giới hạn 1 tin UCS2).")
        }
        _ = try await callCgi(
            session: session,
            cgiName: "sms.cgi",
            params: [
                ("action", "send"),
                ("number_hex", Self.ucs2Hex(cleanNumber)),
                ("body_hex", Self.ucs2Hex(body))
            ],
            useLongTimeout: true
        )
    }

    func getBootMode(session: NvtlSession) async throws -> Bool? {
        let base = try baseURL(for: session.ip)
        let url = try resolveURL(base: base, pathOrUrl: "/cgi/persistmode.cgi")
        let raw = try await postForm(session: session, url: url, pairs: [("action", "get")], xmlHttpRequest: true, referer: base, quiet: true)
        if raw.code == 401 || raw.code == 403 { throw NvtlError.sessionExpired }
        guard (200..<300).contains(raw.code), let r = jsonObject(raw.body), boolVal(r, "ok") == true else {
            return nil
        }
        return intVal(r, "is_persistent") == 1
    }

    func forceUsbSharingMode(session: NvtlSession) async throws -> Bool {
        let page = try await fetchPage(session: session, pathOrUrl: "/preferences/")
        if page.code == 401 || HtmlFormParser.hasLoginForm(page.html) {
            throw NvtlError.sessionExpired
        }
        guard (200..<300).contains(page.code), let token = secureToken(in: page.html) else {
            return false
        }
        let form = HtmlFormParser.extractForm(idOrName: "preferencesForm", in: page.html)
        var pairs = form?.pairs ?? []
        setField(&pairs, "gSecureToken", token)
        setField(&pairs, "usbModeChange", "1")
        setField(&pairs, "usbMode", "1")

        let base = try baseURL(for: session.ip)
        let pageUrl = URL(string: page.finalUrl) ?? base
        let actionUrl: URL
        if let formAction = form?.action, !formAction.isEmpty,
           let resolved = URL(string: formAction, relativeTo: pageUrl)?.absoluteURL {
            actionUrl = resolved
        } else {
            actionUrl = try resolveURL(base: base, pathOrUrl: "/preferences/")
        }

        _ = try await postForm(session: session, url: actionUrl, pairs: pairs, xmlHttpRequest: false, referer: pageUrl)
        let verify = try await fetchPage(session: session, pathOrUrl: "/preferences/")
        if let verifiedForm = HtmlFormParser.extractForm(idOrName: "preferencesForm", in: verify.html) {
            return getField(verifiedForm.pairs, "usbMode") == "1"
        }
        return false
    }

    func setBootMode(session: NvtlSession, router24: Bool) async throws -> BootModeResult {
        let r = try await callCgi(
            session: session,
            cgiName: "persistmode.cgi",
            params: [("action", "set_mode"), ("mode", router24 ? "router24" : "mobile")],
            useLongTimeout: true
        )
        let isPersistent = intVal(r, "is_persistent") == 1
        let runlevel = strVal(r, "runlevel")

        var usbOk = false
        var battOk = false
        if router24 {
            usbOk = (try? await forceUsbSharingMode(session: session)) ?? false
            if (try? await setBatteryHealthEnabled(session: session, enabled: true)) != nil {
                battOk = true
            }
        }
        _ = try await powerAction(session: session, action: .restart)
        return BootModeResult(isPersistent: isPersistent, runlevel: runlevel, usbUpdated: usbOk, batteryEnabled: battOk)
    }

    func logout(session: NvtlSession) async {
        _ = try? await fetchPage(session: session, pathOrUrl: "/logout/")
    }
}
