import SwiftUI

struct LoginView: View {
    @Environment(AuthService.self) private var auth

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section("Server") {
                TextField("https://music.example.com", text: $serverURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
            }

            Section("Credentials") {
                TextField("Username", text: $username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section {
                Button {
                    Task {
                        guard let url = URL(string: serverURL) else {
                            auth.errorMessage = "Invalid server URL"
                            return
                        }
                        await auth.login(serverURL: url, username: username, password: password)
                    }
                } label: {
                    if auth.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty || auth.isLoading)
            }

            if let error = auth.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("MusicBox")
        .onAppear {
            if let stored = auth.storedServerURL {
                serverURL = stored
            }
            if let stored = auth.storedUsername {
                username = stored
            }
        }
    }
}
