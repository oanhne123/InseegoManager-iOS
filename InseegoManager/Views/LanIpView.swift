import SwiftUI

struct LanIpView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var ipAddress = ""
    @State private var subnetMask = ""
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("Cấu hình IP LAN (Gateway)") {
                TextField("192.168.1.1", text: $ipAddress)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Text("Subnet Mask")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(subnetMask.isEmpty ? "255.255.255.0" : subnetMask)
                }
            }

            Section {
                Button {
                    Task { await saveLan() }
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        Text("Lưu IP LAN mới")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("Sau khi đổi IP LAN, thiết bị sẽ khởi động lại dịch vụ mạng. Hãy kết nối lại Wi-Fi để iPhone nhận dải IP mới.")
            }
        }
        .navigationTitle("Địa chỉ IP LAN")
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
            let info = try await NvtlApi.shared.getLanInfo(session: session)
            ipAddress = info.ip
            subnetMask = info.subnetMask
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveLan() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        let newIp = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let res = try await NvtlApi.shared.setLanIp(session: session, newIp: newIp)
            KeychainStore.lastIp = newIp
            appVM.alertTitle = "Cập nhật IP LAN"
            appVM.alertMessage = res == .sentConnectionLost
                ? "Đã gửi IP LAN mới (\(newIp)). Máy đang khởi động lại mạng."
                : "Đã lưu IP LAN mới: \(newIp)."
        } catch {
            appVM.handleError(error)
        }
    }
}
