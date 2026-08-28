import Foundation
import Testing
@testable import MusicBox

// MARK: - AuthService State Tests

@Suite(.serialized) struct AuthServiceTests {
    init() {
        // Clean state before each test
        UserDefaults.standard.removeObject(forKey: "serverURL")
        UserDefaults.standard.removeObject(forKey: "username")
        KeychainHelper.deleteAll()
    }

    @Test func initialStateIsLoggedOut() {
        let auth = AuthService()
        #expect(!auth.isLoggedIn)
        #expect(auth.currentUser == nil)
        #expect(auth.apiService == nil)
        #expect(!auth.isLoading)
        #expect(!auth.isOffline)
        #expect(!auth.isSessionExpired)
        #expect(auth.errorMessage == nil)
    }

    @Test func isLoggedInReflectsApiService() {
        let auth = AuthService()
        #expect(!auth.isLoggedIn)

        auth.apiService = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "token")
        #expect(auth.isLoggedIn)

        auth.apiService = nil
        #expect(!auth.isLoggedIn)
    }

    @Test func storedServerURLReadsFromDefaults() {
        let auth = AuthService()
        #expect(auth.storedServerURL == nil)

        UserDefaults.standard.set("https://music.example.com/api", forKey: "serverURL")
        #expect(auth.storedServerURL == "https://music.example.com/api")
    }

    @Test func storedUsernameReadsFromDefaults() {
        let auth = AuthService()
        #expect(auth.storedUsername == nil)

        UserDefaults.standard.set("testuser", forKey: "username")
        #expect(auth.storedUsername == "testuser")
    }

    @Test func restoreSessionRequiresAllCredentials() async {
        let auth = AuthService()

        // No credentials stored — should not restore
        await auth.restoreSession()
        #expect(!auth.isLoggedIn)

        // Only serverURL — still not enough
        UserDefaults.standard.set("https://music.example.com/api", forKey: "serverURL")
        await auth.restoreSession()
        #expect(!auth.isLoggedIn)

        // serverURL + token but no username needed for restore (username only for prefill)
        KeychainHelper.save("test_token", for: "sessionToken")
        await auth.restoreSession()
        #expect(auth.isLoggedIn)
        #expect(auth.apiService?.sessionToken == "test_token")
    }

    @Test func restoreSessionSetsBaseURL() async {
        UserDefaults.standard.set("https://music.example.com/api", forKey: "serverURL")
        KeychainHelper.save("my_token", for: "sessionToken")

        let auth = AuthService()
        await auth.restoreSession()

        #expect(auth.apiService?.baseURL.absoluteString == "https://music.example.com/api")
    }

    @Test func restoringFlagStartsTrueAndClearsAfterRestore() async {
        let auth = AuthService()
        #expect(auth.isRestoringSession)

        await auth.restoreSession()

        #expect(!auth.isRestoringSession)
    }

    @Test func restoringFlagClearsWhenThereIsNothingStored() async {
        UserDefaults.standard.removeObject(forKey: "serverURL")
        let auth = AuthService()

        await auth.restoreSession()

        #expect(!auth.isRestoringSession)
        #expect(!auth.isLoggedIn)
    }

    @Test func logoutClearsState() {
        let auth = AuthService()
        auth.apiService = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "token")
        auth.currentUser = User(id: UUID(), username: "testuser")
        auth.isSessionExpired = true
        auth.isOffline = true

        KeychainHelper.save("token", for: "sessionToken")
        KeychainHelper.save("pass", for: "password")

        auth.logout()

        #expect(!auth.isLoggedIn)
        #expect(auth.currentUser == nil)
        #expect(auth.apiService == nil)
        #expect(!auth.isSessionExpired)
        #expect(!auth.isOffline)
        // Keychain should be cleared
        #expect(KeychainHelper.load(key: "sessionToken") == nil)
        #expect(KeychainHelper.load(key: "password") == nil)
    }

    @Test func logoutPreservesServerURLAndUsername() {
        UserDefaults.standard.set("https://music.example.com/api", forKey: "serverURL")
        UserDefaults.standard.set("testuser", forKey: "username")

        let auth = AuthService()
        auth.apiService = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "token")
        auth.logout()

        // Server URL and username kept for login prefill
        #expect(auth.storedServerURL == "https://music.example.com/api")
        #expect(auth.storedUsername == "testuser")
    }
}

// MARK: - Login Response Decoding Tests

@Suite struct LoginResponseDecodingTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @Test func decodesSuccessfulLogin() throws {
        let json = """
        {
            "ok": true,
            "session_token": "abc123",
            "current_user": {
                "id": "11111111-1111-1111-1111-111111111111",
                "username": "testuser"
            }
        }
        """
        let response = try decoder.decode(APIService.LoginResponse.self, from: Data(json.utf8))
        #expect(response.ok)
        #expect(response.sessionToken == "abc123")
        #expect(response.currentUser?.username == "testuser")
        #expect(response.fields == nil)
    }

    @Test func decodesFailedLogin() throws {
        let json = """
        {
            "ok": false,
            "fields": {
                "password": { "message": "Invalid password" }
            }
        }
        """
        let response = try decoder.decode(APIService.LoginResponse.self, from: Data(json.utf8))
        #expect(!response.ok)
        #expect(response.sessionToken == nil)
        #expect(response.currentUser == nil)
        #expect(response.fields?.password?.message == "Invalid password")
    }

    @Test func decodesFailedLoginWithoutFields() throws {
        let json = """
        { "ok": false }
        """
        let response = try decoder.decode(APIService.LoginResponse.self, from: Data(json.utf8))
        #expect(!response.ok)
        #expect(response.fields == nil)
    }
}
