import Foundation

enum JSONBridge {
    static func encode(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw NativeBridgeError.invalidUTF8
        }
        return string
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = Data(string.utf8)
        return try JSONDecoder().decode(type, from: data)
    }
}
