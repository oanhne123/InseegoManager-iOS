import Foundation

enum SignalSampler {
    static let minRsrpDbm: Double = -125.0
    static let maxRsrpDbm: Double = -55.0
    static let minSnrDb: Double = -5.0
    static let maxSnrDb: Double = 25.0

    static func buildSample(
        lte: SignalInfo?,
        nr: NrInfo?,
        temp: TempInfo?,
        mode: SignalSourceMode,
        timestamp: Date = Date()
    ) -> SignalSample {
        let nrHasMetrics = nr.map { $0.dataConnected || $0.rsrp != nil || $0.snr != nil } ?? false
        let lteRsrp = lte?.rsrp.map(Double.init)
        let nrRsrp = nr?.rsrp.map(Double.init)

        let primaryRsrp: Double?
        let primarySnr: Double?
        let primaryRsrq: Double?
        let tech: String
        let band: String
        let bars: Int?
        let pci: String

        switch mode {
        case .nr5gOnly:
            primaryRsrp = nrRsrp
            primarySnr = nr?.snr.map(Double.init)
            primaryRsrq = nr?.rsrq.map(Double.init)
            tech = nrHasMetrics ? "5G NR" : "5G (Chưa có sóng)"
            band = formatBand(nr?.activeBand, fallback: nr?.band)
            bars = nr?.bars
            pci = (nr?.pci.isEmpty == false) ? nr!.pci : "—"

        case .lteOnly:
            primaryRsrp = lteRsrp
            primarySnr = lte?.snr.map(Double.init)
            primaryRsrq = lte?.rsrq.map(Double.init)
            tech = (lte?.tech.isEmpty == false) ? lte!.tech : "4G LTE"
            band = formatBand(lte?.band, fallback: nil, suffix: (lte?.ca == true) ? " (CA)" : nil)
            bars = lte?.bars
            pci = (lte?.cellId.isEmpty == false) ? lte!.cellId : "—"

        case .auto:
            if nrHasMetrics, let nrRsrp {
                primaryRsrp = nrRsrp
                primarySnr = (nr?.snr ?? lte?.snr).map(Double.init)
                primaryRsrq = (nr?.rsrq ?? lte?.rsrq).map(Double.init)
                tech = "5G NR"
                let nrBand = formatBand(nr?.activeBand, fallback: nr?.band)
                let lteBand = formatBand(lte?.band, fallback: nil)
                band = (lteBand != "—" && nrBand != "—") ? "\(nrBand) + \(lteBand)" : nrBand
                bars = nr?.bars ?? lte?.bars
                if let p = nr?.pci, !p.isEmpty {
                    pci = p
                } else if let c = lte?.cellId, !c.isEmpty {
                    pci = c
                } else {
                    pci = "—"
                }
            } else {
                primaryRsrp = lteRsrp
                primarySnr = lte?.snr.map(Double.init)
                primaryRsrq = lte?.rsrq.map(Double.init)
                tech = (lte?.tech.isEmpty == false) ? lte!.tech : "4G LTE"
                band = formatBand(lte?.band, fallback: nil, suffix: (lte?.ca == true) ? " (CA)" : nil)
                bars = lte?.bars
                pci = (lte?.cellId.isEmpty == false) ? lte!.cellId : "—"
            }
        }

        let score = computeSignalScore(rsrpDbm: primaryRsrp, snrDb: primarySnr)

        return SignalSample(
            timestamp: timestamp,
            primaryRsrp: primaryRsrp,
            lteRsrp: lteRsrp,
            nrRsrp: nrRsrp,
            primarySnr: primarySnr,
            primaryRsrq: primaryRsrq,
            score: score,
            deviceTempC: temp?.device.tempC,
            batteryTempC: temp?.battery.tempC,
            activeTech: tech,
            activeBand: band,
            bars: bars,
            pci: pci
        )
    }

    static func computeSignalScore(rsrpDbm: Double?, snrDb: Double?) -> Int {
        guard let rsrpDbm else {
            guard let snrDb else { return 0 }
            let snrOnly = min(max((snrDb - minSnrDb) / (maxSnrDb - minSnrDb), 0.0), 1.0)
            return Int((snrOnly * 100.0).rounded())
        }
        let rsrpNorm = min(max((rsrpDbm - minRsrpDbm) / (maxRsrpDbm - minRsrpDbm), 0.0), 1.0)
        guard let snrDb else {
            return Int((rsrpNorm * 100.0).rounded())
        }
        let snrNorm = min(max((snrDb - minSnrDb) / (maxSnrDb - minSnrDb), 0.0), 1.0)
        return Int(((rsrpNorm * 80.0) + (snrNorm * 20.0)).rounded())
    }

    static func describeRsrpQuality(_ rsrpDbm: Double?) -> String {
        guard let rsrpDbm else { return "Chưa có dữ liệu" }
        if rsrpDbm >= -80.0 { return "Rất khỏe" }
        if rsrpDbm >= -92.0 { return "Tốt" }
        if rsrpDbm >= -103.0 { return "Trung bình" }
        if rsrpDbm >= -112.0 { return "Yếu" }
        return "Rất yếu"
    }

    private static func formatBand(_ primary: String?, fallback: String?, suffix: String? = nil) -> String {
        let p = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let f = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value: String
        if !p.isEmpty && p.caseInsensitiveCompare("unknown") != .orderedSame {
            value = p
        } else if !f.isEmpty && f.caseInsensitiveCompare("unknown") != .orderedSame {
            value = f
        } else {
            value = "—"
        }
        if value == "—" || suffix == nil || suffix?.isEmpty == true {
            return value
        }
        return value + (suffix ?? "")
    }
}
