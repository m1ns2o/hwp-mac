pub mod ffi;
mod render_tree_json;

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::document_core::DocumentCore;

pub type SessionHandle = u64;

pub struct NativeDocumentSession {
    pub core: DocumentCore,
    pub source_path: Option<PathBuf>,
}

#[derive(Default)]
struct SessionStore {
    next_handle: SessionHandle,
    sessions: HashMap<SessionHandle, NativeDocumentSession>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OperationRequest {
    pub op: String,
    #[serde(default)]
    pub payload: Value,
}

static SESSION_STORE: OnceLock<Mutex<SessionStore>> = OnceLock::new();

fn store() -> &'static Mutex<SessionStore> {
    SESSION_STORE.get_or_init(|| {
        Mutex::new(SessionStore {
            next_handle: 1,
            sessions: HashMap::new(),
        })
    })
}

fn parse_json_fragment(raw: &str) -> Value {
    serde_json::from_str(raw).unwrap_or_else(|_| json!({ "raw": raw }))
}

fn next_handle(store: &mut SessionStore) -> SessionHandle {
    let handle = store.next_handle.max(1);
    store.next_handle = handle.saturating_add(1);
    handle
}

fn with_session<T, F>(handle: SessionHandle, f: F) -> Result<T, String>
where
    F: FnOnce(&NativeDocumentSession) -> Result<T, String>,
{
    let store = store().lock().map_err(|_| "세션 저장소 잠금 실패".to_string())?;
    let session = store
        .sessions
        .get(&handle)
        .ok_or_else(|| format!("세션 {} 을(를) 찾을 수 없습니다", handle))?;
    f(session)
}

fn with_session_mut<T, F>(handle: SessionHandle, f: F) -> Result<T, String>
where
    F: FnOnce(&mut NativeDocumentSession) -> Result<T, String>,
{
    let mut store = store().lock().map_err(|_| "세션 저장소 잠금 실패".to_string())?;
    let session = store
        .sessions
        .get_mut(&handle)
        .ok_or_else(|| format!("세션 {} 을(를) 찾을 수 없습니다", handle))?;
    f(session)
}

pub fn open_document_bytes(data: &[u8], source_path: Option<PathBuf>) -> Result<SessionHandle, String> {
    let mut core = DocumentCore::from_bytes(data).map_err(|error| error.to_string())?;
    let _ = core.convert_to_editable_native();

    let mut store = store().lock().map_err(|_| "세션 저장소 잠금 실패".to_string())?;
    let handle = next_handle(&mut store);
    store.sessions.insert(handle, NativeDocumentSession { core, source_path });
    Ok(handle)
}

pub fn open_document_path(path: &Path) -> Result<SessionHandle, String> {
    let bytes = fs::read(path).map_err(|error| format!("문서를 읽을 수 없습니다: {}", error))?;
    open_document_bytes(&bytes, Some(path.to_path_buf()))
}

pub fn create_blank_document() -> Result<SessionHandle, String> {
    let mut core = DocumentCore::new_empty();
    core.create_blank_document_native().map_err(|error| error.to_string())?;

    let mut store = store().lock().map_err(|_| "세션 저장소 잠금 실패".to_string())?;
    let handle = next_handle(&mut store);
    store.sessions.insert(
        handle,
        NativeDocumentSession {
            core,
            source_path: None,
        },
    );
    Ok(handle)
}

pub fn close_document(handle: SessionHandle) -> Result<(), String> {
    let mut store = store().lock().map_err(|_| "세션 저장소 잠금 실패".to_string())?;
    store
        .sessions
        .remove(&handle)
        .map(|_| ())
        .ok_or_else(|| format!("세션 {} 을(를) 찾을 수 없습니다", handle))
}

pub fn get_document_info_json(handle: SessionHandle) -> Result<String, String> {
    with_session(handle, |session| Ok(session.core.get_document_info()))
}

pub fn get_page_info_json(handle: SessionHandle, page_num: u32) -> Result<String, String> {
    with_session(handle, |session| {
        session
            .core
            .get_page_info_native(page_num)
            .map_err(|error| error.to_string())
    })
}

pub fn get_page_text_layout_json(handle: SessionHandle, page_num: u32) -> Result<String, String> {
    with_session(handle, |session| {
        session
            .core
            .get_page_text_layout_native(page_num)
            .map_err(|error| error.to_string())
    })
}

pub fn get_page_control_layout_json(handle: SessionHandle, page_num: u32) -> Result<String, String> {
    with_session(handle, |session| {
        session
            .core
            .get_page_control_layout_native(page_num)
            .map_err(|error| error.to_string())
    })
}

pub fn get_page_render_tree_json(handle: SessionHandle, page_num: u32) -> Result<String, String> {
    with_session(handle, |session| {
        let tree = session
            .core
            .build_page_tree_cached(page_num)
            .map_err(|error| error.to_string())?;
        Ok(render_tree_json::serialize_page_tree(&tree.root))
    })
}

pub fn render_page_svg(handle: SessionHandle, page_num: u32) -> Result<String, String> {
    with_session(handle, |session| {
        session
            .core
            .render_page_svg_native(page_num)
            .map_err(|error| error.to_string())
    })
}

pub fn export_hwp_bytes(handle: SessionHandle) -> Result<Vec<u8>, String> {
    with_session(handle, |session| {
        session
            .core
            .export_hwp_native()
            .map_err(|error| error.to_string())
    })
}

pub fn save_document_to_path(handle: SessionHandle, path: &Path) -> Result<String, String> {
    let bytes = export_hwp_bytes(handle)?;
    fs::write(path, &bytes).map_err(|error| format!("문서를 저장할 수 없습니다: {}", error))?;

    with_session_mut(handle, |session| {
        session.source_path = Some(path.to_path_buf());
        Ok(json!({
            "ok": true,
            "path": path.to_string_lossy(),
            "bytesWritten": bytes.len(),
        })
        .to_string())
    })
}

pub fn begin_batch(handle: SessionHandle) -> Result<String, String> {
    with_session_mut(handle, |session| {
        session
            .core
            .begin_batch_native()
            .map_err(|error| error.to_string())
    })
}

pub fn end_batch(handle: SessionHandle) -> Result<String, String> {
    with_session_mut(handle, |session| {
        session
            .core
            .end_batch_native()
            .map_err(|error| error.to_string())
    })
}

pub fn get_event_log_json(handle: SessionHandle) -> Result<String, String> {
    with_session(handle, |session| Ok(session.core.serialize_event_log()))
}

pub fn save_snapshot(handle: SessionHandle) -> Result<u32, String> {
    with_session_mut(handle, |session| Ok(session.core.save_snapshot_native()))
}

pub fn restore_snapshot(handle: SessionHandle, snapshot_id: u32) -> Result<String, String> {
    with_session_mut(handle, |session| {
        session
            .core
            .restore_snapshot_native(snapshot_id)
            .map_err(|error| error.to_string())
    })
}

pub fn discard_snapshot(handle: SessionHandle, snapshot_id: u32) -> Result<(), String> {
    with_session_mut(handle, |session| {
        session.core.discard_snapshot_native(snapshot_id);
        Ok(())
    })
}

pub fn read_document_json(handle: SessionHandle) -> Result<String, String> {
    with_session(handle, |session| {
        let page_count = session.core.page_count();
        let pages = (0..page_count)
            .map(|page_num| {
                session
                    .core
                    .get_page_info_native(page_num)
                    .map(|raw| parse_json_fragment(&raw))
                    .unwrap_or_else(|error| json!({ "page": page_num, "error": error.to_string() }))
            })
            .collect::<Vec<_>>();

        let bookmarks = session
            .core
            .get_bookmarks_native()
            .map(|raw| parse_json_fragment(&raw))
            .unwrap_or_else(|_| json!([]));

        Ok(json!({
            "sessionId": handle,
            "sourcePath": session.source_path.as_ref().map(|path| path.to_string_lossy().to_string()),
            "documentInfo": parse_json_fragment(&session.core.get_document_info()),
            "fields": parse_json_fragment(&session.core.get_field_list_json()),
            "bookmarks": bookmarks,
            "pages": pages,
        })
        .to_string())
    })
}

pub fn apply_operation(handle: SessionHandle, op: &str, payload_json: &str) -> Result<String, String> {
    let payload = if payload_json.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str(payload_json).map_err(|error| format!("payload JSON 파싱 실패: {}", error))?
    };

    with_session_mut(handle, |session| dispatch_operation(&mut session.core, op, &payload))
}

pub fn apply_operations(handle: SessionHandle, operations: &[OperationRequest]) -> Result<String, String> {
    with_session_mut(handle, |session| {
        session
            .core
            .begin_batch_native()
            .map_err(|error| error.to_string())?;

        let mut results = Vec::with_capacity(operations.len());
        for operation in operations {
            match dispatch_operation(&mut session.core, &operation.op, &operation.payload) {
                Ok(result) => results.push(json!({
                    "op": operation.op,
                    "ok": true,
                    "result": parse_json_fragment(&result),
                })),
                Err(error) => {
                    session.core.batch_mode = false;
                    session.core.event_log.clear();
                    return Err(format!("{}: {}", operation.op, error));
                }
            }
        }

        session.core.batch_mode = false;
        session.core.paginate();
        let event_log = parse_json_fragment(&session.core.serialize_event_log());
        session.core.event_log.clear();

        Ok(json!({
            "ok": true,
            "results": results,
            "eventLog": event_log,
        })
        .to_string())
    })
}

fn dispatch_operation(core: &mut DocumentCore, op: &str, payload: &Value) -> Result<String, String> {
    match op {
        "insert_text" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            let text = req_str(payload, "text")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.insert_text_in_cell_native(sec, parent_para, control_index, cell_index, cell_para, char_offset, text)
                    .map_err(|error| error.to_string())
            } else {
                core.insert_text_native(sec, para, char_offset, text)
                    .map_err(|error| error.to_string())
            }
        }
        "delete_text" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            let count = req_usize(payload, "count")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.delete_text_in_cell_native(sec, parent_para, control_index, cell_index, cell_para, char_offset, count)
                    .map_err(|error| error.to_string())
            } else {
                core.delete_text_native(sec, para, char_offset, count)
                    .map_err(|error| error.to_string())
            }
        }
        "delete_range" => {
            let sec = req_usize(payload, "sec")?;
            let start_para = req_usize(payload, "startPara")?;
            let start_char = req_usize(payload, "startCharOffset")?;
            let end_para = req_usize(payload, "endPara")?;
            let end_char = req_usize(payload, "endCharOffset")?;
            let cell_ctx = cell_context(payload)?.map(|(parent_para, control_index, cell_index, _)| {
                (parent_para, control_index, cell_index)
            });
            core.delete_range_native(sec, start_para, start_char, end_para, end_char, cell_ctx)
                .map_err(|error| error.to_string())
        }
        "split_paragraph" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.split_paragraph_in_cell_native(sec, parent_para, control_index, cell_index, cell_para, char_offset)
                    .map_err(|error| error.to_string())
            } else {
                core.split_paragraph_native(sec, para, char_offset)
                    .map_err(|error| error.to_string())
            }
        }
        "merge_paragraph" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.merge_paragraph_in_cell_native(sec, parent_para, control_index, cell_index, cell_para)
                    .map_err(|error| error.to_string())
            } else {
                core.merge_paragraph_native(sec, para)
                    .map_err(|error| error.to_string())
            }
        }
        "insert_page_break" => core
            .insert_page_break_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "charOffset")?)
            .map_err(|error| error.to_string()),
        "insert_column_break" => core
            .insert_column_break_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "charOffset")?)
            .map_err(|error| error.to_string()),
        "get_cursor_rect" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.get_cursor_rect_in_cell_native(sec, parent_para, control_index, cell_index, cell_para, char_offset)
                    .map_err(|error| error.to_string())
            } else {
                core.get_cursor_rect_native(sec, para, char_offset)
                    .map_err(|error| error.to_string())
            }
        }
        "get_selection_rects" => {
            let sec = req_usize(payload, "sec")?;
            let start_para = req_usize(payload, "startPara")?;
            let start_char = req_usize(payload, "startCharOffset")?;
            let end_para = req_usize(payload, "endPara")?;
            let end_char = req_usize(payload, "endCharOffset")?;
            let cell_ctx = cell_context(payload)?.map(|(parent_para, control_index, cell_index, _)| {
                (parent_para, control_index, cell_index)
            });
            core.get_selection_rects_native(sec, start_para, start_char, end_para, end_char, cell_ctx)
                .map_err(|error| error.to_string())
        }
        "get_paragraph_length" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            if let Some((parent_para, control_index, cell_index, _)) = cell_context(payload)? {
                core.get_cell_paragraph_length_native(sec, parent_para, control_index, cell_index, para)
                    .map(|length| json!({ "length": length }).to_string())
                    .map_err(|error| error.to_string())
            } else {
                core.get_paragraph_length_native(sec, para)
                    .map(|length| json!({ "length": length }).to_string())
                    .map_err(|error| error.to_string())
            }
        }
        "get_text_range" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            let count = req_usize(payload, "count")?;
            if let Some((parent_para, control_index, cell_index, _)) = cell_context(payload)? {
                core.get_text_in_cell_native(sec, parent_para, control_index, cell_index, para, char_offset, count)
                    .map_err(|error| error.to_string())
            } else {
                core.get_text_range_native(sec, para, char_offset, count)
                    .map_err(|error| error.to_string())
            }
        }
        "get_paragraph_count" => {
            let sec = req_usize(payload, "sec")?;
            if let Some((parent_para, control_index, cell_index, _)) = cell_context(payload)? {
                core.get_cell_paragraph_count_native(sec, parent_para, control_index, cell_index)
                    .map(|count| json!({ "count": count }).to_string())
                    .map_err(|error| error.to_string())
            } else {
                core.get_paragraph_count_native(sec)
                    .map(|count| json!({ "count": count }).to_string())
                    .map_err(|error| error.to_string())
            }
        }
        "hit_test" => core
            .hit_test_native(req_u32(payload, "pageNum")?, req_f64(payload, "x")?, req_f64(payload, "y")?)
            .map_err(|error| error.to_string()),
        "move_vertical" => core
            .move_vertical_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "para")?,
                req_usize(payload, "charOffset")?,
                req_i32(payload, "delta")?,
                opt_f64(payload, "preferredX").unwrap_or(-1.0),
                cell_context(payload)?,
            )
            .map_err(|error| error.to_string()),
        "search_text" => core
            .search_text_native(
                req_str(payload, "query")?,
                req_usize(payload, "fromSec")?,
                req_usize(payload, "fromPara")?,
                req_usize(payload, "fromChar")?,
                opt_bool(payload, "forward").unwrap_or(true),
                opt_bool(payload, "caseSensitive").unwrap_or(false),
            )
            .map_err(|error| error.to_string()),
        "replace_text" => core
            .replace_text_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "para")?,
                req_usize(payload, "charOffset")?,
                req_usize(payload, "length")?,
                req_str(payload, "newText")?,
            )
            .map_err(|error| error.to_string()),
        "replace_all" => core
            .replace_all_native(
                req_str(payload, "query")?,
                req_str(payload, "newText")?,
                opt_bool(payload, "caseSensitive").unwrap_or(false),
            )
            .map_err(|error| error.to_string()),
        "copy_selection" => {
            let sec = req_usize(payload, "sec")?;
            let start_para = req_usize(payload, "startPara")?;
            let start_char = req_usize(payload, "startCharOffset")?;
            let end_para = req_usize(payload, "endPara")?;
            let end_char = req_usize(payload, "endCharOffset")?;
            if let Some((parent_para, control_index, cell_index, _)) = cell_context(payload)? {
                core.copy_selection_in_cell_native(
                    sec,
                    parent_para,
                    control_index,
                    cell_index,
                    start_para,
                    start_char,
                    end_para,
                    end_char,
                )
                .map_err(|error| error.to_string())
            } else {
                core.copy_selection_native(sec, start_para, start_char, end_para, end_char)
                    .map_err(|error| error.to_string())
            }
        }
        "paste_internal" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.paste_internal_in_cell_native(sec, parent_para, control_index, cell_index, cell_para, char_offset)
                    .map_err(|error| error.to_string())
            } else {
                core.paste_internal_native(sec, para, char_offset)
                    .map_err(|error| error.to_string())
            }
        }
        "copy_control" => core
            .copy_control_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "controlIndex")?)
            .map_err(|error| error.to_string()),
        "paste_control" => core
            .paste_control_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "charOffset")?)
            .map_err(|error| error.to_string()),
        "get_char_properties" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let char_offset = req_usize(payload, "charOffset")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.get_cell_char_properties_at_native(sec, parent_para, control_index, cell_index, cell_para, char_offset)
                    .map_err(|error| error.to_string())
            } else {
                core.get_char_properties_at_native(sec, para, char_offset)
                    .map_err(|error| error.to_string())
            }
        }
        "get_para_properties" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.get_cell_para_properties_at_native(sec, parent_para, control_index, cell_index, cell_para)
                    .map_err(|error| error.to_string())
            } else {
                core.get_para_properties_at_native(sec, para)
                    .map_err(|error| error.to_string())
            }
        }
        "apply_char_format" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let start_offset = req_usize(payload, "startOffset")?;
            let end_offset = req_usize(payload, "endOffset")?;
            let props = json_field(payload, "props")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.apply_char_format_in_cell_native(
                    sec,
                    parent_para,
                    control_index,
                    cell_index,
                    cell_para,
                    start_offset,
                    end_offset,
                    &props,
                )
                .map_err(|error| error.to_string())
            } else {
                core.apply_char_format_native(sec, para, start_offset, end_offset, &props)
                    .map_err(|error| error.to_string())
            }
        }
        "apply_para_format" => {
            let sec = req_usize(payload, "sec")?;
            let para = req_usize(payload, "para")?;
            let props = json_field(payload, "props")?;
            if let Some((parent_para, control_index, cell_index, cell_para)) = cell_context(payload)? {
                core.apply_para_format_in_cell_native(sec, parent_para, control_index, cell_index, cell_para, &props)
                    .map_err(|error| error.to_string())
            } else {
                core.apply_para_format_native(sec, para, &props)
                    .map_err(|error| error.to_string())
            }
        }
        "find_or_create_font_id" => Ok(json!({
            "id": core.find_or_create_font_id_native(req_str(payload, "name")?)
        }).to_string()),
        "ensure_default_numbering" => {
            use crate::model::style::{Numbering, NumberingHead};

            let id = if core.document.doc_info.numberings.is_empty() {
                let mut numbering = Numbering::default();
                numbering.level_formats = [
                    "^1.".to_string(),
                    "^2)".to_string(),
                    "^3)".to_string(),
                    "^4)".to_string(),
                    "^5)".to_string(),
                    "^6)".to_string(),
                    "^7)".to_string(),
                ];
                numbering.start_number = 1;
                numbering.level_start_numbers = [1; 7];
                numbering.heads[0] = NumberingHead { number_format: 0, ..Default::default() };
                numbering.heads[1] = NumberingHead { number_format: 8, ..Default::default() };
                numbering.heads[2] = NumberingHead { number_format: 0, ..Default::default() };
                numbering.heads[3] = NumberingHead { number_format: 8, ..Default::default() };
                numbering.heads[4] = NumberingHead { number_format: 1, ..Default::default() };
                numbering.heads[5] = NumberingHead { number_format: 10, ..Default::default() };
                numbering.heads[6] = NumberingHead { number_format: 5, ..Default::default() };
                core.document.doc_info.numberings.push(numbering);
                1
            } else {
                1
            };

            Ok(json!({ "id": id }).to_string())
        }
        "ensure_default_bullet" => {
            let bullet_ch = req_str(payload, "char")?.chars().next().unwrap_or('●');
            let mut found_id = None;
            for (index, bullet) in core.document.doc_info.bullets.iter().enumerate() {
                let mapped = crate::renderer::layout::map_pua_bullet_char(bullet.bullet_char);
                if mapped == bullet_ch {
                    found_id = Some(index + 1);
                    break;
                }
            }

            let id = if let Some(found_id) = found_id {
                found_id
            } else {
                use crate::model::style::Bullet;
                let bullet = Bullet {
                    bullet_char: bullet_ch,
                    text_distance: 50,
                    ..Default::default()
                };
                core.document.doc_info.bullets.push(bullet);
                core.document.doc_info.bullets.len()
            };

            Ok(json!({ "id": id }).to_string())
        }
        "create_table" => core
            .create_table_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "para")?,
                req_usize(payload, "charOffset")?,
                req_u16(payload, "rows")?,
                req_u16(payload, "cols")?,
            )
            .map_err(|error| error.to_string()),
        "insert_table_row" => core
            .insert_table_row_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_u16(payload, "row")?,
                opt_bool(payload, "after").unwrap_or(true),
            )
            .map_err(|error| error.to_string()),
        "insert_table_column" => core
            .insert_table_column_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_u16(payload, "column")?,
                opt_bool(payload, "after").unwrap_or(true),
            )
            .map_err(|error| error.to_string()),
        "delete_table_row" => core
            .delete_table_row_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_u16(payload, "row")?,
            )
            .map_err(|error| error.to_string()),
        "delete_table_column" => core
            .delete_table_column_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_u16(payload, "column")?,
            )
            .map_err(|error| error.to_string()),
        "merge_table_cells" => core
            .merge_table_cells_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_u16(payload, "startRow")?,
                req_u16(payload, "startCol")?,
                req_u16(payload, "endRow")?,
                req_u16(payload, "endCol")?,
            )
            .map_err(|error| error.to_string()),
        "split_table_cell" => core
            .split_table_cell_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_u16(payload, "row")?,
                req_u16(payload, "col")?,
            )
            .map_err(|error| error.to_string()),
        "get_table_dimensions" => core
            .get_table_dimensions_native(req_usize(payload, "sec")?, req_usize(payload, "parentPara")?, req_usize(payload, "controlIndex")?)
            .map_err(|error| error.to_string()),
        "get_cell_properties" => core
            .get_cell_properties_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_usize(payload, "cellIndex")?,
            )
            .map_err(|error| error.to_string()),
        "get_cell_info" => core
            .get_cell_info_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_usize(payload, "cellIndex")?,
            )
            .map_err(|error| error.to_string()),
        "set_cell_properties" => core
            .set_cell_properties_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                req_usize(payload, "cellIndex")?,
                &json_field(payload, "props")?,
            )
            .map_err(|error| error.to_string()),
        "get_table_properties" => core
            .get_table_properties_native(req_usize(payload, "sec")?, req_usize(payload, "parentPara")?, req_usize(payload, "controlIndex")?)
            .map_err(|error| error.to_string()),
        "set_table_properties" => core
            .set_table_properties_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "parentPara")?,
                req_usize(payload, "controlIndex")?,
                &json_field(payload, "props")?,
            )
            .map_err(|error| error.to_string()),
        "delete_table_control" => core
            .delete_table_control_native(req_usize(payload, "sec")?, req_usize(payload, "parentPara")?, req_usize(payload, "controlIndex")?)
            .map_err(|error| error.to_string()),
        "get_page_def" => core
            .get_page_def_native(req_usize(payload, "sec")?)
            .map_err(|error| error.to_string()),
        "set_page_def" => core
            .set_page_def_native(req_usize(payload, "sec")?, &json_field(payload, "props")?)
            .map_err(|error| error.to_string()),
        "set_page_def_all" => core
            .set_page_def_all_native(&json_field(payload, "props")?)
            .map_err(|error| error.to_string()),
        "get_section_def" => core
            .get_section_def_native(req_usize(payload, "sec")?)
            .map_err(|error| error.to_string()),
        "set_section_def" => core
            .set_section_def_native(req_usize(payload, "sec")?, &json_field(payload, "props")?)
            .map_err(|error| error.to_string()),
        "set_section_def_all" => core
            .set_section_def_all_native(&json_field(payload, "props")?)
            .map_err(|error| error.to_string()),
        "get_header_footer" => core
            .get_header_footer_native(
                req_usize(payload, "sec")?,
                req_bool(payload, "isHeader")?,
                req_u8(payload, "applyTo")?,
            )
            .map_err(|error| error.to_string()),
        "get_header_footer_list" => core
            .get_header_footer_list_native(
                req_usize(payload, "sec")?,
                req_bool(payload, "isHeader")?,
                req_u8(payload, "applyTo")?,
            )
            .map_err(|error| error.to_string()),
        "delete_header_footer" => core
            .delete_header_footer_native(
                req_usize(payload, "sec")?,
                req_bool(payload, "isHeader")?,
                req_u8(payload, "applyTo")?,
            )
            .map_err(|error| error.to_string()),
        "apply_header_footer_template" => core
            .apply_hf_template_native(
                req_usize(payload, "sec")?,
                req_bool(payload, "isHeader")?,
                req_u8(payload, "applyTo")?,
                req_u8(payload, "templateId")?,
            )
            .map_err(|error| error.to_string()),
        "get_field_list" => Ok(core.get_field_list_json()),
        "get_field_value_by_name" => core
            .get_field_value_by_name(req_str(payload, "name")?)
            .map_err(|error| error.to_string()),
        "set_field_value_by_name" => core
            .set_field_value_by_name(req_str(payload, "name")?, req_str(payload, "value")?)
            .map_err(|error| error.to_string()),
        "get_form_object_at" => core
            .get_form_object_at_native(req_u32(payload, "pageNum")?, req_f64(payload, "x")?, req_f64(payload, "y")?)
            .map_err(|error| error.to_string()),
        "get_form_value" => core
            .get_form_value_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "controlIndex")?)
            .map_err(|error| error.to_string()),
        "set_form_value" => core
            .set_form_value_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "para")?,
                req_usize(payload, "controlIndex")?,
                &json_field(payload, "value")?,
            )
            .map_err(|error| error.to_string()),
        "insert_footnote" => core
            .insert_footnote_native(
                req_usize(payload, "sec")?,
                req_usize(payload, "para")?,
                req_usize(payload, "charOffset")?,
            )
            .map_err(|error| error.to_string()),
        "get_bookmarks" => core.get_bookmarks_native().map_err(|error| error.to_string()),
        "add_bookmark" => core
            .add_bookmark_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "charOffset")?, req_str(payload, "name")?)
            .map_err(|error| error.to_string()),
        "rename_bookmark" => core
            .rename_bookmark_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "controlIndex")?, req_str(payload, "name")?)
            .map_err(|error| error.to_string()),
        "delete_bookmark" => core
            .delete_bookmark_native(req_usize(payload, "sec")?, req_usize(payload, "para")?, req_usize(payload, "controlIndex")?)
            .map_err(|error| error.to_string()),
        _ => Err(format!("지원하지 않는 operation: {}", op)),
    }
}

fn cell_context(payload: &Value) -> Result<Option<(usize, usize, usize, usize)>, String> {
    match payload.get("cellContext") {
        None | Some(Value::Null) => Ok(None),
        Some(value) => Ok(Some((
            req_usize(value, "parentPara")?,
            req_usize(value, "controlIndex")?,
            req_usize(value, "cellIndex")?,
            req_usize(value, "cellParaIndex")?,
        ))),
    }
}

fn json_field(payload: &Value, key: &str) -> Result<String, String> {
    let value = payload
        .get(key)
        .ok_or_else(|| format!("필수 필드 '{}' 가 없습니다", key))?;
    serde_json::to_string(value).map_err(|error| format!("JSON 직렬화 실패({}): {}", key, error))
}

fn req_value<'a>(payload: &'a Value, key: &str) -> Result<&'a Value, String> {
    payload
        .get(key)
        .ok_or_else(|| format!("필수 필드 '{}' 가 없습니다", key))
}

fn req_str<'a>(payload: &'a Value, key: &str) -> Result<&'a str, String> {
    req_value(payload, key)?
        .as_str()
        .ok_or_else(|| format!("필드 '{}' 는 문자열이어야 합니다", key))
}

fn req_usize(payload: &Value, key: &str) -> Result<usize, String> {
    let number = req_value(payload, key)?
        .as_u64()
        .ok_or_else(|| format!("필드 '{}' 는 양의 정수여야 합니다", key))?;
    usize::try_from(number).map_err(|_| format!("필드 '{}' 값이 너무 큽니다", key))
}

fn req_u32(payload: &Value, key: &str) -> Result<u32, String> {
    let number = req_value(payload, key)?
        .as_u64()
        .ok_or_else(|| format!("필드 '{}' 는 양의 정수여야 합니다", key))?;
    u32::try_from(number).map_err(|_| format!("필드 '{}' 값이 너무 큽니다", key))
}

fn req_u8(payload: &Value, key: &str) -> Result<u8, String> {
    let number = req_value(payload, key)?
        .as_u64()
        .ok_or_else(|| format!("필드 '{}' 는 양의 정수여야 합니다", key))?;
    u8::try_from(number).map_err(|_| format!("필드 '{}' 값이 너무 큽니다", key))
}

fn req_u16(payload: &Value, key: &str) -> Result<u16, String> {
    let number = req_value(payload, key)?
        .as_u64()
        .ok_or_else(|| format!("필드 '{}' 는 양의 정수여야 합니다", key))?;
    u16::try_from(number).map_err(|_| format!("필드 '{}' 값이 너무 큽니다", key))
}

fn req_i32(payload: &Value, key: &str) -> Result<i32, String> {
    let number = req_value(payload, key)?
        .as_i64()
        .ok_or_else(|| format!("필드 '{}' 는 정수여야 합니다", key))?;
    i32::try_from(number).map_err(|_| format!("필드 '{}' 값이 너무 큽니다", key))
}

fn req_bool(payload: &Value, key: &str) -> Result<bool, String> {
    req_value(payload, key)?
        .as_bool()
        .ok_or_else(|| format!("필드 '{}' 는 bool 이어야 합니다", key))
}

fn req_f64(payload: &Value, key: &str) -> Result<f64, String> {
    req_value(payload, key)?
        .as_f64()
        .ok_or_else(|| format!("필드 '{}' 는 숫자여야 합니다", key))
}

fn opt_bool(payload: &Value, key: &str) -> Option<bool> {
    payload.get(key).and_then(Value::as_bool)
}

fn opt_f64(payload: &Value, key: &str) -> Option<f64> {
    payload.get(key).and_then(Value::as_f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blank_document_session_roundtrip() {
        let handle = create_blank_document().expect("blank session");

        let info = get_document_info_json(handle).expect("document info");
        assert!(info.contains("\"pageCount\""));

        let render_tree = get_page_render_tree_json(handle, 0).expect("render tree");
        assert!(render_tree.contains("\"type\":\"Page\""));

        let result = apply_operation(
            handle,
            "insert_text",
            r#"{"sec":0,"para":0,"charOffset":0,"text":"테스트"}"#,
        )
        .expect("insert text");
        assert!(result.contains("\"ok\":true"));

        let exported = export_hwp_bytes(handle).expect("export");
        assert!(!exported.is_empty());

        close_document(handle).expect("close");
    }
}
