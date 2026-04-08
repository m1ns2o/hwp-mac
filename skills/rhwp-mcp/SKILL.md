---
name: rhwp-mcp
description: Use when inspecting or editing HWP/HWPX documents through this repository's Rust MCP server. Opens a document, reads structure, applies semantic batch operations, renders pages for verification, saves back to HWP, and closes the session.
---

# RHWP MCP

Use this skill when the task is document inspection or transformation and the safest path is to operate through the Rust engine instead of UI automation.

## Default workflow

1. Start from the repository root and run `cargo run --bin rhwp-mcp`.
2. Open with `open_document`, or create with `create_document`.
3. Call `read_document` first to inspect metadata, fields, bookmarks, and page count.
4. Use `render_page` with `page_info`, `text_layout`, or `render_tree` before editing when placement matters.
5. Apply edits through `apply_operations`.
6. Re-render the affected pages to verify layout and cursor movement.
7. Save with `save_document`.
8. Always finish with `close_document`.

## Editing guidance

- Prefer one `apply_operations` call with multiple semantic ops over many one-off mutations.
- Keep operations semantic. Examples: `insert_text`, `delete_text`, `split_paragraph`, `move_vertical`, `apply_char_format`, `create_table`.
- When coordinates are involved, derive them from `render_page` or use semantic positions returned by `hit_test` and cursor APIs.
- Treat HWPX as an input/edit format for phase 1, but save output as HWP unless a separate HWPX save path is explicitly implemented.

## Verification order

- Verify page count and page metrics first.
- Then verify caret rect or hit-test result.
- Then verify affected render tree or SVG output.
- Only after verification save the document.

## Failure handling

- If `apply_operations` fails, inspect the failing op and retry with a smaller batch.
- If rendering looks wrong, compare `render_tree` and `svg` for the same page before assuming the Swift app is wrong.
- If the document uses nested table or textbox editing, explicitly check `cellContext`-related outputs before further mutations.
