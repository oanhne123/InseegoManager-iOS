import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @State private var confirmRestart = false
    @State private var confirmShutdown = false

    private struct MenuItem: Identifiable {
        let id = UUID()
        let route: AppRoute
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
    }

    private let menuItems: [MenuItem] = [
        MenuItem(route: .deviceInfo, title: "Thiết bị & Khóa băng", subtitle: "4G/5G NR, Quét băng, APN, TTL, IMEI", icon: "antenna.radiowaves.left.and.right", color: .blue),
        MenuItem(route: .signalChart, title: "Biểu đồ sóng trực tiếp", subtitle: "RSRP, SNR & Nhiệt độ theo thời gian thực", icon: "chart.xyaxis.line", color: .green),
        MenuItem(route: .battery, title: "Pin & Chế độ nguồn", subtitle: "Battery Health, Sạc thủ công, Router 24/7", icon: "battery.75", color: .orange),
        MenuItem(route: .wifi, title: "Cài đặt Wi-Fi", subtitle: "Đổi tên mạng (SSID) & mật khẩu Wi-Fi", icon: "wifi", color: .indigo),
        MenuItem(route: .lanIp, title: "Địa chỉ IP LAN", subtitle: "Xem hoặc đổi IP Gateway của máy", icon: "network", color: .teal),
        MenuItem(route: .sms, title: "Tin nhắn SMS", subtitle: "Đọc, gửi và xóa tin nhắn SIM", icon: "message.fill", color: .purple),
        MenuItem(route: .changePassword, title: "Đổi mật khẩu Admin", subtitle: "Cập nhật mật khẩu đăng nhập WebUI", icon: "key.fill", color: .pink),
        MenuItem(route: .debugLog, title: "Nhật ký gỡ lỗi", subtitle: "Xem lịch sử request CGI & sao chép log", icon: "terminal", color: .gray)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                telemetryGrid
                quickPowerCard
                menuSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Inseego Manager")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await appVM.refreshDashboard() }
                } label: {
                    if appVM.isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Đăng xuất", role: .destructive) {
                    Task { await appVM.logout() }
                }
            }
        }
        .refreshable {
            await appVM.refreshDashboard()
        }
        .task(id: appVM.isLiveEnabled) {
            guard appVM.isLiveEnabled else { return }
            while !Task.isCancelled && appVM.isLoggedIn && appVM.isLiveEnabled {
                await appVM.refreshTelemetryOnly()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .confirmationDialog("Khởi động lại thiết bị?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Khởi động lại ngay", role: .destructive) {
                Task { await appVM.powerAction(.restart) }
            }
            Button("Hủy", role: .cancel) {}
        }
        .confirmationDialog("Tắt nguồn thiết bị?", isPresented: $confirmShutdown, titleVisibility: .visible) {
            Button("Tắt nguồn ngay", role: .destructive) {
                Task { await appVM.powerAction(.shutdown) }
            }
            Button("Hủy", role: .cancel) {}
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image("InseegoLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(appVM.deviceTitle)
                    .font(.headline)
                Text("IP: \(appVM.session?.ip ?? "—") • \(appVM.signal?.carrier.isEmpty == false ? appVM.signal!.carrier : "Đang đọc nhà mạng")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        appVM.isLiveEnabled.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(appVM.isLiveEnabled ? Color.green : Color.gray)
                                .frame(width: 7, height: 7)
                            Text(appVM.isLiveEnabled ? "Live 3s" : "Đã tạm dừng")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((appVM.isLiveEnabled ? Color.green : Color.gray).opacity(0.12))
                        .foregroundStyle(appVM.isLiveEnabled ? .green : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if let updated = appVM.lastUpdated {
                        Text(updated, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let batt = appVM.signal?.battery {
                Label("\(batt)%", systemImage: "battery.75")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var telemetryGrid: some View {
        let sample = SignalSampler.buildSample(
            lte: appVM.signal,
            nr: appVM.nrInfo,
            temp: appVM.tempInfo,
            mode: .auto
        )
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricBox(
                title: "Công nghệ & Băng",
                value: sample.activeTech,
                sub: "Band: \(sample.activeBand)",
                icon: "cellularbars",
                tint: .blue
            )
            metricBox(
                title: "Sóng (RSRP / SNR)",
                value: sample.primaryRsrp.map { "\(Int($0)) dBm" } ?? "—",
                sub: "SNR: \(sample.primarySnr.map { "\(Int($0)) dB" } ?? "—") • \(SignalSampler.describeRsrpQuality(sample.primaryRsrp))",
                icon: "waveform.path.ecg",
                tint: .green
            )
            metricBox(
                title: "Nhiệt độ",
                value: appVM.tempInfo?.device.tempC.map { String(format: "%.1f°C", $0) } ?? "—",
                sub: "Pin: \(appVM.tempInfo?.battery.tempC.map { String(format: "%.1f°C", $0) } ?? "—")",
                icon: "thermometer.medium",
                tint: .orange
            )
            metricBox(
                title: "Lưu lượng hôm nay",
                value: appVM.dataUsage.map { AppViewModel.formatBytes($0.todayBytes) } ?? "—",
                sub: appVM.dataUsage?.date.isEmpty == false ? appVM.dataUsage!.date : "Hôm nay",
                icon: "arrow.up.arrow.down",
                tint: .purple
            )
        }
    }

    private func metricBox(title: String, value: String, sub: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var quickPowerCard: some View {
        HStack(spacing: 12) {
            Button {
                confirmRestart = true
            } label: {
                Label("Khởi động lại", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button {
                confirmShutdown = true
            } label: {
                Label("Tắt nguồn", systemImage: "power")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var menuSection: some View {
        VStack(spacing: 12) {
            ForEach(menuItems) { item in
                NavigationLink(value: item.route) {
                    HStack(spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(item.color)
                            .frame(width: 42, height: 42)
                            .background(item.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
