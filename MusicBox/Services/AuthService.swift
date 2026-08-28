import Foundation
import Nuke
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
    /// True until the stored session has been read back at launch. Gates the UI so
    /// `LoginView` doesn't flash before we know whether there's a token.
    var isRestoringSession = true

    // MARK: - Storage Keys

    private enum Keys {
        static let serverURL = "serverURL"
        static let username = "username"
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

    /// Reads the stored session back at launch. The Keychain work happens off the main
    /// thread: `SecItemCopyMatching` blocks on a locked keychain or an access prompt, and
    /// a stall on the main thread freezes the app before any window exists.
    func restoreSession() async {
        defer { isRestoringSession = false }

        guard let serverURLString = storedServerURL,
              let serverURL = URL(string: serverURLString) else { return }

        let key = Keys.sessionToken
        guard let token = await Task.detached(priority: .userInitiated, operation: {
            KeychainHelper.load(key: key)
        }).value else { return }

        // Re-save to upgrade Keychain accessibility if needed (kSecAttrAccessibleAfterFirstUnlock)
        await Task.detached(priority: .utility, operation: {
            KeychainHelper.save(token, for: key)
        }).value

        // Optimistically set up the API service — UI renders immediately
        #if DEBUG
        print("AuthService: restoring session with token: \(token)")
        #endif
        self.apiService = APIService(baseURL: serverURL, sessionToken: token)

        // Validate in the background — the UI must not wait on the network.
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

                // Session token in Keychain
                KeychainHelper.save(token, for: Keys.sessionToken)
                #if DEBUG
                print("AuthService: logged in with token: \(token)")
                #endif

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

    // MARK: - Re-Authentication

    /// Re-authenticate with a user-provided password.
    func reAuthenticate(password: String) async -> Bool {
        guard let serverURLString = storedServerURL,
              let serverURL = URL(string: serverURLString),
              let username = storedUsername else {
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await APIService.login(
                baseURL: serverURL,
                username: username,
                password: password
            )

            if response.ok, let token = response.sessionToken, let user = response.currentUser {
                KeychainHelper.save(token, for: Keys.sessionToken)
                #if DEBUG
                print("AuthService: re-authenticated with token: \(token)")
                #endif

                let api = APIService(baseURL: serverURL, sessionToken: token)
                self.apiService = api
                self.currentUser = user
                self.isSessionExpired = false
                isLoading = false
                return true
            } else {
                errorMessage = response.fields?.password?.message ?? "Re-authentication failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        return false
    }

    // MARK: - Logout

    func logout() {
        // Server-side session invalidation (best-effort, fire-and-forget)
        if let api = apiService {
            Task { try? await api.deleteSession() }
        }

        // Clear Nuke image cache (cached artwork)
        ImagePipeline.shared.cache.removeAll()

        // Keep server URL and username for prefill
        KeychainHelper.deleteAll()
        currentUser = nil
        apiService = nil
        isSessionExpired = false
        isOffline = false
    }

    // MARK: - Session Expiration Observation

    func observeSessionExpiration() {
        NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSessionExpired = true
        }
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
}
