import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Invalid server response."
        case .server(_, let message):
            return message
        case .decoding:
            return "Unable to decode server response."
        case .transport(let message):
            return message
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encoder: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encoder = { enc in
            try wrapped.encode(to: enc)
        }
    }

    func encode(to encoder: Encoder) throws {
        try self.encoder(encoder)
    }
}

final class APIClient {
    static let shared = APIClient()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Encodable? = nil
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, headers: headers, body: body)

        do {
            let (data, response) = try await session.data(for: request)
            return try decodeResponse(data: data, response: response)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }

    func upload<T: Decodable>(
        path: String,
        headers: [String: String],
        mimeType: String,
        data: Data
    ) async throws -> T {
        var request = try makeRequest(path: path, method: "PUT", headers: headers, body: nil as String?)
        request.setValue(mimeType, forHTTPHeaderField: "content-type")

        do {
            let (responseData, response) = try await session.upload(for: request, from: data)
            return try decodeResponse(data: responseData, response: response)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }

    func requestIgnoringBody(
        path: String,
        method: String = "POST",
        headers: [String: String] = [:],
        body: Encodable? = nil
    ) async throws {
        let request = try makeRequest(path: path, method: method, headers: headers, body: body)

        do {
            let (data, response) = try await session.data(for: request)
            _ = try decodeResponse(data: data, response: response) as SimpleOKResponse
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        headers: [String: String],
        body: Encodable?
    ) throws -> URLRequest {
        guard let url = resolvedURL(path: path) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            if request.value(forHTTPHeaderField: "content-type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "content-type")
            }
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }

    private func resolvedURL(path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme?.hasPrefix("http") == true {
            return absolute
        }

        if path.hasPrefix("/") {
            return URL(string: path, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        }

        return URL(string: "/\(path)", relativeTo: AppConfig.apiBaseURL)?.absoluteURL
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            if let apiError = try? decoder.decode(APIFieldErrorResponse.self, from: data) {
                throw NetworkError.server(status: http.statusCode, message: apiError.error.message)
            }

            let fallback = String(data: data, encoding: .utf8) ?? "Request failed with status \(http.statusCode)."
            throw NetworkError.server(status: http.statusCode, message: fallback)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error.localizedDescription)
        }
    }
}
