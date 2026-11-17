import SwiftUI
import Charts

struct SignalChartView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var samples: [SignalSample] = []
    @State private var mode: SignalSourceMode = .auto
    @State private var isRunning = true
    @State private var timerTask: Task<Void, Never>?

    private var latest: SignalSample? { samples.last }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Nguồn sóng", selection: $mode) {
                    ForEach(SignalSourceMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                summaryCard
                rsrpChartCard
                snrAndTempCard

                HStack(spacing: 12) {
                    Button {
                        isRunning.toggle()
                        if isRunning { startPolling() } else { timerTask?.cancel() }
                    } label: {
                        Label(isRunning ? "Tạm dừng" : "Tiếp tục", systemImage: isRunning ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        samples.removeAll()
                    } label: {
                        Label("Xóa biểu đồ", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Biểu đồ sóng trực tiếp")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if isRunning { startPolling() }
        }
        .onDisappear {
            timerTask?.cancel()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(latest?.activeTech ?? "Đang đo...")
                        .font(.headline)
                    Text("Band: \(latest?.activeBand ?? "—") • PCI/Cell: \(latest?.pci ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(latest?.score ?? 0)/100")
                        .font(.title2.bold())
                        .foregroundStyle(.tint)
                    Text(SignalSampler.describeRsrpQuality(latest?.primaryRsrp))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                statPill("RSRP", latest?.primaryRsrp.map { "\(Int($0)) dBm" } ?? "—")
                statPill("SNR", latest?.primarySnr.map { "\(Int($0)) dB" } ?? "—")
                statPill("RSRQ", latest?.primaryRsrq.map { "\(Int($0)) dB" } ?? "—")
                statPill("Nhiệt", latest?.deviceTempC.map { String(format: "%.1f°C", $0) } ?? "—")
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statPill(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var rsrpChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cường độ sóng RSRP (dBm)")
                .font(.subheadline.weight(.semibold))

            if samples.isEmpty {
                ProgressView("Đang thu thập mẫu...")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(samples) { item in
                    if let rsrp = item.primaryRsrp {
                        LineMark(
                            x: .value("Thời gian", item.timestamp),
                            y: .value("RSRP", rsrp)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: -125 ... -55)
                .frame(height: 190)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var snrAndTempCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SNR (dB) & Nhiệt độ thiết bị (°C)")
                .font(.subheadline.weight(.semibold))

            if samples.isEmpty {
                Text("Chưa có dữ liệu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Chart(samples) { item in
                    if let snr = item.primarySnr {
                        LineMark(
                            x: .value("Thời gian", item.timestamp),
                            y: .value("Giá trị", snr)
                        )
                        .foregroundStyle(by: .value("Chỉ số", "SNR (dB)"))
                    }
                    if let temp = item.deviceTempC {
                        LineMark(
                            x: .value("Thời gian", item.timestamp),
                            y: .value("Giá trị", temp)
                        )
                        .foregroundStyle(by: .value("Chỉ số", "Nhiệt độ (°C)"))
                    }
                }
                .frame(height: 170)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func startPolling() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                await sampleOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func sampleOnce() async {
        guard let session = appVM.session else { return }
        do {
            async let sigT = NvtlApi.shared.getSignal(session: session)
            async let nrT = NvtlApi.shared.getNrInfo(session: session)
            async let tmpT = NvtlApi.shared.getTemperature(session: session)

            let lte = try await sigT
            let nr = try? await nrT
            let temp = try? await tmpT

            let sample = SignalSampler.buildSample(lte: lte, nr: nr, temp: temp, mode: mode)
            samples.append(sample)
            if samples.count > 60 {
                samples.removeFirst(samples.count - 60)
            }
        } catch {
            if case NvtlError.sessionExpired = error {
                timerTask?.cancel()
                appVM.handleError(error)
            }
        }
    }
}
