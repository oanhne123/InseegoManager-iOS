import SwiftUI

@main
struct InseegoManagerApp: App {
    @StateObject private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if appVM.isLoggedIn {
                    NavigationStack {
                        DashboardView()
                            .navigationDestination(for: AppRoute.self) { route in
                                switch route {
                                case .deviceInfo:
                                    DeviceInfoView()
                                case .signalChart:
                                    SignalChartView()
                                case .battery:
                                    BatteryView()
                                case .wifi:
                                    WifiView()
                                case .lanIp:
                                    LanIpView()
                                case .sms:
                                    SmsView()
                                case .changePassword:
                                    ChangePasswordView()
                                case .debugLog:
                                    DebugLogView()
                                }
                            }
                    }
                } else {
                    NavigationStack {
                        LoginView()
                            .navigationDestination(for: AppRoute.self) { route in
                                if route == .debugLog {
                                    DebugLogView()
                                }
                            }
                    }
                }
            }
            .environmentObject(appVM)
            .alert(appVM.alertTitle ?? "Thông báo", isPresented: Binding(
                get: { appVM.alertMessage != nil },
                set: { if !$0 { appVM.alertMessage = nil } }
            )) {
                Button("Đóng", role: .cancel) {
                    appVM.alertMessage = nil
                }
            } message: {
                Text(appVM.alertMessage ?? "")
            }
        }
    }
}
