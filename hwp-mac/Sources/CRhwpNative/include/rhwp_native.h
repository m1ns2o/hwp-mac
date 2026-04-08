#ifndef RHWP_NATIVE_H
#define RHWP_NATIVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t rhwp_session_open(const uint8_t *data, size_t len);
uint64_t rhwp_session_open_with_path(const uint8_t *data, size_t len, const char *source_path);
uint64_t rhwp_session_create_blank(void);
bool rhwp_session_close(uint64_t handle);

char *rhwp_session_get_document_info(uint64_t handle);
char *rhwp_session_get_page_info(uint64_t handle, uint32_t page_num);
char *rhwp_session_get_page_text_layout(uint64_t handle, uint32_t page_num);
char *rhwp_session_get_page_control_layout(uint64_t handle, uint32_t page_num);
char *rhwp_session_get_page_render_tree(uint64_t handle, uint32_t page_num);
char *rhwp_session_render_page_svg(uint64_t handle, uint32_t page_num);

char *rhwp_session_begin_batch(uint64_t handle);
char *rhwp_session_end_batch(uint64_t handle);
char *rhwp_session_get_event_log(uint64_t handle);

uint32_t rhwp_session_save_snapshot(uint64_t handle);
char *rhwp_session_restore_snapshot(uint64_t handle, uint32_t snapshot_id);
bool rhwp_session_discard_snapshot(uint64_t handle, uint32_t snapshot_id);

char *rhwp_session_apply_operation(uint64_t handle, const char *operation, const char *payload_json);
uint8_t *rhwp_session_export_hwp(uint64_t handle, size_t *out_len);

char *rhwp_last_error_message(void);
void rhwp_string_free(char *value);
void rhwp_bytes_free(uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif
