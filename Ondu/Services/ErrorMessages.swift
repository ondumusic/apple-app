import Foundation

/// The system's own descriptions for network and decoding failures read as diagnostics
/// ("hostname could not be found", "NSURLErrorDomain error -1005"). These say which
/// part of the setup to look at instead.
nonisolated enum ErrorMessages {
    static func login(for error: Error) -> String {
        if let message = connection(for: error) { return message }
        switch error {
        case is DecodingError, APIError.invalidResponse, APIError.httpError(404), APIError.httpError(405):
            return String(localized: "That address doesn’t look like an Ondu server.")
        default:
            return error.localizedDescription
        }
    }

    static func sync(for error: Error) -> String {
        if let message = connection(for: error) { return message }
        switch error {
        case is DecodingError, APIError.decoding, APIError.invalidResponse, APIError.httpError(404):
            return String(
                localized:
                    "The server sent something this version of Ondu can’t read. Make sure the app and the server are both up to date."
            )
        default:
            return error.localizedDescription
        }
    }

    private static func connection(for error: Error) -> String? {
        if let urlError = error as? URLError {
            if isLocalNetworkDenied(urlError) {
                #if os(macOS)
                return String(
                    localized:
                        "Ondu isn’t allowed to reach your local network. Turn it on in System Settings ▸ Privacy & Security ▸ Local Network."
                )
                #else
                return String(
                    localized:
                        "Ondu isn’t allowed to reach your local network. Turn it on in Settings ▸ Privacy & Security ▸ Local Network."
                )
                #endif
            }
            switch urlError.code {
            case .notConnectedToInternet:
                return String(localized: "You’re offline. Check your connection and try again.")
            case .cannotFindHost, .dnsLookupFailed:
                return String(localized: "Couldn’t find a server at that address. Check it for typos.")
            case .cannotConnectToHost, .timedOut, .networkConnectionLost:
                return String(
                    localized: "Couldn’t reach the server. Make sure it’s running and reachable from this device.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return String(localized: "Couldn’t connect securely. Check the server’s HTTPS certificate.")
            default:
                return nil
            }
        }
        if case APIError.httpError(let code) = error, code >= 500 {
            return String(localized: "The server ran into a problem. Try again in a moment.")
        }
        return nil
    }

    /// A server on the local network after the user declined the local network prompt. The
    /// request fails as if the device were offline, so without this it read "You're
    /// offline" — on a device that plainly isn't. The network path attached to the error
    /// names the reason; it isn't public API, so its absence just falls through.
    static func isLocalNetworkDenied(_ error: URLError) -> Bool {
        guard let path = error.userInfo["_NSURLErrorNWPathKey"] else { return false }
        return String(describing: path).localizedCaseInsensitiveContains("Local network prohibited")
    }
}
