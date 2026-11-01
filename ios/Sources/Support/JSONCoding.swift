import Foundation

/// 统一的 JSON 编解码器。
/// - 解码：字段缺失/类型不符尽量不炸整个响应（模型里所有字段都是可选）。
/// - 日期：带毫秒、不带毫秒、Unix 秒/毫秒都能吃下；解析失败给 1970 哨兵值，交给展示层显示「未知」。
enum JSONCoding {

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { inner in
            let container = try inner.singleValueContainer()
            if let text = try? container.decode(String.self) {
                return DateParsing.parse(text) ?? Date(timeIntervalSince1970: 0)
            }
            if let number = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1000 : number)
            }
            return Date(timeIntervalSince1970: 0)
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
