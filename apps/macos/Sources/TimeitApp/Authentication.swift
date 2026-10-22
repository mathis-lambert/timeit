@preconcurrency import AppAuth
import AppKit
import TimeitCore
import Valet

@MainActor
final class Authentication {
    private let vault = Valet.valet(
        with: Identifier(nonEmpty: "fr.mathislambert.Timeit")!, accessibility: .whenUnlockedThisDeviceOnly)
    private var state: OIDAuthState?
    private var flow: (any OIDExternalUserAgentSession)?
    private var storageKey = ""

    func restore(server: URL) -> Bool {
        storageKey = "oidc:\(server.absoluteString)"
        guard let data = try? vault.object(forKey: storageKey),
            let restored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data),
            restored.isAuthorized
        else { return false }
        state = restored
        return true
    }

    func signIn(configuration: ServerConfiguration, server: URL) async throws {
        storageKey = "oidc:\(server.absoluteString)"
        if restore(server: server) { return }
        guard let issuer = configuration.issuer.flatMap(URL.init(string:)), issuer.scheme == "https",
            let clientID = configuration.clientID,
            let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
        else { throw APIError.invalidResponse }
        let service: OIDServiceConfiguration = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) { configuration, error in
                if let configuration {
                    continuation.resume(returning: configuration)
                } else {
                    continuation.resume(throwing: error ?? APIError.invalidResponse)
                }
            }
        }
        let request = OIDAuthorizationRequest(
            configuration: service, clientId: clientID, scopes: [OIDScopeOpenID, OIDScopeProfile, OIDScopeEmail],
            redirectURL: URL(string: "fr.mathislambert.timeit:/oauth/callback")!, responseType: OIDResponseTypeCode,
            additionalParameters: nil)
        let authorized: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            flow = OIDAuthState.authState(byPresenting: request, presenting: window) { state, error in
                if let state {
                    continuation.resume(returning: state)
                } else {
                    continuation.resume(throwing: error ?? APIError.unauthorized)
                }
            }
        }
        flow = nil
        state = authorized
        try persist()
    }
    func accessToken() async throws -> String {
        guard let state else { throw APIError.unauthorized }
        let token: String = try await withCheckedThrowingContinuation { continuation in
            state.performAction { token, _, error in
                if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: error ?? APIError.unauthorized)
                }
            }
        }
        try persist()
        return token
    }
    private func persist() throws {
        guard let state else { return }
        try vault.setObject(
            NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true), forKey: storageKey)
    }
    func signOut() {
        flow?.cancel()
        flow = nil
        state = nil
        if !storageKey.isEmpty { try? vault.removeObject(forKey: storageKey) }
    }
}
