import CRhwpNative
import Foundation

enum NativeBridgeError: LocalizedError {
    case missingSession
    case nativeFailure(String)
    case invalidUTF8
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "문서 세션이 없습니다."
        case .nativeFailure(let message):
            return message
        case .invalidUTF8:
            return "native API 문자열을 UTF-8로 해석할 수 없습니다."
        case .invalidResponse(let payload):
            return "예상하지 못한 응답입니다: \(payload)"
        }
    }
}

final class EditorSession {
    let handle: UInt64
    private var isClosed = false

    private init(handle: UInt64) {
        self.handle = handle
    }

    deinit {
        close()
    }

    static func open(data: Data, sourcePath: String? = nil) throws -> EditorSession {
        let handle = data.withUnsafeBytes { rawBuffer -> UInt64 in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            if let sourcePath {
                return sourcePath.withCString { pathCString in
                    rhwp_session_open_with_path(baseAddress, rawBuffer.count, pathCString)
                }
            }
            return rhwp_session_open(baseAddress, rawBuffer.count)
        }
        guard handle != 0 else {
            throw NativeBridgeError.nativeFailure(lastErrorMessage())
        }
        return EditorSession(handle: handle)
    }

    static func createBlank() throws -> EditorSession {
        let handle = rhwp_session_create_blank()
        guard handle != 0 else {
            throw NativeBridgeError.nativeFailure(lastErrorMessage())
        }
        return EditorSession(handle: handle)
    }

    func close() {
        guard !isClosed else { return }
        _ = rhwp_session_close(handle)
        isClosed = true
    }

    func documentInfo() throws -> RHWPDocumentInfo {
        try decodeJSON(RHWPDocumentInfo.self, from: rhwp_session_get_document_info(handle))
    }

    func pageInfo(_ pageIndex: Int) throws -> RHWPPageInfo {
        try decodeJSON(RHWPPageInfo.self, from: rhwp_session_get_page_info(handle, UInt32(pageIndex)))
    }

    func pageRenderTree(_ pageIndex: Int) throws -> RHWPRenderNode {
        try decodeJSON(RHWPRenderNode.self, from: rhwp_session_get_page_render_tree(handle, UInt32(pageIndex)))
    }

    func renderPageSVG(_ pageIndex: Int) throws -> String {
        try string(from: rhwp_session_render_page_svg(handle, UInt32(pageIndex)))
    }

    func exportHwp() throws -> Data {
        var length: Int = 0
        guard let pointer = rhwp_session_export_hwp(handle, &length), length > 0 else {
            throw NativeBridgeError.nativeFailure(Self.lastErrorMessage())
        }
        defer { rhwp_bytes_free(pointer, length) }
        return Data(bytes: pointer, count: length)
    }

    func saveSnapshot() throws -> UInt32 {
        let snapshot = rhwp_session_save_snapshot(handle)
        if snapshot == 0 {
            throw NativeBridgeError.nativeFailure(Self.lastErrorMessage())
        }
        return snapshot
    }

    func restoreSnapshot(_ snapshotID: UInt32) throws {
        _ = try string(from: rhwp_session_restore_snapshot(handle, snapshotID))
    }

    func discardSnapshot(_ snapshotID: UInt32) {
        _ = rhwp_session_discard_snapshot(handle, snapshotID)
    }

    @discardableResult
    func beginBatch() throws -> String {
        try string(from: rhwp_session_begin_batch(handle))
    }

    @discardableResult
    func endBatch() throws -> String {
        try string(from: rhwp_session_end_batch(handle))
    }

    func eventLogJSON() throws -> String {
        try string(from: rhwp_session_get_event_log(handle))
    }

    func perform(operation: String, payload: [String: Any] = [:]) throws -> String {
        let payloadJSON = try JSONBridge.encode(payload)
        return try operation.withCString { operationCString in
            try payloadJSON.withCString { payloadCString in
                try string(from: rhwp_session_apply_operation(handle, operationCString, payloadCString))
            }
        }
    }

    func decodeResult<T: Decodable>(_ type: T.Type, operation: String, payload: [String: Any] = [:]) throws -> T {
        let raw = try perform(operation: operation, payload: payload)
        return try JSONBridge.decode(T.self, from: raw)
    }

    static func lastErrorMessage() -> String {
        guard let raw = rhwp_last_error_message() else {
            return "알 수 없는 native API 오류"
        }
        defer { rhwp_string_free(raw) }
        return String(cString: raw)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from rawPointer: UnsafeMutablePointer<CChar>?) throws -> T {
        let raw = try string(from: rawPointer)
        return try JSONBridge.decode(T.self, from: raw)
    }

    private func string(from rawPointer: UnsafeMutablePointer<CChar>?) throws -> String {
        guard let rawPointer else {
            throw NativeBridgeError.nativeFailure(Self.lastErrorMessage())
        }
        defer { rhwp_string_free(rawPointer) }
        return String(cString: rawPointer)
    }
}
