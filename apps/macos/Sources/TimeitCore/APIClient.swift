import Foundation

public struct RemoteWorkspace: Codable, Sendable {
    public var revision: Int
    public var document: Workspace?
}
public struct ServerConfiguration: Codable, Sendable {
    public var developmentAuth: Bool
    public var issuer: String?
    public var clientID: String?
}
public struct RemoteIdentity: Codable, Sendable { public var id: String }
public struct SyncRequest: Codable, Sendable {
    public var baseRevision: Int
    public var mutationID: UUID
    public var document: Workspace
    public init(baseRevision: Int, mutationID: UUID = UUID(), document: Workspace) {
        self.baseRevision = baseRevision
        self.mutationID = mutationID
        self.document = document
    }
}
public struct SyncResponse: Codable, Sendable { public var revision: Int }

public struct APIClient: Sendable {
    public let baseURL: URL
    public let token: String
    public init(baseURL: URL, token: String = "") {
        self.baseURL = baseURL
        self.token = token
    }

    public func configuration() async throws -> ServerConfiguration { try await get("v1/config") }
    public func identity() async throws -> RemoteIdentity { try await get("v1/me") }
    public func workspace() async throws -> RemoteWorkspace { try await get("v1/workspace") }
    public func upload(_ document: SyncRequest) async throws -> SyncResponse {
        var request = request("v1/workspace")
        request.httpMethod = "PUT"
        request.httpBody = try WireFormat.encoder().encode(document)
        return try await perform(request)
    }
    public func rate(base: String, quote: String, date: String) async throws -> ExchangeRate {
        var parts = URLComponents(
            url: baseURL.appendingPathComponent("v1/exchange-rate"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "base", value: base), URLQueryItem(name: "quote", value: quote),
            URLQueryItem(name: "date", value: date),
        ]
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }
    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T { try await perform(request(path)) }
    private func request(_ path: String) -> URLRequest {
        var result = URLRequest(url: baseURL.appendingPathComponent(path))
        result.timeoutInterval = 15
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return result
    }
    private func perform<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if response.statusCode == 409 { throw APIError.conflict }
        if response.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw APIError.server(response.statusCode) }
        return try WireFormat.decoder().decode(T.self, from: data)
    }
}

public enum APIError: LocalizedError {
    case conflict, unauthorized, invalidResponse
    case server(Int)
    public var errorDescription: String? {
        switch self {
        case .conflict: "Des modifications ont été effectuées sur un autre appareil."
        case .unauthorized: "Reconnectez votre compte pour reprendre la synchronisation."
        case .invalidResponse: "La réponse du serveur est invalide."
        case .server(let status):
            "Le serveur est indisponible (\(status)). Vos données restent enregistrées sur ce Mac."
        }
    }
}
