import Foundation

enum HTTPError: LocalizedError, Equatable {

    case invalidURL
    case unauthorized
    case http(Int)
    case transport(String)
    case decoding(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return t("net.invalidURL")
        case .unauthorized:
            return t("net.unauthorized")
        case .http(let status):
            return String(format: t("net.http"), status)
        case .transport(let reason):
            return String(format: t("net.transport"), reason)
        case .decoding:
            return t("net.decoding")
        case .emptyResponse:
            return t("net.empty")
        }
    }
}

/// 极简 HTTP 客户端：只做「拼 URL → 加 Bearer → 发请求 → 返回 data/状态码」。
/// 网关契约见 docs/SPEC.md 第 2 节；这里不引入任何第三方库。
enum HTTPClient {

    static let session: URLSession = NetworkSession.make(timeout: 10)

    static func url(for path: String, baseURL: URL) -> URL? {
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: base + trimmed)
    }

    /// 只抛出传输层错误；HTTP 状态码交给调用方判断（配对接口靠状态码区分错误原因）。
    static func send(_ path: String,
                     baseURL: URL,
                     method: String = "GET",
                     token: String? = nil,
                     jsonBody: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = url(for: path, baseURL: baseURL) else { throw HTTPError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let jsonBody {
            guard JSONSerialization.isValidJSONObject(jsonBody) else {
                throw HTTPError.decoding("request-body")
            }
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
            } catch {
                throw HTTPError.decoding("request-body")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.emptyResponse }
            return (data, http)
        } catch let error as HTTPError {
            throw error
        } catch let error as URLError {
            throw HTTPError.transport(error.localizedDescription)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
    }

    /// GET 并解码；非 2xx 直接映射成 `HTTPError`。
    static func getJSON<T: Decodable>(_ path: String,
                                      baseURL: URL,
                                      token: String?,
                                      as type: T.Type) async throws -> T {
        let (data, http) = try await send(path, baseURL: baseURL, method: "GET", token: token)
        switch http.statusCode {
        case 200...299:
            return try decode(data, as: type)
        case 401, 403:
            throw HTTPError.unauthorized
        default:
            throw HTTPError.http(http.statusCode)
        }
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            DSHLog.error("decode \(T.self) failed: \(error.localizedDescription)")
            throw HTTPError.decoding(error.localizedDescription)
        }
    }
}
