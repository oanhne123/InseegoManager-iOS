import SwiftUI
import UIKit

struct DebugLogView: View {
    @ObservedObject private var log = DebugLog.shared
    @State private var copied = false

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Chưa có nhật ký nào.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.detail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Nhật ký gỡ lỗi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(copied ? "Đã copy" : "Copy") {
                    UIPasteboard.general.string = log.exportText()
                    copied = true
                }
                .disabled(log.entries.isEmpty)

                Button("Xóa", role: .destructive) {
                    log.clear()
                    copied = false
                }
                .disabled(log.entries.isEmpty)
            }
        }
    }
}
