use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::ptr;
use std::sync::{Mutex, OnceLock};

use super::{
    apply_operation, begin_batch, close_document, create_blank_document, discard_snapshot, end_batch,
    export_hwp_bytes, get_document_info_json, get_event_log_json, get_page_control_layout_json,
    get_page_info_json, get_page_render_tree_json, get_page_text_layout_json, open_document_bytes,
    render_page_svg, restore_snapshot, save_snapshot, SessionHandle,
};

static LAST_ERROR: OnceLock<Mutex<String>> = OnceLock::new();

fn last_error() -> &'static Mutex<String> {
    LAST_ERROR.get_or_init(|| Mutex::new(String::new()))
}

fn set_last_error(message: impl Into<String>) {
    if let Ok(mut guard) = last_error().lock() {
        *guard = message.into();
    }
}

fn take_c_string(result: Result<String, String>) -> *mut c_char {
    match result {
        Ok(value) => CString::new(value).map(CString::into_raw).unwrap_or(ptr::null_mut()),
        Err(error) => {
            set_last_error(error);
            ptr::null_mut()
        }
    }
}

fn c_string_arg(value: *const c_char, field_name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{} 포인터가 null 입니다", field_name));
    }
    let c_str = unsafe { CStr::from_ptr(value) };
    c_str
        .to_str()
        .map(|text| text.to_string())
        .map_err(|error| format!("{} UTF-8 디코딩 실패: {}", field_name, error))
}

#[no_mangle]
pub extern "C" fn rhwp_session_open(data: *const u8, len: usize) -> SessionHandle {
    if data.is_null() || len == 0 {
        set_last_error("문서 바이트가 비어 있습니다");
        return 0;
    }

    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    match open_document_bytes(bytes, None) {
        Ok(handle) => handle,
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_session_open_with_path(
    data: *const u8,
    len: usize,
    source_path: *const c_char,
) -> SessionHandle {
    if data.is_null() || len == 0 {
        set_last_error("문서 바이트가 비어 있습니다");
        return 0;
    }

    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    let path = match c_string_arg(source_path, "source_path") {
        Ok(value) => Some(PathBuf::from(value)),
        Err(error) => {
            set_last_error(error);
            return 0;
        }
    };

    match open_document_bytes(bytes, path) {
        Ok(handle) => handle,
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_session_create_blank() -> SessionHandle {
    match create_blank_document() {
        Ok(handle) => handle,
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_session_close(handle: SessionHandle) -> bool {
    match close_document(handle) {
        Ok(()) => true,
        Err(error) => {
            set_last_error(error);
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_session_get_document_info(handle: SessionHandle) -> *mut c_char {
    take_c_string(get_document_info_json(handle))
}

#[no_mangle]
pub extern "C" fn rhwp_session_get_page_info(handle: SessionHandle, page_num: u32) -> *mut c_char {
    take_c_string(get_page_info_json(handle, page_num))
}

#[no_mangle]
pub extern "C" fn rhwp_session_get_page_text_layout(handle: SessionHandle, page_num: u32) -> *mut c_char {
    take_c_string(get_page_text_layout_json(handle, page_num))
}

#[no_mangle]
pub extern "C" fn rhwp_session_get_page_control_layout(handle: SessionHandle, page_num: u32) -> *mut c_char {
    take_c_string(get_page_control_layout_json(handle, page_num))
}

#[no_mangle]
pub extern "C" fn rhwp_session_get_page_render_tree(handle: SessionHandle, page_num: u32) -> *mut c_char {
    take_c_string(get_page_render_tree_json(handle, page_num))
}

#[no_mangle]
pub extern "C" fn rhwp_session_render_page_svg(handle: SessionHandle, page_num: u32) -> *mut c_char {
    take_c_string(render_page_svg(handle, page_num))
}

#[no_mangle]
pub extern "C" fn rhwp_session_begin_batch(handle: SessionHandle) -> *mut c_char {
    take_c_string(begin_batch(handle))
}

#[no_mangle]
pub extern "C" fn rhwp_session_end_batch(handle: SessionHandle) -> *mut c_char {
    take_c_string(end_batch(handle))
}

#[no_mangle]
pub extern "C" fn rhwp_session_get_event_log(handle: SessionHandle) -> *mut c_char {
    take_c_string(get_event_log_json(handle))
}

#[no_mangle]
pub extern "C" fn rhwp_session_save_snapshot(handle: SessionHandle) -> u32 {
    match save_snapshot(handle) {
        Ok(snapshot_id) => snapshot_id,
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_session_restore_snapshot(handle: SessionHandle, snapshot_id: u32) -> *mut c_char {
    take_c_string(restore_snapshot(handle, snapshot_id))
}

#[no_mangle]
pub extern "C" fn rhwp_session_discard_snapshot(handle: SessionHandle, snapshot_id: u32) -> bool {
    match discard_snapshot(handle, snapshot_id) {
        Ok(()) => true,
        Err(error) => {
            set_last_error(error);
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_session_apply_operation(
    handle: SessionHandle,
    operation: *const c_char,
    payload_json: *const c_char,
) -> *mut c_char {
    let operation = match c_string_arg(operation, "operation") {
        Ok(value) => value,
        Err(error) => {
            set_last_error(error);
            return ptr::null_mut();
        }
    };
    let payload_json = if payload_json.is_null() {
        String::new()
    } else {
        match c_string_arg(payload_json, "payload_json") {
            Ok(value) => value,
            Err(error) => {
                set_last_error(error);
                return ptr::null_mut();
            }
        }
    };

    take_c_string(apply_operation(handle, &operation, &payload_json))
}

#[no_mangle]
pub extern "C" fn rhwp_session_export_hwp(
    handle: SessionHandle,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        set_last_error("out_len 포인터가 null 입니다");
        return ptr::null_mut();
    }

    match export_hwp_bytes(handle) {
        Ok(mut bytes) => {
            let len = bytes.len();
            let ptr = bytes.as_mut_ptr();
            unsafe {
                *out_len = len;
            }
            std::mem::forget(bytes);
            ptr
        }
        Err(error) => {
            set_last_error(error);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn rhwp_string_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

#[no_mangle]
pub extern "C" fn rhwp_bytes_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    unsafe {
        drop(Vec::from_raw_parts(ptr, len, len));
    }
}

#[no_mangle]
pub extern "C" fn rhwp_last_error_message() -> *mut c_char {
    let message = last_error()
        .lock()
        .map(|value| value.clone())
        .unwrap_or_else(|_| "알 수 없는 native API 오류".to_string());
    CString::new(message)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}
