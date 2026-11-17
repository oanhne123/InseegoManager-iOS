import SwiftUI

struct WifiView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var ssid = ""
    @State private var password = ""
    @State private var isOpenNetwork = false
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("Cấu hình Wi-Fi chính") {
                TextField("Tên Wi-Fi (SSID)", text: $ssid)
                    .autocorrectionDisabled()
                SecureField(isOpenNetwork ? "Mạng đang mở (để trống nếu giữ nguyên)" : "Mật khẩu Wi-Fi mới (để trống nếu giữ nguyên)", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await saveWifi() }
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        Text("Lưu cài đặt Wi-Fi")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading || ssid.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Nếu đổi tên hoặc mật khẩu Wi-Fi đang kết nối, iPhone có thể bị ngắt kết nối Wi-Fi tạm thời và cần kết nối lại.")
            }
        }
        .navigationTitle("Cài đặt Wi-Fi")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private func load() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await NvtlApi.shared.getWifiInfo(session: session)
            ssid = info.ssid
            isOpenNetwork = info.isOpen
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveWifi() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await NvtlApi.shared.setWifi(
                session: session,
                newSsid: ssid.trimmingCharacters(in: .whitespacesAndNewlines),
                newPassword: password.isEmpty ? nil : password
            )
            appVM.alertTitle = "Cập nhật Wi-Fi"
            appVM.alertMessage = res == .sentConnectionLost
                ? "Đã gửi cấu hình Wi-Fi mới (thiết bị đã áp dụng và khởi động lại Wi-Fi)."
                : "Đã lưu cấu hình Wi-Fi thành công."
        } catch {
            appVM.handleError(error)
        }
    }
}
