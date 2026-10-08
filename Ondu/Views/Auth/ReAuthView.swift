import SwiftUI

struct ReAuthView: View {
    @Environment(AuthService.self) private var auth
    @State private var password = ""
    @State private var isAttempting = false
    @State private var showLogoutConfirmation = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .padding(.bottom, 4)

            Text("Session Expired")
                .font(.headline)

            if let username = auth.storedUsername {
                Text("Please re-enter your password for **\(username)**")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SecureField("Password", text: $password)
                .focused($passwordFocused)
                .onSubmit { submit() }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            if let error = auth.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }

            Button {
                submit()
            } label: {
                Group {
                    if isAttempting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || isAttempting)

            Button("Sign Out", role: .destructive) {
                showLogoutConfirmation = true
            }
            .font(.footnote)
            .padding(.top, 4)
            .confirmationDialog(
                "Sign Out?",
                isPresented: $showLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    auth.logout()
                }
            } message: {
                Text("This will remove all offline data including downloads, cached artwork, and your synced library from this device.")
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .onAppear {
            auth.errorMessage = nil
            passwordFocused = true
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        isAttempting = true
        Task {
            let success = await auth.reAuthenticate(password: password)
            isAttempting = false
            if !success {
                password = ""
                passwordFocused = true
            }
        }
    }
}
