import SwiftUI

struct BatteryView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var info: BatteryHealthInfo?
    @State private var isRouter24: Bool?
    @State private var minPercent = 70
    @State private var maxPercent = 80
    @State private var durationHours = 16
    @State private var isLoading = false

    var body: some View {
        List {
            if let info {
                Section("Trạng thái Pin hiện tại") {
                    row("Mức pin", info.capacity.map { "\($0)%" } ?? "—")
                    row("Nguồn ngoài (USB/Sạc)", info.online ? "Đang cắm nguồn" : "Dùng pin")
                    row("Bảo vệ Pin (Battery Health)", info.enabled ? "Đang bật" : "Đang tắt")
                    row("Ngắt sạc thủ công", info.manualStop ? "Đang ngắt sạc" : "Không")
                    row("Trạng thái ngõ sạc", info.inputSuspended ? "Đang tạm dừng nạp" : "Cho phép nạp")
                    row("Thời gian đã cắm", formatDuration(info.elapsedSeconds))
                    if let note = info.note, !note.isEmpty {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Điều khiển nhanh") {
                    Button(info.manualStop ? "Tiếp tục sạc pin" : "Ngắt sạc thủ công (Dùng nguồn trực tiếp)") {
                        Task { await runAction { try await NvtlApi.shared.setBatteryManualCharge(session: $0, stopCharging: !info.manualStop) } }
                    }
                    Button(info.enabled ? "Tắt chế độ bảo vệ Pin" : "Bật chế độ bảo vệ Pin") {
                        Task { await runAction { try await NvtlApi.shared.setBatteryHealthEnabled(session: $0, enabled: !info.enabled) } }
                    }
                    Button("Kích hoạt bảo vệ Pin ngay") {
                        Task { await runAction { try await NvtlApi.shared.activateBatteryHealthNow(session: $0) } }
                    }
                    Button("Đặt lại bộ đếm thời gian") {
                        Task { await runAction { try await NvtlApi.shared.resetBatteryTimer(session: $0) } }
                    }
                    Button("Khôi phục cài đặt Pin mặc định", role: .destructive) {
                        Task { await runAction { try await NvtlApi.shared.restoreBatteryDefault(session: $0) } }
                    }
                }

                Section("Ngưỡng bảo vệ Pin") {
                    Stepper("Sạc lại khi dưới (Min): \(minPercent)%", value: $minPercent, in: 20...95, step: 5)
                    Stepper("Dừng sạc ở mức (Max): \(maxPercent)%", value: $maxPercent, in: 30...100, step: 5)
                    Stepper("Chờ trước khi kích hoạt: \(durationHours) giờ", value: $durationHours, in: 1...72)
                    Button("Lưu ngưỡng bảo vệ Pin") {
                        Task {
                            await runAction {
                                try await NvtlApi.shared.setBatteryCapability(
                                    session: $0,
                                    durationSeconds: durationHours * 3600,
                                    minPercent: minPercent,
                                    maxPercent: maxPercent
                                )
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let isRouter24 {
                Section("Chế độ khởi động (Boot Mode)") {
                    row("Chế độ hiện tại", isRouter24 ? "Router 24/7 (Cắm điện tự bật)" : "Di động (Mobile)")
                    Button(isRouter24 ? "Chuyển về chế độ Di động & Reboot" : "Chuyển sang Router 24/7 & Reboot") {
                        Task { await toggleBootMode(targetRouter24: !isRouter24) }
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Pin & Chế độ nguồn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func formatDuration(_ sec: Int64) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return "\(h) giờ \(m) phút"
    }

    private func load() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let b = try await NvtlApi.shared.getBatteryHealth(session: session)
            applyBatteryInfo(b)
            isRouter24 = try? await NvtlApi.shared.getBootMode(session: session)
        } catch {
            appVM.handleError(error)
        }
    }

    private func applyBatteryInfo(_ b: BatteryHealthInfo) {
        info = b
        minPercent = b.min
        maxPercent = b.max
        durationHours = max(1, b.durationSeconds / 3600)
    }

    private func runAction(_ block: (NvtlSession) async throws -> BatteryHealthInfo) async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await block(session)
            applyBatteryInfo(updated)
        } catch {
            appVM.handleError(error)
        }
    }

    private func toggleBootMode(targetRouter24: Bool) async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await NvtlApi.shared.setBootMode(session: session, router24: targetRouter24)
            appVM.alertTitle = "Đã đổi chế độ khởi động"
            appVM.alertMessage = "Thiết bị đang khởi động lại (\(res.runlevel))."
            appVM.logoutLocalOnly()
        } catch {
            appVM.handleError(error)
        }
    }
}
