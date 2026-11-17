import Foundation

enum AppRoute: String, CaseIterable, Identifiable, Hashable {
    case deviceInfo
    case signalChart
    case battery
    case wifi
    case lanIp
    case sms
    case changePassword
    case debugLog

    var id: String { rawValue }
}

enum PowerAction {
    case restart
    case shutdown
}

enum PowerMode: String, CaseIterable {
    case save = "save"
    case turbo = "turbo"
}

enum SaveResult {
    case confirmed
    case sentConnectionLost
    case rejected
}

struct DeviceIdentity: Sendable {
    var productName: String = ""
    var manufacturer: String = ""
    var model: String = ""
    var marketingModel: String = ""
    var radioTech: String = ""
    var imei: String = ""
    var hwVersion: String = ""
    var osVersion: String = ""
    var appVersion: String = ""
    var webUiVersion: String = ""
    var modemVersion: String = ""

    var displayName: String? {
        for candidate in [marketingModel, model, productName] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.caseInsensitiveCompare("unknown") != .orderedSame {
                return trimmed
            }
        }
        return nil
    }
}

struct SignalInfo: Sendable {
    var tech: String = ""
    var band: String = ""
    var ca: Bool = false
    var carrier: String = ""
    var bars: Int?
    var rssi: Int?
    var rsrp: Int?
    var rsrq: Int?
    var snr: Int?
    var cellId: String = ""
    var battery: Int?
}

struct NrInfo: Sendable {
    var radioEnabled: Bool?
    var serviceAvailable: Bool = false
    var dataConnected: Bool = false
    var band: String = ""
    var activeBand: String = ""
    var endc: Bool = false
    var pci: String = ""
    var mode: String = ""
    var bars: Int?
    var rsrp: Int?
    var rsrq: Int?
    var snr: Int?
    var disableMode: Int?
}

struct TempReading: Sendable {
    var tempC: Double?
    var warnC: Double?
    var hotC: Double?
    var monitorEnabled: Bool = false
    var state: String = "normal"
}

struct TempInfo: Sendable {
    var device: TempReading = TempReading()
    var battery: TempReading = TempReading()
}

struct DataUsage: Sendable {
    var available: Bool = true
    var todayBytes: Int64 = 0
    var date: String = ""
}

struct WifiInfo: Sendable {
    var ssid: String = ""
    var isOpen: Bool = false
}

struct LanInfo: Sendable {
    var ip: String = ""
    var subnetMask: String = ""
}

struct SecurityQuestion: Identifiable, Hashable, Sendable {
    var id: String { value }
    var value: String
    var label: String
}

struct PasscodeFormInfo: Sendable {
    var questions: [SecurityQuestion]
    var selectedValue: String
}

struct ImeiInfo: Sendable {
    var imei: String
    var orig: String
}

struct ImeiWriteResult: Sendable {
    var oldImei: String
    var newImei: String
    var verified: Bool
}

struct TtlInfo: Sendable {
    var active: Bool
    var ttl: Int?
}

struct ApnInfo: Sendable {
    var apn: String
    var carrier: String
    var mccMnc: String
}

struct NrBands: Sendable {
    var nsa: Set<Int>
    var sa: Set<Int>
    var isMaskMode: Bool = false
    var rawBands: String = ""
}

struct NrBandSaveResult: Sendable {
    var bands: Set<Int>
    var needsReboot: Bool
    var doneText: String
}

struct BandScanPollResult: Sendable {
    var isRunning: Bool
    var found: Bool
    var rsrp: Int?
}

struct SmsMessage: Identifiable, Hashable, Sendable {
    var id: Int
    var wasUnread: Bool
    var hasDetail: Bool
    var address: String
    var time: String
    var body: String
}

struct BatteryHealthInfo: Sendable {
    var enabled: Bool
    var online: Bool
    var capacity: Int?
    var elapsedSeconds: Int64
    var min: Int
    var max: Int
    var durationSeconds: Int
    var manualStop: Bool
    var inputSuspended: Bool
    var note: String?
}

struct BootModeResult: Sendable {
    var isPersistent: Bool
    var runlevel: String
    var usbUpdated: Bool
    var batteryEnabled: Bool
}

struct ApnPreset: Identifiable, Sendable {
    var id: String { "\(carrier)-\(apn)" }
    var carrier: String
    var apn: String
    var user: String
    var pass: String
    var auth: Int
    var mccMncs: [String]
}

struct BandProfile: Sendable {
    var name: String
    var lteBands: [Int]
    var nrNsaBands: [Int]
    var nrSaBands: [Int]
}

struct LogEntry: Identifiable, Sendable {
    var id: Int64
    var timestamp: Date
    var title: String
    var detail: String
}

enum SignalSourceMode: String, CaseIterable, Identifiable {
    case auto = "Tự động"
    case lteOnly = "4G LTE"
    case nr5gOnly = "5G NR"

    var id: String { rawValue }
}

struct SignalSample: Identifiable, Sendable {
    let id = UUID()
    var timestamp: Date
    var primaryRsrp: Double?
    var lteRsrp: Double?
    var nrRsrp: Double?
    var primarySnr: Double?
    var primaryRsrq: Double?
    var score: Int
    var deviceTempC: Double?
    var batteryTempC: Double?
    var activeTech: String
    var activeBand: String
    var bars: Int?
    var pci: String
}

enum NvtlError: LocalizedError {
    case api(String)
    case sessionExpired
    case wrongPassword(String?)

    var errorDescription: String? {
        switch self {
        case .api(let msg):
            return msg
        case .sessionExpired:
            return "Phiên đăng nhập đã hết, vui lòng đăng nhập lại."
        case .wrongPassword(let msg):
            if let msg, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return msg
            }
            return "Sai mật khẩu quản lý."
        }
    }
}
