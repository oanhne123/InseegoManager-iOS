import SwiftUI

struct DeviceInfoView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var isLoading = false
    @State private var lteBands: Set<Int> = []
    @State private var nrBands: NrBands?
    @State private var nrSelectedNsa: Set<Int> = []
    @State private var nrSelectedSa: Set<Int> = []

    @State private var apnText = ""
    @State private var apnCarrier = ""
    @State private var apnMccMnc = ""

    @State private var ttlText = ""
    @State private var ttlActive = false

    @State private var imeiInput = ""
    @State private var origImei = ""

    @State private var scanBand = 3
    @State private var isScanning = false
    @State private var scanStatus = ""
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        List {
            identitySection
            radioControlSection
            lteBandsSection
            if let nrBands {
                nrBandsSection(nrBands)
            }
            bandScanSection
            apnSection
            ttlSection
            imeiSection
        }
        .navigationTitle("Thiết bị & Băng tần")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadAll() }
                } label: {
                    if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task {
            await loadAll()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private var identitySection: some View {
        Section("Thông tin phần cứng & Firmware") {
            let id = appVM.identity
            row("Tên thiết bị", appVM.deviceTitle)
            row("Nhà sản xuất", id?.manufacturer ?? "")
            row("Model", id?.model ?? "")
            row("IMEI hiện tại", id?.imei ?? "")
            row("Công nghệ", id?.radioTech ?? "")
            row("Phần cứng", id?.hwVersion ?? "")
            row("OS / App", [id?.osVersion, id?.appVersion].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
            row("WebUI", id?.webUiVersion ?? "")
            row("Modem", id?.modemVersion ?? "")
        }
    }

    private var radioControlSection: some View {
        Section("Điều khiển Radio & Chế độ nguồn") {
            HStack {
                Text("Công suất Wi-Fi / Nguồn")
                Spacer()
                Button("Tiết kiệm") {
                    Task { await setPowerMode(.save) }
                }
                .buttonStyle(.bordered)
                Button("Turbo") {
                    Task { await setPowerMode(.turbo) }
                }
                .buttonStyle(.borderedProminent)
            }

            if let enabled = appVM.nrInfo?.radioEnabled ?? appVM.radio5gEnabled {
                Toggle("Bật Radio 5G NR", isOn: Binding(
                    get: { enabled },
                    set: { newVal in Task { await set5gRadio(newVal) } }
                ))
            }

            HStack {
                Text("Chế độ 5G")
                Spacer()
                Menu("Chọn chế độ") {
                    Button("Tự động (Auto 5G)") { Task { await set5gMode(0) } }
                    Button("Chỉ tắt 5G (Chế độ 1)") { Task { await set5gMode(1) } }
                    Button("Tắt 5G sâu (Chế độ 2)") { Task { await set5gMode(2) } }
                }
            }
        }
    }

    private var lteBandsSection: some View {
        let profile = appVM.session.map { NvtlApi.shared.bandProfile(for: $0) } ?? NvtlApi.profileM2000
        return Section("Khóa băng tần 4G LTE (\(lteBands.count) băng đang bật)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], spacing: 8) {
                ForEach(profile.lteBands, id: \.self) { band in
                    let active = lteBands.contains(band)
                    Button("B\(band)") {
                        if active { lteBands.remove(band) } else { lteBands.insert(band) }
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(active ? Color.accentColor : Color(.secondarySystemFill))
                    .foregroundStyle(active ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Button("Chọn tất cả") {
                    lteBands = Set(profile.lteBands)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Lưu băng 4G LTE") {
                    Task { await saveLteBands() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func nrBandsSection(_ nr: NrBands) -> some View {
        let profile = appVM.session.map { NvtlApi.shared.bandProfile(for: $0) } ?? NvtlApi.profileM2000
        let availableNsa = nr.isMaskMode ? NvtlApi.m2000NrNsaBands : (profile.nrNsaBands.isEmpty ? NvtlApi.m2000NrNsaBands : profile.nrNsaBands)

        Section("Khóa băng tần 5G NR (NSA)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], spacing: 8) {
                ForEach(availableNsa, id: \.self) { band in
                    let active = nrSelectedNsa.contains(band)
                    Button("n\(band)") {
                        if active { nrSelectedNsa.remove(band) } else { nrSelectedNsa.insert(band) }
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(active ? Color.teal : Color(.secondarySystemFill))
                    .foregroundStyle(active ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Button("Khôi phục gốc") {
                    Task { await restoreNrBands() }
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Lưu băng 5G NSA") {
                    Task { await saveNrBands(sa: false, bands: nrSelectedNsa, isMaskMode: nr.isMaskMode) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }

        if !nr.isMaskMode && !profile.nrSaBands.isEmpty {
            Section("Khóa băng tần 5G NR (SA)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 8)], spacing: 8) {
                    ForEach(profile.nrSaBands, id: \.self) { band in
                        let active = nrSelectedSa.contains(band)
                        Button("n\(band)") {
                            if active { nrSelectedSa.remove(band) } else { nrSelectedSa.insert(band) }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(active ? Color.indigo : Color(.secondarySystemFill))
                        .foregroundStyle(active ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                Button("Lưu băng 5G SA") {
                    Task { await saveNrBands(sa: true, bands: nrSelectedSa, isMaskMode: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
        }
    }

    private var bandScanSection: some View {
        Section("Quét dò sóng băng tần 4G") {
            Picker("Băng cần dò", selection: $scanBand) {
                ForEach([1, 3, 5, 7, 8, 20, 28, 38, 40, 41], id: \.self) { b in
                    Text("Band B\(b)").tag(b)
                }
            }
            if !scanStatus.isEmpty {
                Text(scanStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(isScanning ? "Đang dò..." : "Bắt đầu dò") {
                    startScan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)

                if isScanning {
                    Button("Dừng & Khôi phục", role: .destructive) {
                        Task { await stopScan() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var apnSection: some View {
        Section("Cấu hình APN") {
            if !apnCarrier.isEmpty || !apnMccMnc.isEmpty {
                row("Nhà mạng / MCC-MNC", "\(apnCarrier) (\(apnMccMnc))")
            }
            TextField("Ví dụ: v-internet", text: $apnText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NvtlApi.vietnamApnPresets) { preset in
                        Button("\(preset.carrier) (\(preset.apn))") {
                            apnText = preset.apn
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }

            Button("Lưu APN") {
                Task { await saveApn() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var ttlSection: some View {
        Section("Cấu hình TTL") {
            row("Trạng thái TTL", ttlActive ? "Đang bật" : "Mặc định")
            TextField("Nhập TTL (1–255, ví dụ 65)", text: $ttlText)
                .keyboardType(.numberPad)
            HStack {
                Button("Đặt TTL") {
                    Task { await saveTtl() }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Reset TTL", role: .destructive) {
                    Task { await resetTtl() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var imeiSection: some View {
        Section("IMEI thiết bị") {
            if !origImei.isEmpty {
                row("IMEI gốc", origImei)
            }
            TextField("IMEI 15 chữ số", text: $imeiInput)
                .keyboardType(.numberPad)
            HStack {
                Button("Ghi IMEI mới") {
                    Task { await saveImei() }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Khôi phục gốc") {
                    Task { await restoreImei() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadAll() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try? await NvtlApi.shared.getDeviceIdentity(session: session)
            appVM.identity = session.identity

            if let lte = try? await NvtlApi.shared.getEnabledLteBands(session: session) {
                lteBands = lte
            }
            if let nr = try? await NvtlApi.shared.getNrBands(session: session) {
                nrBands = nr
                nrSelectedNsa = nr.nsa
                nrSelectedSa = nr.sa
            }
            if let apn = try? await NvtlApi.shared.getApn(session: session) {
                apnText = apn.apn
                apnCarrier = apn.carrier
                apnMccMnc = apn.mccMnc
            }
            if let ttl = try? await NvtlApi.shared.getTtl(session: session) {
                ttlActive = ttl.active
                ttlText = ttl.ttl.map(String.init) ?? ""
            }
            if let imei = try? await NvtlApi.shared.getImei(session: session) {
                imeiInput = imei.imei
                origImei = imei.orig
            }
        }
    }

    private func setPowerMode(_ mode: PowerMode) async {
        guard let session = appVM.session else { return }
        do {
            try await NvtlApi.shared.setPowerMode(session: session, mode: mode)
            appVM.alertTitle = "Thành công"
            appVM.alertMessage = "Đã chuyển chế độ sang \(mode == .save ? "Tiết kiệm" : "Turbo")."
        } catch {
            appVM.handleError(error)
        }
    }

    private func set5gRadio(_ on: Bool) async {
        guard let session = appVM.session else { return }
        do {
            try await NvtlApi.shared.set5gRadio(session: session, enabled: on)
            await appVM.refreshDashboard()
        } catch {
            appVM.handleError(error)
        }
    }

    private func set5gMode(_ mode: Int) async {
        guard let session = appVM.session else { return }
        do {
            try await NvtlApi.shared.set5gMode(session: session, disableMode: mode)
            appVM.alertTitle = "Đã cập nhật"
            appVM.alertMessage = "Đã đổi chế độ 5G (val=\(mode))."
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveLteBands() async {
        guard let session = appVM.session else { return }
        do {
            try await NvtlApi.shared.setEnabledLteBands(session: session, bands: lteBands)
            appVM.alertTitle = "Thành công"
            appVM.alertMessage = "Đã lưu danh sách băng tần 4G LTE."
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveNrBands(sa: Bool, bands: Set<Int>, isMaskMode: Bool) async {
        guard let session = appVM.session else { return }
        do {
            let res = try await NvtlApi.shared.setNrBands(session: session, sa: sa, bands: bands, isMaskMode: isMaskMode)
            appVM.alertTitle = "Đã lưu băng 5G NR"
            appVM.alertMessage = res.needsReboot
                ? "Đã lưu (\(res.doneText)). Thiết bị cần khởi động lại để áp dụng."
                : "Đã áp dụng (\(res.doneText))."
        } catch {
            appVM.handleError(error)
        }
    }

    private func restoreNrBands() async {
        guard let session = appVM.session else { return }
        do {
            let res = try await NvtlApi.shared.restoreNrBands(session: session)
            nrSelectedNsa = res.bands
            appVM.alertTitle = "Đã khôi phục"
            appVM.alertMessage = "Băng 5G đã về mặc định (\(res.doneText))."
        } catch {
            appVM.handleError(error)
        }
    }

    private func startScan() {
        guard let session = appVM.session else { return }
        scanTask?.cancel()
        isScanning = true
        scanStatus = "Đang khởi chạy quét B\(scanBand)..."
        scanTask = Task {
            do {
                try await NvtlApi.shared.startBandScan(session: session, band: scanBand)
                for _ in 0..<25 {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    let poll = try await NvtlApi.shared.pollBandScan(session: session)
                    if !poll.isRunning {
                        scanStatus = poll.found
                            ? "Tìm thấy sóng B\(scanBand) • RSRP: \(poll.rsrp.map { "\($0) dBm" } ?? "—")"
                            : "Không tìm thấy sóng B\(scanBand)."
                        break
                    }
                    scanStatus = "Đang dò B\(scanBand)..."
                }
            } catch is CancellationError {
                // Cancelled
            } catch {
                scanStatus = "Lỗi: \(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    private func stopScan() async {
        scanTask?.cancel()
        isScanning = false
        guard let session = appVM.session else { return }
        do {
            try await NvtlApi.shared.stopBandScan(session: session)
            scanStatus = "Đã dừng quét và khôi phục băng."
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveApn() async {
        guard let session = appVM.session else { return }
        do {
            let updated = try await NvtlApi.shared.setApn(session: session, apn: apnText)
            apnText = updated.apn
            appVM.alertTitle = "Đã lưu APN"
            appVM.alertMessage = "APN hiện tại: \(updated.apn)"
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveTtl() async {
        guard let session = appVM.session else { return }
        guard let val = Int(ttlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            appVM.alertTitle = "Lỗi"
            appVM.alertMessage = "Vui lòng nhập số nguyên từ 1 đến 255."
            return
        }
        do {
            let updated = try await NvtlApi.shared.setTtl(session: session, ttl: val)
            ttlActive = updated.active
            ttlText = updated.ttl.map(String.init) ?? ""
            appVM.alertTitle = "Đã cập nhật TTL"
            appVM.alertMessage = "TTL = \(updated.ttl.map(String.init) ?? "—")"
        } catch {
            appVM.handleError(error)
        }
    }

    private func resetTtl() async {
        guard let session = appVM.session else { return }
        do {
            let updated = try await NvtlApi.shared.resetTtl(session: session)
            ttlActive = updated.active
            ttlText = updated.ttl.map(String.init) ?? ""
            appVM.alertTitle = "Đã reset TTL"
            appVM.alertMessage = "TTL đã trở về mặc định."
        } catch {
            appVM.handleError(error)
        }
    }

    private func saveImei() async {
        guard let session = appVM.session else { return }
        do {
            let res = try await NvtlApi.shared.setImei(session: session, imei: imeiInput)
            appVM.alertTitle = "Ghi IMEI"
            appVM.alertMessage = "IMEI mới: \(res.newImei) (Verified: \(res.verified ? "Có" : "Chờ reboot"))"
        } catch {
            appVM.handleError(error)
        }
    }

    private func restoreImei() async {
        guard let session = appVM.session else { return }
        do {
            let res = try await NvtlApi.shared.restoreImei(session: session)
            imeiInput = res.newImei
            appVM.alertTitle = "Khôi phục IMEI"
            appVM.alertMessage = "Đã khôi phục IMEI: \(res.newImei)"
        } catch {
            appVM.handleError(error)
        }
    }
}
