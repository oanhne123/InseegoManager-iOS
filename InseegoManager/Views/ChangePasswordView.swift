import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject private var appVM: AppViewModel

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var questions: [SecurityQuestion] = []
    @State private var selectedQuestion = ""
    @State private var securityAnswer = ""
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("Mật khẩu quản trị") {
                SecureField("Mật khẩu hiện tại", text: $currentPassword)
                SecureField("Mật khẩu mới", text: $newPassword)
                SecureField("Xác nhận mật khẩu mới", text: $confirmPassword)
            }

            if !questions.isEmpty {
                Section("Câu hỏi bảo mật") {
                    Picker("Câu hỏi", selection: $selectedQuestion) {
                        ForEach(questions) { q in
                            Text(q.label).tag(q.value)
                        }
                    }
                    TextField("Câu trả lời bảo mật", text: $securityAnswer)
                        .autocorrectionDisabled()
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        Text("Đổi mật khẩu")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading || currentPassword.isEmpty || newPassword.isEmpty || newPassword != confirmPassword)
            }
        }
        .navigationTitle("Đổi mật khẩu Admin")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadForm()
        }
    }

    private func loadForm() async {
        guard let session = appVM.session else { return }
        do {
            let form = try await NvtlApi.shared.getPasscodeForm(session: session)
            questions = form.questions
            selectedQuestion = form.selectedValue
        } catch {
            // Optional if device doesn't expose passcode form
        }
    }

    private func submit() async {
        guard let session = appVM.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await NvtlApi.shared.changeAdminPassword(
                session: session,
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmPassword: confirmPassword,
                securityAnswer: securityAnswer,
                securityQuestion: selectedQuestion
            )
            if KeychainStore.savePasswordEnabled {
                KeychainStore.savePassword(newPassword)
            }
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            appVM.alertTitle = "Thành công"
            appVM.alertMessage = "Đã đổi mật khẩu quản trị thành công."
        } catch {
            appVM.handleError(error)
        }
    }
}
