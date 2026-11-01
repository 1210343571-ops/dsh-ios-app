import Foundation

/// 网关返回的 device 对象（`PairedDevice`）与精简 host 对象（`PairedHost`）。
/// 两者字段全部可选：网关升级时多/少字段都不该让配对失败。
struct PairedDevice: Codable, Equatable, Sendable {
    var id: String?
    var name: String?
    var platform: String?
    var createdAt: Date?
    var lastSeenAt: Date?
}

struct PairedHost: Codable, Equatable, Sendable {
    var id: String?
    var name: String?
    var platform: String?
    var release: String?
    var gatewayUrl: String?
    var gatewayUrls: [String]?
    var upstreamUrl: String?
    var dshVersion: String?
    var gatewayVersion: String?
}

struct PairResult: Equatable, Sendable {
    var token: String
    var device: PairedDevice?
    var host: PairedHost?
}

enum PairingError: LocalizedError, Equatable {

    case invalidURL
    case invalidCode
    case expired
    case rateLimited
    case pairingDisabled
    case unauthenticated
    case tokenStorageFailed
    case malformedResponse
    case transport(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return t("pair.invalidURL")
        case .invalidCode:
            return t("pair.invalidCode")
        case .expired:
            return t("pair.expired")
        case .rateLimited:
            return t("pair.rateLimited")
        case .pairingDisabled:
            return t("pair.pairingDisabled")
        case .unauthenticated:
            return t("pair.unauthenticated")
        case .tokenStorageFailed:
            return t("pair.tokenStorageFailed")
        case .malformedResponse:
            return t("pair.malformed")
        case .transport(let reason):
            return String(format: t("pair.transport"), reason)
        case .server(let reason):
            return String(format: t("pair.server"), reason)
        }
    }
}

/// `POST /__mobile/api/pair`：6 位码换设备令牌。
enum PairingClient {

    private struct PairPayload: Decodable {
        var ok: Bool?
        var token: String?
        var device: PairedDevice?
        var host: PairedHost?
        var error: String?
    }

    static func pair(baseURL: URL,
                     code: String,
                     name: String,
                     platform: String = "ios") async throws -> PairResult {
        let body: [String: Any] = [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "name": name,
            "platform": platform
        ]

        let response: (Data, HTTPURLResponse)
        do {
            response = try await HTTPClient.send("__mobile/api/pair",
                                                 baseURL: baseURL,
                                                 method: "POST",
                                                 jsonBody: body)
        } catch let error as HTTPError {
            throw PairingError.transport(error.localizedDescription)
        } catch {
            throw PairingError.transport(error.localizedDescription)
        }

        let data = response.0
        let http = response.1

        switch http.statusCode {
        case 200...299:
            let payload: PairPayload
            do {
                payload = try JSONCoding.decoder.decode(PairPayload.self, from: data)
            } catch {
                DSHLog.error("pair payload decode failed: \(error.localizedDescription)")
                throw PairingError.malformedResponse
            }
            guard let token = payload.token, !token.isEmpty else {
                throw PairingError.malformedResponse
            }
            return PairResult(token: token, device: payload.device, host: payload.host)
        case 401, 403, 429:
            let failure = try? JSONCoding.decoder.decode(PairPayload.self, from: data)
            throw mapFailure(code: failure?.error, status: http.statusCode)
        default:
            throw PairingError.server("HTTP \(http.statusCode)")
        }
    }

    private static func mapFailure(code: String?, status: Int) -> PairingError {
        switch code {
        case "invalid-code":
            return .invalidCode
        case "expired":
            return .expired
        case "rate-limited":
            return .rateLimited
        case "pairing-disabled":
            return .pairingDisabled
        case "unauthenticated":
            return .unauthenticated
        default:
            if status == 429 { return .rateLimited }
            return .server(code ?? "HTTP \(status)")
        }
    }
}
