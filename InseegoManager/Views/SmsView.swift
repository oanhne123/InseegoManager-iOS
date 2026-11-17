import SwiftUI

struct SmsView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var messages: [SmsMessage] = []
    @State private var isLoading = false
    @State private var selectedMessage: SmsMessage?
    @State private var showCompose = false

    @State private var toNumber = ""
    @State private var smsBody = ""
    @State private var isSending = false

    var body: some View {
        List {
            if messages.isEmpty && !isLoading {
                Text("Hộp thư SMS trống.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages) { msg in
                    Button {
                        Task { await openMessage(msg) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(msg.address.isEmpty ? "Không rõ số" : msg.address)
                                    .font(.subheadline.weight(msg.wasUnread ? .bold : .semibold))
                                    .foregroundStyle(.primary)
                                if msg.wasUnread {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                }
                                Spacer()
                                Text(msg.time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(msg.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button("Xóa", role: .destructive) {
                            Task { await deleteMessage(msg) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Tin nhắn SMS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                Button {
                    Task { await load() }
                } label: {
                    if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
        .sheet(item: $selectedMessage) { msg in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(msg.address)
                            .font(.headline)
                        Text(msg.time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        Text(msg.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle("Chi tiết SMS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Đóng") { selectedMessage = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                Form {
                    Section("Gửi tin nhắn mới") {
                        TextField("Số điện thoại nhận", text: $toNumber)
                            .keyboardType(.phonePad)
                        TextEditor(text: $smsBody)
                            .frame(minHeight: 110)
                        Text("\(smsBody.count)/70 ký tự")
                            .font(.caption)
                            .foregroundStyle(smsBody.count > 70 ? .red : .secondary)
                    }
                }
                .navigationTitle("Soạn SMS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Hủy") { showCompose = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSending ? "Đang gửi..." : "Gửi") {
                            Task { await send() }
                        }
                        .disabled(isSending || toNumber.isEmpty || smsBody.isEmpty || smsBody.count > 70)
                    }
                }
            }
        }
    }

    private func load() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await NvtlApi.shared.getSmsList(session: session)
        } catch {
            appVM.handleError(error)
        }
    }

    private func openMessage(_ msg: SmsMessage) async {
        guard let session = appVM.session else { return }
        if !msg.hasDetail {
            selectedMessage = msg
            return
        }
        do {
            let full = try await NvtlApi.shared.readSms(session: session, id: msg.id)
            selectedMessage = full
            if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                messages[idx] = full
            }
        } catch {
            appVM.handleError(error)
        }
    }

    private func deleteMessage(_ msg: SmsMessage) async {
        guard let session = appVM.session else { return }
        do {
            try await NvtlApi.shared.deleteSms(session: session, id: msg.id)
            messages.removeAll { $0.id == msg.id }
        } catch {
            appVM.handleError(error)
        }
    }

    private func send() async {
        guard let session = appVM.session else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await NvtlApi.shared.sendSms(session: session, number: toNumber, body: smsBody)
            showCompose = false
            toNumber = ""
            smsBody = ""
            appVM.alertTitle = "Đã gửi SMS"
            appVM.alertMessage = "Tin nhắn đã được gửi qua SIM trên thiết bị."
            await load()
        } catch {
            appVM.handleError(error)
        }
    }
}
