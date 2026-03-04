import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "music.note")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)

                Text("Welcome, \(auth.currentUser?.username ?? "")!")
                    .font(.title)

                Text("Logged in successfully.")
                    .foregroundStyle(.secondary)

                Button("Log Out", role: .destructive) {
                    auth.logout()
                }
            }
            .navigationTitle("MusicBox")
        }
    }
}
