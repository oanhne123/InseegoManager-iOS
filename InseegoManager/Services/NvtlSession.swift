import Foundation

final class NvtlSession {
    var ip: String
    let cookieStorage: HTTPCookieStorage
    let normalSession: URLSession
    let longSession: URLSession

    var discovered: [String: String] = [:]
    var appPaths: [String: String] = [:]
    var deviceName: String?
    var identity: DeviceIdentity?

    init(ip: String, userAgent: String) {
        self.ip = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cookieStorage = HTTPCookieStorage()

        let normalConfig = URLSessionConfiguration.ephemeral
        normalConfig.httpCookieStorage = cookieStorage
        normalConfig.httpShouldSetCookies = true
        normalConfig.timeoutIntervalForRequest = 15
        normalConfig.timeoutIntervalForResource = 20
        normalConfig.httpAdditionalHeaders = ["User-Agent": userAgent]
        normalConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.normalSession = URLSession(configuration: normalConfig)

        let longConfig = URLSessionConfiguration.ephemeral
        longConfig.httpCookieStorage = cookieStorage
        longConfig.httpShouldSetCookies = true
        longConfig.timeoutIntervalForRequest = 100
        longConfig.timeoutIntervalForResource = 110
        longConfig.httpAdditionalHeaders = ["User-Agent": userAgent]
        longConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.longSession = URLSession(configuration: longConfig)
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
