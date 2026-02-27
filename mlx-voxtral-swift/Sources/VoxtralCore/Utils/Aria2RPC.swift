/// Minimal aria2 JSON-RPC client adapted from Peeri's Aria2Kit.
/// Only includes the subset of types and methods needed by ModelDownloader.

import Foundation

// MARK: - JSON-RPC Wire Types

enum AnyJSON: Encodable, Sendable {
    case string(String)
    case int(Int)
    case array([AnyJSON])
    case dictionary([String: AnyJSON])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        }
    }
}

enum Aria2Method: String, Encodable {
    case addUri = "aria2.addUri"
    case tellActive = "aria2.tellActive"
    case tellWaiting = "aria2.tellWaiting"
    case tellStopped = "aria2.tellStopped"
    case pause = "aria2.pause"
    case unpause = "aria2.unpause"
    case forceRemove = "aria2.forceRemove"
    case getVersion = "aria2.getVersion"
    case forceShutdown = "aria2.forceShutdown"
}

private struct RPCRequest: Encodable {
    let id: String
    let jsonrpc: String = "2.0"
    let method: String
    let params: [AnyJSON]

    init(method: Aria2Method, params: [AnyJSON], token: String?) {
        self.id = UUID().uuidString
        self.method = method.rawValue
        if let token {
            self.params = [.string("token:\(token)")] + params
        } else {
            self.params = params
        }
    }
}

private struct RPCResponse<T: Decodable>: Decodable {
    let id: String
    let jsonrpc: String
    let result: T?
    let error: RPCError?
}

private struct RPCError: Decodable {
    let code: Int
    let message: String
}

// MARK: - Response Models

struct Aria2StatusResponse: Decodable, Sendable {
    let gid: String
    let status: String
    let totalLength: String
    let completedLength: String
    let downloadSpeed: String
    let errorCode: String?
    let errorMessage: String?
}

struct Aria2VersionResponse: Decodable, Sendable {
    let version: String
    let enabledFeatures: [String]
}

// MARK: - Errors

enum Aria2RPCError: Error, LocalizedError {
    case notInitialized
    case connectionFailed(underlying: Error)
    case httpError(statusCode: Int)
    case decodingError(String)
    case rpcError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Aria2 RPC client not initialized"
        case .connectionFailed(let e): return "Connection failed: \(e.localizedDescription)"
        case .httpError(let code): return "HTTP error: \(code)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .rpcError(_, let msg): return "RPC error: \(msg)"
        }
    }
}

// MARK: - RPC Client

actor Aria2RPCClient {
    private var baseURL: URL?
    private var token: String?
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func initialize(port: UInt16, token: String) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)/jsonrpc")
        self.token = token
    }

    // MARK: - Generic RPC Call

    func call<T: Decodable>(_ method: Aria2Method, params: [AnyJSON] = []) async throws -> T {
        guard let url = baseURL else { throw Aria2RPCError.notInitialized }

        let request = RPCRequest(method: method, params: params, token: token)
        let bodyData = try JSONEncoder().encode(request)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = bodyData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw Aria2RPCError.connectionFailed(underlying: error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Aria2RPCError.httpError(statusCode: http.statusCode)
        }

        let rpcResponse: RPCResponse<T>
        do {
            rpcResponse = try JSONDecoder().decode(RPCResponse<T>.self, from: data)
        } catch {
            throw Aria2RPCError.decodingError(error.localizedDescription)
        }

        if let rpcError = rpcResponse.error {
            throw Aria2RPCError.rpcError(code: rpcError.code, message: rpcError.message)
        }

        guard let result = rpcResponse.result else {
            throw Aria2RPCError.decodingError("Response had no result and no error")
        }

        return result
    }

    // MARK: - Thin Wrappers

    func getVersion() async throws -> Aria2VersionResponse {
        try await call(.getVersion)
    }

    func addUri(_ uris: [String], options: [String: String]? = nil) async throws -> String {
        var params: [AnyJSON] = [.array(uris.map { .string($0) })]
        if let options {
            let dict = Dictionary(uniqueKeysWithValues: options.map { ($0.key, AnyJSON.string($0.value)) })
            params.append(.dictionary(dict))
        }
        return try await call(.addUri, params: params)
    }

    func tellActive() async throws -> [Aria2StatusResponse] {
        try await call(.tellActive)
    }

    func tellWaiting(offset: Int = 0, num: Int = 1000) async throws -> [Aria2StatusResponse] {
        try await call(.tellWaiting, params: [.int(offset), .int(num)])
    }

    func tellStopped(offset: Int = 0, num: Int = 1000) async throws -> [Aria2StatusResponse] {
        try await call(.tellStopped, params: [.int(offset), .int(num)])
    }

    func pause(gid: String) async throws -> String {
        try await call(.pause, params: [.string(gid)])
    }

    func forceRemove(gid: String) async throws -> String {
        try await call(.forceRemove, params: [.string(gid)])
    }

    func forceShutdown() async throws -> String {
        try await call(.forceShutdown)
    }
}
