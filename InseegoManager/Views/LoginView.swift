import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var ipAddress: String = KeychainStore.lastIp
    @State private var password: String = KeychainStore.loadPassword() ?? ""
    @State private var rememberPassword: Bool = KeychainStore.savePasswordEnabled
    @State private var showPassword = false
    @State private var isConnecting = false
    @State private var probeText: String?
    @State private var probeIsOk: Bool?
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Image("InseegoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                    Text("Inseego Manager")
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    Text("Quản lý MiFi M2000 / M3000 / M3100 / FX3100 qua Wi-Fi")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Địa chỉ IP thiết bị")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Image(systemName: "wifi.router")
                                .foregroundStyle(.tint)
                            TextField("192.168.1.1", text: $ipAddress)
                                .keyboardType(.decimalPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mật khẩu quản trị (Admin)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Image(systemName: "lock")
                                .foregroundStyle(.tint)
                            Group {
                                if showPassword {
                                    TextField("Nhập mật khẩu WebUI", text: $password)
                                } else {
                                    SecureField("Nhập mật khẩu WebUI", text: $password)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Toggle("Lưu mật khẩu an toàn trong Keychain", isOn: $rememberPassword)
                        .font(.subheadline)

                    if let probeText {
                        HStack(spacing: 8) {
                            Image(systemName: probeIsOk == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(probeIsOk == true ? .green : .orange)
                            Text(probeText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        Task { await performLogin() }
                    } label: {
                        HStack(spacing: 8) {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isConnecting ? "Đang kết nối..." : "Đăng nhập")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isConnecting || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)

                    HStack(spacing: 12) {
                        Button {
                            Task { await checkConnection() }
                        } label: {
                            Label("Kiểm tra 192.168.1.1", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isConnecting)

                        NavigationLink(value: AppRoute.debugLog) {
                            Label("Nhật ký", systemImage: "doc.text.magnifyingglass")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(18)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)

                Text("Lưu ý: Hãy kết nối iPhone vào Wi-Fi do máy Inseego phát ra và cấp quyền \"Mạng nội bộ\" (Local Network) khi được hỏi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Kết nối thiết bị")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkConnection()
        }
    }

    private func checkConnection() async {
        let ip = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { return }
        probeText = "Đang dò thiết bị tại \(ip)..."
        probeIsOk = nil
        let ok = await NvtlApi.shared.probe(ip: ip)
        probeIsOk = ok
        probeText = ok
            ? "Đã phát hiện thiết bị Inseego sẵn sàng tại \(ip)."
            : "Chưa thấy phản hồi từ \(ip). Kiểm tra lại Wi-Fi của iPhone."
    }

    private func performLogin() async {
        let ip = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        errorText = nil
        isConnecting = true
        defer { isConnecting = false }

        do {
            let session = try await NvtlApi.shared.login(ip: ip, password: password)
            KeychainStore.savePasswordEnabled = rememberPassword
            if rememberPassword {
                KeychainStore.savePassword(password)
            } else {
                KeychainStore.deletePassword()
            }
            appVM.didLogin(session)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
