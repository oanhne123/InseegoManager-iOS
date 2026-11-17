import Foundation

final class NvtlSession {
    var ip: String
    let normalSession: URLSession
    let longSession: URLSession

    private let cookieLock = NSLock()
    private var cookies: [String: String] = [:]

    var discovered: [String: String] = [:]
    var appPaths: [String: String] = [:]
    var deviceName: String?
    var identity: DeviceIdentity?

    init(ip: String, userAgent: String) {
        self.ip = ip.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalConfig = URLSessionConfiguration.ephemeral
        normalConfig.httpCookieStorage = nil
        normalConfig.httpShouldSetCookies = false
        normalConfig.timeoutIntervalForRequest = 15
        normalConfig.timeoutIntervalForResource = 20
        normalConfig.httpAdditionalHeaders = ["User-Agent": userAgent]
        normalConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.normalSession = URLSession(configuration: normalConfig)

        let longConfig = URLSessionConfiguration.ephemeral
        longConfig.httpCookieStorage = nil
        longConfig.httpShouldSetCookies = false
        longConfig.timeoutIntervalForRequest = 100
        longConfig.timeoutIntervalForResource = 110
        longConfig.httpAdditionalHeaders = ["User-Agent": userAgent]
        longConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.longSession = URLSession(configuration: longConfig)
    }

    func applyCookies(to request: inout URLRequest) {
        cookieLock.lock()
        let snapshot = cookies
        cookieLock.unlock()

        guard !snapshot.isEmpty else { return }
        let header = snapshot
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
        request.setValue(header, forHTTPHeaderField: "Cookie")
    }

    func captureCookies(from response: URLResponse?) {
        guard let http = response as? HTTPURLResponse, let url = http.url else { return }

        var stringHeaders: [String: String] = [:]
        var setCookieRawValues: [String] = []
        for (k, v) in http.allHeaderFields {
            let key = "\(k)"
            let val = "\(v)"
            stringHeaders[key] = val
            if key.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
                setCookieRawValues.append(val)
            }
        }

        let parsed = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: url)

        cookieLock.lock()
        defer { cookieLock.unlock() }

        for cookie in parsed {
            cookies[cookie.name] = cookie.value
        }

        // Fallback parser in case Apple HTTPCookie drops Version=1 / IP / SameSite cookies
        if parsed.isEmpty {
            let ignoredAttrs: Set<String> = [
                "path", "domain", "expires", "max-age", "samesite", "version", "comment", "priority", "partitioned"
            ]
            for raw in setCookieRawValues {
                let firstPart = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
                let kv = firstPart.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let name = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && !ignoredAttrs.contains(name.lowercased()) {
                        cookies[name] = value
                    }
                }
            }
        }
    }

    var cookieDebugSummary: String {
        cookieLock.lock()
        let keys = cookies.map { "\($0.key)=\($0.value.prefix(8))..." }
        cookieLock.unlock()
        return keys.isEmpty ? "(trống)" : keys.joined(separator: "; ")
    }

    var imeiNeedsFactoryReset: Bool {
        let combined = [
            deviceName ?? "",
            identity?.model ?? "",
            identity?.marketingModel ?? "",
            identity?.productName ?? ""
        ].joined(separator: " ")
        return combined.range(of: #"M3[012]00"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    deinit {
        normalSession.invalidateAndCancel()
        longSession.invalidateAndCancel()
    }
}
