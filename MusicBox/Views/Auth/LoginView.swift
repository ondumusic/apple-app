import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var shakeError = false

    private enum Field: Hashable {
        case server, username, password
    }

    @FocusState private var focusedField: Field?

    private var resolvedURL: URL? {
        Self.resolveServerURL(serverURL)
    }

    /// Resolves user input into a full server URL.
    /// Defaults to https scheme and /api path when not specified.
    static func resolveServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Default to https if no scheme provided
        if !text.contains("://") {
            text = "https://\(text)"
        }

        guard let url = URL(string: text) else { return nil }

        // Default to /api path if user only entered a hostname (no path)
        if url.path.isEmpty || url.path == "/" {
            return url.appendingPathComponent("/api")
        }

        return url
    }

    private var canSubmit: Bool {
        resolvedURL != nil && !username.isEmpty && !password.isEmpty && !auth.isLoading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // App branding
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 8)

                Text("MusicBox")
                    .font(.title.bold())
                    .padding(.bottom, 4)

                Text("Sign in to your server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 36)

                // Input fields
                VStack(spacing: 12) {
                    fieldRow(
                        icon: "server.rack",
                        placeholder: "music.example.com",
                        text: $serverURL,
                        field: .server
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                    fieldRow(
                        icon: "person",
                        placeholder: "Username",
                        text: $username,
                        field: .username
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                    HStack(spacing: 10) {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        SecureField("Password", text: $password)
                            .focused($focusedField, equals: .password)
                            .onSubmit { submit() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                }
                .autocorrectionDisabled()
                .padding(.horizontal, 24)

                // Error
                if let error = auth.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .offset(x: shakeError ? -6 : 0)
                }

                // Sign In button
                Button {
                    submit()
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .disabled(!canSubmit)
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()
            }
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
        .onAppear {
            if let stored = auth.storedServerURL {
                var display = stored
                // Strip https:// for cleaner display since it's the default
                if display.hasPrefix("https://") {
                    display = String(display.dropFirst(8))
                }
                // Strip /api suffix since it's the default
                if display.hasSuffix("/api") {
                    display = String(display.dropLast(4))
                }
                serverURL = display
            }
            if let stored = auth.storedUsername {
                username = stored
            }

            // Focus first empty field
            if serverURL.isEmpty {
                focusedField = .server
            } else if username.isEmpty {
                focusedField = .username
            } else {
                focusedField = .password
            }
        }
    }

    private func fieldRow(icon: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .onSubmit { advanceFocus(from: field) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .server: focusedField = .username
        case .username: focusedField = .password
        case .password: submit()
        }
    }

    private func submit() {
        guard canSubmit, let url = resolvedURL else { return }
        Task {
            await auth.login(serverURL: url, username: username, password: password)
            if auth.errorMessage != nil {
                withAnimation(.default.speed(3).repeatCount(3, autoreverses: true)) {
                    shakeError = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    shakeError = false
                }
            }
        }
    }
}
