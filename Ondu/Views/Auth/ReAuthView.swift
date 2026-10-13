import SwiftUI

struct ReAuthView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isAttempting = false
    @State private var showLogoutConfirmation = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        layout
            .confirmationDialog(
                "Sign Out?",
                isPresented: $showLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    auth.logout()
                }
            } message: {
                Text(
                    "This will remove all offline data including downloads, cached artwork, and your synced library from this device."
                )
            }
            .onAppear {
                auth.errorMessage = nil
                passwordFocused = true
            }
    }

    #if os(macOS)
    /// A Mac dialog: a standard field, and the buttons in a row along the bottom with the
    /// default action on the right and the destructive one set apart on the left.
    private var layout: some View {
        VStack(spacing: 16) {
            header
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit { submit() }
            errorLine
            HStack {
                Button("Sign Out…", role: .destructive) { showLogoutConfirmation = true }
                Spacer()
                // A Mac sheet can't be swiped away, so without this the only ways out
                // were signing in or signing out. The expired state stays up either way.
                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sign In") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isAttempting)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
    }
    #else
    private var layout: some View {
        VStack(spacing: 16) {
            header

            SecureField("Password", text: $password)
                .focused($passwordFocused)
                .onSubmit { submit() }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            errorLine

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

            Button("Not Now") { dismiss() }

            Button("Sign Out", role: .destructive) {
                showLogoutConfirmation = true
            }
            .font(.footnote)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 320)
    }
    #endif

    private var header: some View {
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
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let error = auth.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text(error)
                    .font(.caption)
            }
            .foregroundStyle(.red)
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
