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

    /// Whether a typed `http://` address is usable.
    ///
    /// Release builds refuse it: sign-in credentials and the whole library would cross
    /// the network in the clear, and a self-hosted server can be given a certificate.
    /// Debug keeps it so a server can be run locally without setting up TLS first.
    static var allowsInsecureServers: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Resolves user input into a full server URL.
    /// Defaults to https scheme and /api path when not specified.
    /// `allowingInsecure` is a parameter rather than only a build flag so both policies
    /// are testable; tests build as Debug and would otherwise never exercise the release
    /// behaviour.
    static func resolveServerURL(_ input: String,
                                 allowingInsecure: Bool = allowsInsecureServers) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Default to https if no scheme provided
        if !text.contains("://") {
            text = "https://\(text)"
        }

        guard let url = URL(string: text) else { return nil }
        guard allowingInsecure || url.scheme?.lowercased() != "http" else { return nil }

        // Default to /api path if user only entered a hostname (no path)
        if url.path.isEmpty || url.path == "/" {
            return url.appendingPathComponent("/api")
        }

        return url
    }

    /// Explains a rejected address, rather than leaving Sign In greyed out with no
    /// indication of why.
    private var serverURLProblem: String? {
        let text = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, resolvedURL == nil else { return nil }
        if text.lowercased().hasPrefix("http://") {
            return String(localized: "Your server must use https. Sign-in details and your music would otherwise travel unencrypted.")
        }
        return nil
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

                if let problem = serverURLProblem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }

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
                    // Overlay rather than swap: a ProgressView and the label have
                    // different intrinsic sizes, so branching between them resized
                    // the button mid-submit.
                    Text("Sign In")
                        .fontWeight(.semibold)
                        .opacity(auth.isLoading ? 0 : 1)
                        .overlay {
                            if auth.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
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
