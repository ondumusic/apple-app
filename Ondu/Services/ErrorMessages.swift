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
            return String(localized: "The server sent something this version of Ondu can’t read. Make sure the app and the server are both up to date.")
        default:
            return error.localizedDescription
        }
    }

    private static func connection(for error: Error) -> String? {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return String(localized: "You’re offline. Check your connection and try again.")
            case .cannotFindHost, .dnsLookupFailed:
                return String(localized: "Couldn’t find a server at that address. Check it for typos.")
            case .cannotConnectToHost, .timedOut, .networkConnectionLost:
                return String(localized: "Couldn’t reach the server. Make sure it’s running and reachable from this device.")
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
}
