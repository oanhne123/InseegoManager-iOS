import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var session: NvtlSession?
    @Published var identity: DeviceIdentity?
    @Published var signal: SignalInfo?
    @Published var nrInfo: NrInfo?
    @Published var tempInfo: TempInfo?
    @Published var dataUsage: DataUsage?
    @Published var radio5gEnabled: Bool?

    @Published var isLiveEnabled = true
    @Published var lastUpdated: Date?
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var alertTitle: String?
    @Published var alertMessage: String?

    private var isRefreshing = false

    var isLoggedIn: Bool { session != nil }

    var deviceTitle: String {
        identity?.displayName ?? session?.deviceName ?? "Inseego M2000"
    }

    func didLogin(_ newSession: NvtlSession) {
        self.session = newSession
        self.identity = newSession.identity
        KeychainStore.lastIp = newSession.ip
        Task {
            await refreshDashboard(silent: true)
        }
    }

    func refreshDashboard(silent: Bool = false) async {
        guard let session, !isRefreshing else { return }
        isRefreshing = true
        if !silent { isBusy = true }
        defer {
            isRefreshing = false
            if !silent { isBusy = false }
        }

        do {
            if self.identity == nil {
                self.identity = try await NvtlApi.shared.getDeviceIdentity(session: session)
            }
            self.signal = try await NvtlApi.shared.getSignal(session: session)
            self.nrInfo = try? await NvtlApi.shared.getNrInfo(session: session)
            self.tempInfo = try? await NvtlApi.shared.getTemperature(session: session)
            self.dataUsage = try? await NvtlApi.shared.getDataUsage(session: session)
            if self.radio5gEnabled == nil {
                self.radio5gEnabled = try? await NvtlApi.shared.getRadio5gEnabled(session: session)
            }
            self.lastUpdated = Date()
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            if !silent {
                handleError(error)
            } else if case NvtlError.sessionExpired = error {
                handleError(error)
            }
        }
    }

    func refreshTelemetryOnly() async {
        guard let session, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            self.signal = try await NvtlApi.shared.getSignal(session: session)
            self.nrInfo = try? await NvtlApi.shared.getNrInfo(session: session)
            self.tempInfo = try? await NvtlApi.shared.getTemperature(session: session)
            self.dataUsage = try? await NvtlApi.shared.getDataUsage(session: session)
            self.lastUpdated = Date()
        } catch {
            if case NvtlError.sessionExpired = error {
                handleError(error)
            }
        }
    }

    func powerAction(_ action: PowerAction) async {
        guard let session else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let msg = try await NvtlApi.shared.powerAction(session: session, action: action)
            alertTitle = action == .restart ? "Khởi động lại" : "Tắt nguồn"
            alertMessage = msg
            logoutLocalOnly()
        } catch {
            handleError(error)
        }
    }

    func logout() async {
        if let session {
            await NvtlApi.shared.logout(session: session)
        }
        logoutLocalOnly()
    }

    func logoutLocalOnly() {
        session = nil
        identity = nil
        signal = nil
        nrInfo = nil
        tempInfo = nil
        dataUsage = nil
        radio5gEnabled = nil
        lastUpdated = nil
    }

    func handleError(_ error: Error) {
        if error is CancellationError || Task.isCancelled { return }
        if case NvtlError.sessionExpired = error {
            alertTitle = "Hết phiên đăng nhập"
            alertMessage = error.localizedDescription
            logoutLocalOnly()
            return
        }
        alertTitle = "Thông báo"
        alertMessage = error.localizedDescription
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", b / 1024.0) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.2f MB", b / (1024.0 * 1024.0)) }
        return String(format: "%.2f GB", b / (1024.0 * 1024.0 * 1024.0))
    }
}
