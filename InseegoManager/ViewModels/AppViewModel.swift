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

    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var alertTitle: String?
    @Published var alertMessage: String?

    var isLoggedIn: Bool { session != nil }

    var deviceTitle: String {
        identity?.displayName ?? session?.deviceName ?? "Inseego M2000"
    }

    func didLogin(_ newSession: NvtlSession) {
        self.session = newSession
        self.identity = newSession.identity
        KeychainStore.lastIp = newSession.ip
        Task {
            await refreshDashboard()
        }
    }

    func refreshDashboard() async {
        guard let session else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            async let idTask = NvtlApi.shared.getDeviceIdentity(session: session)
            async let sigTask = NvtlApi.shared.getSignal(session: session)
            async let nrTask = NvtlApi.shared.getNrInfo(session: session)
            async let tempTask = NvtlApi.shared.getTemperature(session: session)
            async let dataTask = NvtlApi.shared.getDataUsage(session: session)

            self.identity = try await idTask
            self.signal = try await sigTask
            self.nrInfo = try? await nrTask
            self.tempInfo = try? await tempTask
            self.dataUsage = try? await dataTask
            self.radio5gEnabled = try? await NvtlApi.shared.getRadio5gEnabled(session: session)
        } catch {
            handleError(error)
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
    }

    func handleError(_ error: Error) {
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
