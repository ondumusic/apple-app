import Foundation
import SwiftUI

@Observable
final class AuthService {
    var currentUser: User?
    var apiService: APIService?
    var isLoggedIn: Bool { apiService != nil }
    var isLoading = false
    var isOffline = false
    var isSessionExpired = false
    var errorMessage: String?

    // MARK: - Storage Keys

    private enum Keys {
        static let serverURL = "serverURL"
        static let username = "username"
        static let password = "password"
        static let sessionToken = "sessionToken"
    }

    // MARK: - Stored Credentials (non-secrets in UserDefaults)

    var storedServerURL: String? {
        UserDefaults.standard.string(forKey: Keys.serverURL)
    }

    var storedUsername: String? {
        UserDefaults.standard.string(forKey: Keys.username)
    }

    // MARK: - Auto-Login (optimistic)

    func restoreSession() {
        guard let serverURLString = storedServerURL,
              let serverURL = URL(string: serverURLString),
              let token = KeychainHelper.load(key: Keys.sessionToken) else {
            return
        }

        // Optimistically set up the API service — UI renders immediately
        self.apiService = APIService(baseURL: serverURL, sessionToken: token)

        // Validate in the background; kick to login if expired
        Task {
            await validateSession()
        }
    }

    // MARK: - Login

    func login(serverURL: URL, username: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await APIService.login(
                baseURL: serverURL,
                username: username,
                password: password
            )

            if response.ok, let token = response.sessionToken, let user = response.currentUser {
                // Non-secrets in UserDefaults
                UserDefaults.standard.set(serverURL.absoluteString, forKey: Keys.serverURL)
                UserDefaults.standard.set(username, forKey: Keys.username)

                // Secrets in Keychain
                KeychainHelper.save(password, for: Keys.password)
                KeychainHelper.save(token, for: Keys.sessionToken)

                let api = APIService(baseURL: serverURL, sessionToken: token)
                self.apiService = api
                self.currentUser = user
            } else {
                errorMessage = response.fields?.password?.message ?? "Login failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Logout

    func logout() {
        // Keep server URL and username for prefill
        KeychainHelper.deleteAll()
        currentUser = nil
        apiService = nil
        isSessionExpired = false
        isOffline = false
    }

    // MARK: - Session Validation

    func validateSession() async {
        guard let api = apiService else { return }

        do {
            let user = try await api.fetchCurrentUser()
            self.currentUser = user
            self.isOffline = false
            self.isSessionExpired = false
        } catch APIError.unauthorized {
            self.isSessionExpired = true
        } catch {
            // Network error or other failure — stay logged in for offline playback
            self.isOffline = true
        }
    }

    // MARK: - Private

    private func clearSession() {
        KeychainHelper.delete(key: Keys.sessionToken)
        KeychainHelper.delete(key: Keys.password)
        currentUser = nil
        apiService = nil
    }
}
