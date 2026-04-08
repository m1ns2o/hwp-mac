use std::io::{self, BufRead, Read, Write};
use std::path::Path;

use rhwp::native_api::{
    apply_operations, close_document, create_blank_document, get_page_control_layout_json,
    get_page_info_json, get_page_render_tree_json, get_page_text_layout_json, open_document_path,
    read_document_json, render_page_svg, save_document_to_path, OperationRequest, SessionHandle,
};
use serde_json::{json, Value};

fn main() {
    if let Err(error) = run() {
        eprintln!("[rhwp-mcp] {}", error);
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut reader = stdin.lock();
    let mut writer = stdout.lock();

    while let Some(message) = read_message(&mut reader)? {
        if let Some(response) = handle_message(message) {
            write_message(&mut writer, &response)?;
        }
    }

    Ok(())
}

fn read_message<R: BufRead + Read>(reader: &mut R) -> Result<Option<Value>, String> {
    let mut content_length: Option<usize> = None;

    loop {
        let mut line = String::new();
        let bytes_read = reader
            .read_line(&mut line)
            .map_err(|error| format!("stdin 읽기 실패: {}", error))?;

        if bytes_read == 0 {
            if content_length.is_none() {
                return Ok(None);
            }
            return Err("메시지 헤더가 비정상 종료되었습니다".to_string());
        }

        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }

        if let Some((name, value)) = trimmed.split_once(':') {
            if name.eq_ignore_ascii_case("Content-Length") {
                let parsed = value
                    .trim()
                    .parse::<usize>()
                    .map_err(|error| format!("Content-Length 파싱 실패: {}", error))?;
                content_length = Some(parsed);
            }
        }
    }

    let content_length = content_length.ok_or_else(|| "Content-Length 헤더가 없습니다".to_string())?;
    let mut payload = vec![0u8; content_length];
    reader
        .read_exact(&mut payload)
        .map_err(|error| format!("본문 읽기 실패: {}", error))?;

    serde_json::from_slice(&payload).map(Some).map_err(|error| format!("JSON 파싱 실패: {}", error))
}

fn write_message<W: Write>(writer: &mut W, value: &Value) -> Result<(), String> {
    let encoded = value.to_string();
    write!(writer, "Content-Length: {}\r\n\r\n{}", encoded.len(), encoded)
        .map_err(|error| format!("stdout 쓰기 실패: {}", error))?;
    writer.flush().map_err(|error| format!("stdout flush 실패: {}", error))
}

fn handle_message(message: Value) -> Option<Value> {
    let method = message.get("method")?.as_str()?;
    let id = message.get("id").cloned();
    let params = message.get("params").cloned().unwrap_or_else(|| json!({}));

    let response = match method {
        "initialize" => Ok(json!({
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "serverInfo": {
                "name": "rhwp-mcp",
                "version": env!("CARGO_PKG_VERSION")
            }
        })),
        "notifications/initialized" => return None,
        "ping" => Ok(json!({})),
        "tools/list" => Ok(json!({
            "tools": tool_definitions()
        })),
        "tools/call" => {
            let name = params
                .get("name")
                .and_then(Value::as_str)
                .ok_or_else(|| "tools/call.name 이 필요합니다".to_string());
            let arguments = params.get("arguments").cloned().unwrap_or_else(|| json!({}));
            name.and_then(|tool_name| call_tool(tool_name, &arguments))
        }
        _ => Err(format!("지원하지 않는 메서드: {}", method)),
    };

    id.map(|request_id| match response {
        Ok(result) => json!({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": result,
        }),
        Err(error) => json!({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {
                "code": -32602,
                "message": error,
            }
        }),
    })
}

fn tool_definitions() -> Vec<Value> {
    vec![
        json!({
            "name": "open_document",
            "description": "HWP/HWPX 문서를 열고 세션 핸들을 반환합니다.",
            "inputSchema": {
                "type": "object",
                "required": ["path"],
                "properties": {
                    "path": { "type": "string", "description": "열 문서 경로" }
                }
            }
        }),
        json!({
            "name": "create_document",
            "description": "빈 HWP 문서를 생성하고 세션 핸들을 반환합니다.",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        }),
        json!({
            "name": "read_document",
            "description": "문서 메타데이터, 필드, 책갈피, 페이지 정보를 JSON으로 반환합니다.",
            "inputSchema": {
                "type": "object",
                "required": ["session_id"],
                "properties": {
                    "session_id": { "type": "integer" }
                }
            }
        }),
        json!({
            "name": "apply_operations",
            "description": "semantic operation 배열을 batch로 적용하고 이벤트 로그를 반환합니다.",
            "inputSchema": {
                "type": "object",
                "required": ["session_id", "operations"],
                "properties": {
                    "session_id": { "type": "integer" },
                    "operations": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "required": ["op"],
                            "properties": {
                                "op": { "type": "string" },
                                "payload": { "type": "object" }
                            }
                        }
                    }
                }
            }
        }),
        json!({
            "name": "render_page",
            "description": "페이지를 render_tree/svg/text_layout/control_layout/page_info 형식으로 반환합니다.",
            "inputSchema": {
                "type": "object",
                "required": ["session_id", "page"],
                "properties": {
                    "session_id": { "type": "integer" },
                    "page": { "type": "integer" },
                    "format": {
                        "type": "string",
                        "enum": ["render_tree", "svg", "text_layout", "control_layout", "page_info"]
                    }
                }
            }
        }),
        json!({
            "name": "save_document",
            "description": "문서를 HWP로 저장합니다.",
            "inputSchema": {
                "type": "object",
                "required": ["session_id", "path"],
                "properties": {
                    "session_id": { "type": "integer" },
                    "path": { "type": "string" }
                }
            }
        }),
        json!({
            "name": "close_document",
            "description": "열린 세션을 종료합니다.",
            "inputSchema": {
                "type": "object",
                "required": ["session_id"],
                "properties": {
                    "session_id": { "type": "integer" }
                }
            }
        }),
    ]
}

fn call_tool(name: &str, arguments: &Value) -> Result<Value, String> {
    match name {
        "open_document" => {
            let path = req_str(arguments, "path")?;
            let handle = open_document_path(Path::new(path))?;
            Ok(text_result(json!({ "sessionId": handle }).to_string()))
        }
        "create_document" => {
            let handle = create_blank_document()?;
            Ok(text_result(json!({ "sessionId": handle }).to_string()))
        }
        "read_document" => {
            let session_id = req_session(arguments)?;
            Ok(text_result(read_document_json(session_id)?))
        }
        "apply_operations" => {
            let session_id = req_session(arguments)?;
            let operations_value = arguments
                .get("operations")
                .cloned()
                .ok_or_else(|| "operations 배열이 필요합니다".to_string())?;
            let operations: Vec<OperationRequest> = serde_json::from_value(operations_value)
                .map_err(|error| format!("operations 파싱 실패: {}", error))?;
            Ok(text_result(apply_operations(session_id, &operations)?))
        }
        "render_page" => {
            let session_id = req_session(arguments)?;
            let page = req_u32(arguments, "page")?;
            let format = arguments
                .get("format")
                .and_then(Value::as_str)
                .unwrap_or("render_tree");
            let rendered = match format {
                "render_tree" => get_page_render_tree_json(session_id, page)?,
                "svg" => render_page_svg(session_id, page)?,
                "text_layout" => get_page_text_layout_json(session_id, page)?,
                "control_layout" => get_page_control_layout_json(session_id, page)?,
                "page_info" => get_page_info_json(session_id, page)?,
                _ => return Err(format!("지원하지 않는 render format: {}", format)),
            };
            Ok(text_result(rendered))
        }
        "save_document" => {
            let session_id = req_session(arguments)?;
            let path = req_str(arguments, "path")?;
            Ok(text_result(save_document_to_path(session_id, Path::new(path))?))
        }
        "close_document" => {
            let session_id = req_session(arguments)?;
            close_document(session_id)?;
            Ok(text_result(json!({ "ok": true }).to_string()))
        }
        _ => Err(format!("지원하지 않는 도구: {}", name)),
    }
}

fn text_result(text: String) -> Value {
    json!({
        "content": [
            {
                "type": "text",
                "text": text
            }
        ]
    })
}

fn req_session(arguments: &Value) -> Result<SessionHandle, String> {
    let raw = arguments
        .get("session_id")
        .and_then(Value::as_u64)
        .ok_or_else(|| "session_id 가 필요합니다".to_string())?;
    Ok(raw)
}

fn req_str<'a>(arguments: &'a Value, key: &str) -> Result<&'a str, String> {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{} 가 필요합니다", key))
}

fn req_u32(arguments: &Value, key: &str) -> Result<u32, String> {
    let raw = arguments
        .get(key)
        .and_then(Value::as_u64)
        .ok_or_else(|| format!("{} 가 필요합니다", key))?;
    u32::try_from(raw).map_err(|_| format!("{} 값이 너무 큽니다", key))
}
