import Foundation

/// 统一的 URLSession 配置：10 秒请求超时、不等待网络、不走本地缓存。
/// 用 `.ephemeral` 避免把网关 Cookie 落盘；设备令牌只存在钥匙串里。
enum NetworkSession {

    static func make(timeout: TimeInterval = 10) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }
}
