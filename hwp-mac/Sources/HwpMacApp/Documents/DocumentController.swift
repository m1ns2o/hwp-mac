import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

private struct SelectionBounds {
    let start: RHWPCaretPosition
    let end: RHWPCaretPosition
}

private enum MutationRefreshPolicy {
    case full
    case editing
}

@MainActor
final class DocumentController: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var displayName: String = "Untitled"
    @Published private(set) var documentInfo: RHWPDocumentInfo?
    @Published private(set) var pageInfos: [RHWPPageInfo] = []
    @Published private(set) var currentCaret: RHWPCaretState?
    @Published private(set) var selection: RHWPSelectionState?
    @Published private(set) var selectionRects: [RHWPSelectionRect] = []
    @Published private(set) var charProperties: RHWPCharProperties?
    @Published private(set) var paraProperties: RHWPParaProperties?
    @Published private(set) var currentTableDimensions: RHWPTableDimensionsResult?
    @Published private(set) var currentCellInfo: RHWPCellInfoResult?
    @Published private(set) var currentCellProperties: RHWPCellProperties?
    @Published private(set) var currentTableProperties: RHWPTableProperties?
    @Published private(set) var bookmarks: [RHWPBookmark] = []
    @Published private(set) var fields: [RHWPFieldInfo] = []
    @Published var statusMessage: String = "문서를 열거나 새 문서를 만드세요."
    @Published var searchQuery: String = ""
    @Published var replaceQuery: String = ""
    @Published var searchCaseSensitive: Bool = false
    @Published var searchStatus: String = ""
    @Published var isDirty: Bool = false
    @Published var selectedPageIndex: Int = 0

    let viewportController = ViewportController()
    lazy var commandBus = CommandBus(documentController: self)

    private(set) var session: EditorSession?
    private var undoSnapshots: [UInt32] = []
    private var redoSnapshots: [UInt32] = []
    private var lastInternalClipboardText: String?
    private var deferredRefreshWorkItem: DispatchWorkItem?
    private var compositionUndoSnapshot: UInt32?

    var hasSession: Bool {
        session != nil
    }

    var hasSelection: Bool {
        normalizedSelection() != nil
    }

    var canUndo: Bool {
        !undoSnapshots.isEmpty
    }

    var canRedo: Bool {
        !redoSnapshots.isEmpty
    }

    var isEditingTable: Bool {
        currentTableDimensions != nil
    }

    func createNewDocument() {
        do {
            try loadBlankDocument()
            statusMessage = "새 문서를 만들었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openDocument(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try loadDocument(data: data, fileURL: url, displayName: url.lastPathComponent)
            statusMessage = "\(url.lastPathComponent)을(를) 열었습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveDocument(to explicitURL: URL? = nil) {
        guard session != nil else {
            statusMessage = "저장할 문서가 없습니다."
            return
        }

        let targetURL = explicitURL ?? fileURL
        guard let targetURL else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.data]
            panel.nameFieldStringValue = "document.hwp"
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            saveDocument(to: selectedURL)
            return
        }

        do {
            let data = try exportDocumentData()
            try data.write(to: targetURL, options: [.atomic])
            markSaved(fileURL: targetURL, displayName: targetURL.lastPathComponent)
            statusMessage = "\(targetURL.lastPathComponent)로 저장했습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveDocumentAs() {
        guard session != nil else {
            statusMessage = "저장할 문서가 없습니다."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? displayName

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        saveDocument(to: selectedURL)
    }

    func renameDisplayName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = trimmed
        statusMessage = "문서 이름을 변경했습니다."
    }

    func loadBlankDocument(displayName: String = "Untitled") throws {
        session?.close()
        session = try EditorSession.createBlank()
        fileURL = nil
        self.displayName = displayName
        resetLoadedState()
        try reloadDocumentState()
    }

    func loadDocument(data: Data, fileURL: URL? = nil, displayName: String? = nil) throws {
        session?.close()
        session = try EditorSession.open(data: data, sourcePath: fileURL?.path)
        self.fileURL = fileURL
        self.displayName = displayName ?? fileURL?.lastPathComponent ?? self.displayName
        resetLoadedState()
        try reloadDocumentState()
    }

    func exportDocumentData() throws -> Data {
        guard let session else {
            throw NativeBridgeError.missingSession
        }
        return try session.exportHwp()
    }

    func markSaved(fileURL: URL? = nil, displayName: String? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        }
        if let displayName {
            self.displayName = displayName
        } else if let fileURL {
            self.displayName = fileURL.lastPathComponent
        }
        isDirty = false
    }

    func reloadDocumentState() throws {
        guard let session else { throw NativeBridgeError.missingSession }
        cancelDeferredRefresh()
        let info = try session.documentInfo()
        documentInfo = info
        pageInfos = try (0..<info.pageCount).map { try session.pageInfo($0) }
        selectedPageIndex = min(selectedPageIndex, max(pageInfos.count - 1, 0))
        viewportController.reload(pageInfos: pageInfos)
        viewportController.invalidateCache()

        if pageInfos.isEmpty {
            currentCaret = nil
            selection = nil
            selectionRects = []
            charProperties = nil
            paraProperties = nil
            currentTableDimensions = nil
            currentCellInfo = nil
            currentCellProperties = nil
            currentTableProperties = nil
            bookmarks = []
            fields = []
            return
        }

        if let caret = currentCaret {
            currentCaret = try refreshedCaret(for: caret.position, preferredX: caret.preferredX)
        } else {
            currentCaret = try refreshedCaret(for: RHWPCaretPosition(
                sectionIndex: 0,
                paragraphIndex: 0,
                charOffset: 0
            ))
        }

        syncDerivedState()
        try refreshBookmarks()
        try refreshFields()
    }

    func renderTree(for pageIndex: Int) throws -> RHWPRenderNode {
        guard let session else { throw NativeBridgeError.missingSession }
        return try viewportController.renderTree(for: pageIndex, session: session)
    }

    func setZoom(_ zoom: CGFloat) {
        viewportController.zoom = max(0.25, min(zoom, 4.0))
    }

    func setCaretFromHit(pageIndex: Int, x: Double, y: Double, extendSelection: Bool = false, updateStatus: Bool = true) {
        guard let session else { return }

        do {
            let hit = try session.decodeResult(
                RHWPHitTestResult.self,
                operation: "hit_test",
                payload: [
                    "pageNum": pageIndex,
                    "x": x,
                    "y": y,
                ]
            )

            let position = position(from: hit)
            let anchor = extendSelection ? (selection?.anchor ?? currentCaret?.position ?? position) : nil
            try moveCaret(to: position, selectingFrom: anchor)

            if updateStatus {
                statusMessage = "페이지 \(pageIndex + 1)에서 커서를 이동했습니다."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearSelection() {
        selection = nil
        selectionRects = []
    }

    func selectAll() {
        guard let session, let caret = currentCaret?.position else { return }

        do {
            if let cell = caret.cellContext {
                let count: RHWPCountResult = try session.decodeResult(
                    RHWPCountResult.self,
                    operation: "get_paragraph_count",
                    payload: selectionContainerPayload(for: caret)
                )
                let lastPara = max(count.count - 1, 0)
                let lastLength: RHWPLengthResult = try session.decodeResult(
                    RHWPLengthResult.self,
                    operation: "get_paragraph_length",
                    payload: selectionPayload(
                        sectionIndex: caret.sectionIndex,
                        paragraphIndex: lastPara,
                        charOffset: 0,
                        cellContext: cell
                    )
                )
                let start = RHWPCaretPosition(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: 0,
                    charOffset: 0,
                    cellContext: cell
                )
                let end = RHWPCaretPosition(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: lastPara,
                    charOffset: lastLength.length,
                    cellContext: cell
                )
                selection = RHWPSelectionState(anchor: start, focus: end)
                currentCaret = try refreshedCaret(for: end)
            } else {
                let count: RHWPCountResult = try session.decodeResult(
                    RHWPCountResult.self,
                    operation: "get_paragraph_count",
                    payload: ["sec": caret.sectionIndex]
                )
                let lastPara = max(count.count - 1, 0)
                let lastLength: RHWPLengthResult = try session.decodeResult(
                    RHWPLengthResult.self,
                    operation: "get_paragraph_length",
                    payload: [
                        "sec": caret.sectionIndex,
                        "para": lastPara,
                    ]
                )
                let start = RHWPCaretPosition(sectionIndex: caret.sectionIndex, paragraphIndex: 0, charOffset: 0)
                let end = RHWPCaretPosition(sectionIndex: caret.sectionIndex, paragraphIndex: lastPara, charOffset: lastLength.length)
                selection = RHWPSelectionState(anchor: start, focus: end)
                currentCaret = try refreshedCaret(for: end)
            }

            syncDerivedState()
            statusMessage = "현재 컨테이너 전체를 선택했습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }

        if hasSelection {
            replaceSelection(with: text)
            return
        }

        guard let caret = currentCaret?.position else { return }
        performMutation(successMessage: nil, refreshPolicy: .editing) { session in
            var payload = selectionPayload(for: caret)
            payload["text"] = text
            _ = try session.perform(operation: "insert_text", payload: payload)
            return RHWPCaretPosition(
                sectionIndex: caret.sectionIndex,
                paragraphIndex: caret.paragraphIndex,
                charOffset: caret.charOffset + text.count,
                cellContext: caret.cellContext
            )
        }
    }

    func deleteBackward() {
        if hasSelection {
            deleteSelection()
            return
        }

        guard let caret = currentCaret?.position, let session else { return }

        do {
            if caret.charOffset > 0 {
                performMutation(successMessage: nil, refreshPolicy: .editing) { session in
                    var payload = self.selectionPayload(for: caret)
                    payload["charOffset"] = caret.charOffset - 1
                    payload["count"] = 1
                    _ = try session.perform(operation: "delete_text", payload: payload)
                    return RHWPCaretPosition(
                        sectionIndex: caret.sectionIndex,
                        paragraphIndex: caret.paragraphIndex,
                        charOffset: max(0, caret.charOffset - 1),
                        cellContext: caret.cellContext
                    )
                }
                return
            }

            guard caret.paragraphIndex > 0 else { return }

            let previousLength: RHWPLengthResult = try session.decodeResult(
                RHWPLengthResult.self,
                operation: "get_paragraph_length",
                payload: selectionPayload(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: caret.paragraphIndex - 1,
                    charOffset: 0,
                    cellContext: caret.cellContext
                )
            )

            performMutation(successMessage: nil, refreshPolicy: .editing) { session in
                _ = try session.perform(
                    operation: "merge_paragraph",
                    payload: self.selectionPayload(for: caret)
                )
                return RHWPCaretPosition(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: caret.paragraphIndex - 1,
                    charOffset: previousLength.length,
                    cellContext: caret.cellContext
                )
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteForward() {
        if hasSelection {
            deleteSelection()
            return
        }

        guard let caret = currentCaret?.position, let session else { return }

        do {
            let length: RHWPLengthResult = try session.decodeResult(
                RHWPLengthResult.self,
                operation: "get_paragraph_length",
                payload: selectionPayload(for: caret)
            )

            if caret.charOffset < length.length {
                performMutation(successMessage: nil, refreshPolicy: .editing) { session in
                    var payload = self.selectionPayload(for: caret)
                    payload["count"] = 1
                    _ = try session.perform(operation: "delete_text", payload: payload)
                    return caret
                }
                return
            }

            let count: RHWPCountResult = try session.decodeResult(
                RHWPCountResult.self,
                operation: "get_paragraph_count",
                payload: selectionContainerPayload(for: caret)
            )

            guard caret.paragraphIndex + 1 < count.count else { return }

            performMutation(successMessage: nil, refreshPolicy: .editing) { session in
                _ = try session.perform(
                    operation: "merge_paragraph",
                    payload: self.selectionPayload(
                        sectionIndex: caret.sectionIndex,
                        paragraphIndex: caret.paragraphIndex + 1,
                        charOffset: 0,
                        cellContext: updatedCellContext(caret.cellContext, cellParaIndex: caret.paragraphIndex + 1)
                    )
                )
                return caret
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func insertParagraphBreak() {
        if hasSelection {
            replaceSelection(with: "")
        }

        guard let caret = currentCaret?.position else { return }
        performMutation(successMessage: nil, refreshPolicy: .editing) { session in
            _ = try session.perform(
                operation: "split_paragraph",
                payload: self.selectionPayload(for: caret)
            )
            return RHWPCaretPosition(
                sectionIndex: caret.sectionIndex,
                paragraphIndex: caret.paragraphIndex + 1,
                charOffset: 0,
                cellContext: caret.cellContext.map {
                    RHWPCellContext(
                        parentParaIndex: $0.parentParaIndex,
                        controlIndex: $0.controlIndex,
                        cellIndex: $0.cellIndex,
                        cellParaIndex: caret.paragraphIndex + 1,
                        isTextBox: $0.isTextBox,
                        cellPath: $0.cellPath
                    )
                }
            )
        }
    }

    func moveHorizontal(delta: Int, extendSelection: Bool = false) {
        guard let caret = currentCaret?.position, let session else { return }

        if let bounds = normalizedSelection(), !extendSelection {
            do {
                try moveCaret(to: delta < 0 ? bounds.start : bounds.end)
            } catch {
                statusMessage = error.localizedDescription
            }
            return
        }

        do {
            if delta < 0 {
                if caret.charOffset > 0 {
                    let target = RHWPCaretPosition(
                        sectionIndex: caret.sectionIndex,
                        paragraphIndex: caret.paragraphIndex,
                        charOffset: caret.charOffset - 1,
                        cellContext: caret.cellContext
                    )
                    try moveCaret(to: target, selectingFrom: extendSelection ? (selection?.anchor ?? caret) : nil)
                    return
                }

                guard caret.paragraphIndex > 0 else { return }
                let length: RHWPLengthResult = try session.decodeResult(
                    RHWPLengthResult.self,
                    operation: "get_paragraph_length",
                    payload: selectionPayload(
                        sectionIndex: caret.sectionIndex,
                        paragraphIndex: caret.paragraphIndex - 1,
                        charOffset: 0,
                        cellContext: caret.cellContext
                    )
                )
                let target = RHWPCaretPosition(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: caret.paragraphIndex - 1,
                    charOffset: length.length,
                    cellContext: updatedCellContext(caret.cellContext, cellParaIndex: caret.paragraphIndex - 1)
                )
                try moveCaret(to: target, selectingFrom: extendSelection ? (selection?.anchor ?? caret) : nil)
                return
            }

            let length: RHWPLengthResult = try session.decodeResult(
                RHWPLengthResult.self,
                operation: "get_paragraph_length",
                payload: selectionPayload(for: caret)
            )

            if caret.charOffset < length.length {
                let target = RHWPCaretPosition(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: caret.paragraphIndex,
                    charOffset: caret.charOffset + 1,
                    cellContext: caret.cellContext
                )
                try moveCaret(to: target, selectingFrom: extendSelection ? (selection?.anchor ?? caret) : nil)
                return
            }

            let count: RHWPCountResult = try session.decodeResult(
                RHWPCountResult.self,
                operation: "get_paragraph_count",
                payload: selectionContainerPayload(for: caret)
            )
            guard caret.paragraphIndex + 1 < count.count else { return }

            let target = RHWPCaretPosition(
                sectionIndex: caret.sectionIndex,
                paragraphIndex: caret.paragraphIndex + 1,
                charOffset: 0,
                cellContext: updatedCellContext(caret.cellContext, cellParaIndex: caret.paragraphIndex + 1)
            )
            try moveCaret(to: target, selectingFrom: extendSelection ? (selection?.anchor ?? caret) : nil)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func moveVertical(delta: Int, extendSelection: Bool = false) {
        guard let caret = currentCaret, let session else { return }

        do {
            let result = try session.decodeResult(
                RHWPMoveVerticalResult.self,
                operation: "move_vertical",
                payload: movePayload(for: caret.position, preferredX: caret.preferredX ?? -1.0, delta: delta)
            )

            let position = position(from: result)
            let anchor = extendSelection ? (selection?.anchor ?? caret.position) : nil
            try moveCaret(to: position, selectingFrom: anchor, preferredX: result.preferredX)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func moveToParagraphBoundary(toEnd: Bool, extendSelection: Bool = false) {
        guard let caret = currentCaret?.position, let session else { return }

        do {
            let targetOffset: Int
            if toEnd {
                let length: RHWPLengthResult = try session.decodeResult(
                    RHWPLengthResult.self,
                    operation: "get_paragraph_length",
                    payload: selectionPayload(for: caret)
                )
                targetOffset = length.length
            } else {
                targetOffset = 0
            }

            let target = RHWPCaretPosition(
                sectionIndex: caret.sectionIndex,
                paragraphIndex: caret.paragraphIndex,
                charOffset: targetOffset,
                cellContext: caret.cellContext
            )
            try moveCaret(to: target, selectingFrom: extendSelection ? (selection?.anchor ?? caret) : nil)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func copySelection() -> Bool {
        guard let session, let bounds = normalizedSelection() else {
            statusMessage = "복사할 선택 영역이 없습니다."
            return false
        }

        do {
            let result: RHWPClipboardCopyResult = try session.decodeResult(
                RHWPClipboardCopyResult.self,
                operation: "copy_selection",
                payload: selectionPayload(for: bounds)
            )

            guard result.ok else {
                statusMessage = "선택 영역을 복사하지 못했습니다."
                return false
            }

            let plainText = result.text ?? ""
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(plainText, forType: .string)
            lastInternalClipboardText = plainText
            statusMessage = "선택 영역을 복사했습니다."
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func cutSelection() {
        guard copySelection() else { return }
        deleteSelection(status: "선택 영역을 잘랐습니다.")
    }

    func pasteFromPasteboard() {
        guard let pasteText = NSPasteboard.general.string(forType: .string) else {
            statusMessage = "붙여넣을 텍스트가 없습니다."
            return
        }

        let shouldUseInternalClipboard = !pasteText.isEmpty && pasteText == lastInternalClipboardText

        if shouldUseInternalClipboard {
            pasteInternalClipboard()
            return
        }

        replaceSelection(with: pasteText)
    }

    func findNext() {
        search(forward: true)
    }

    func findPrevious() {
        search(forward: false)
    }

    func replaceCurrent() {
        if !hasSelection {
            findNext()
        }

        guard hasSelection else { return }
        replaceSelection(with: replaceQuery)

        if !searchQuery.isEmpty {
            findNext()
        }
    }

    func replaceAll() {
        guard let session, !searchQuery.isEmpty else {
            statusMessage = "찾을 문자열을 입력하세요."
            return
        }

        performMutation(successMessage: "문서 전체 치환을 적용했습니다.") { _ in
            _ = try session.perform(
                operation: "replace_all",
                payload: [
                    "query": self.searchQuery,
                    "newText": self.replaceQuery,
                    "caseSensitive": self.searchCaseSensitive,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func toggleBold() {
        guard let props = charProperties else { return }
        applyCharFormat(["bold": !props.bold])
    }

    func toggleItalic() {
        guard let props = charProperties else { return }
        applyCharFormat(["italic": !props.italic])
    }

    func toggleUnderline() {
        guard let props = charProperties else { return }
        applyCharFormat([
            "underline": !props.underline,
            "underlineType": !props.underline ? "Bottom" : "None",
        ])
    }

    func setAlignment(_ alignment: String) {
        applyParaFormat(["alignment": alignment])
    }

    func increaseFontSize() {
        adjustFontSize(by: 1)
    }

    func decreaseFontSize() {
        adjustFontSize(by: -1)
    }

    func setFontSize(_ size: Double) {
        applyCharFormat(["fontSize": max(1, size) * 100])
    }

    func setFontFamily(_ family: String) {
        guard let session else { return }

        do {
            let result: RHWPIdentifierResult = try session.decodeResult(
                RHWPIdentifierResult.self,
                operation: "find_or_create_font_id",
                payload: ["name": family]
            )
            applyCharFormat([
                "fontId": result.id,
                "fontIds": Array(repeating: result.id, count: 7),
            ])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func increaseLineSpacing() {
        adjustLineSpacing(by: 5)
    }

    func decreaseLineSpacing() {
        adjustLineSpacing(by: -5)
    }

    func setLineSpacing(_ spacing: Double) {
        applyParaFormat([
            "lineSpacing": max(50, spacing),
            "lineSpacingType": "Percent",
        ])
    }

    func toggleStrikethrough() {
        guard let props = charProperties else { return }
        applyCharFormat(["strikethrough": !props.strikethrough])
    }

    func setTextColor(_ hex: String) {
        applyCharFormat(["textColor": hex])
    }

    func setHighlightColor(_ hex: String) {
        applyCharFormat(["shadeColor": hex])
    }

    func clearHighlightColor() {
        applyCharFormat(["shadeColor": "#ffffff"])
    }

    func applyCharacterProperties(_ props: [String: Any]) {
        applyCharFormat(props)
    }

    func applyParagraphProperties(_ props: [String: Any]) {
        applyParaFormat(props)
    }

    func applyBulletList(bulletCharacter: String = "•") {
        guard let session else { return }

        do {
            let result: RHWPIdentifierResult = try session.decodeResult(
                RHWPIdentifierResult.self,
                operation: "ensure_default_bullet",
                payload: ["char": bulletCharacter]
            )
            applyParaFormat([
                "headType": "Bullet",
                "numberingId": result.id,
            ])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func applyNumberingList() {
        guard let session else { return }

        do {
            let result: RHWPIdentifierResult = try session.decodeResult(
                RHWPIdentifierResult.self,
                operation: "ensure_default_numbering",
                payload: [:]
            )
            applyParaFormat([
                "headType": "Number",
                "numberingId": result.id,
            ])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearParagraphList() {
        applyParaFormat([
            "headType": "None",
            "numberingId": 0,
            "paraLevel": 0,
        ])
    }

    func increaseParagraphLevel() {
        let next = min((paraProperties?.paraLevel ?? 0) + 1, 6)
        applyParaFormat(["paraLevel": next])
    }

    func decreaseParagraphLevel() {
        let next = max((paraProperties?.paraLevel ?? 0) - 1, 0)
        applyParaFormat(["paraLevel": next])
    }

    func createTable(rows: Int, columns: Int) {
        guard let caret = currentCaret?.position else { return }
        guard caret.cellContext == nil else {
            statusMessage = "표 삽입은 현재 본문 커서 위치에서만 지원합니다."
            return
        }

        performMutation(successMessage: "표를 삽입했습니다.") { session in
            var payload = self.selectionPayload(for: caret)
            payload["rows"] = rows
            payload["cols"] = columns
            _ = try session.perform(operation: "create_table", payload: payload)
            return caret
        }
    }

    func addBookmark(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "책갈피 이름을 입력하세요."
            return
        }
        guard let caret = currentCaret?.position else { return }

        performMutation(successMessage: "\"\(trimmed)\" 책갈피를 추가했습니다.") { session in
            let result: RHWPOperationStatus = try session.decodeResult(
                RHWPOperationStatus.self,
                operation: "add_bookmark",
                payload: [
                    "sec": caret.sectionIndex,
                    "para": caret.paragraphIndex,
                    "charOffset": caret.charOffset,
                    "name": trimmed,
                ]
            )
            guard result.ok else {
                throw NativeBridgeError.nativeFailure(result.error ?? "책갈피를 추가하지 못했습니다.")
            }
            return caret
        }
    }

    func renameBookmark(_ bookmark: RHWPBookmark, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "책갈피 이름을 입력하세요."
            return
        }

        performMutation(successMessage: "\"\(trimmed)\" 이름으로 책갈피를 바꿨습니다.") { session in
            let result: RHWPOperationStatus = try session.decodeResult(
                RHWPOperationStatus.self,
                operation: "rename_bookmark",
                payload: [
                    "sec": bookmark.sec,
                    "para": bookmark.para,
                    "controlIndex": bookmark.ctrlIdx,
                    "name": trimmed,
                ]
            )
            guard result.ok else {
                throw NativeBridgeError.nativeFailure(result.error ?? "책갈피 이름을 바꾸지 못했습니다.")
            }
            return self.currentCaret?.position
        }
    }

    func deleteBookmark(_ bookmark: RHWPBookmark) {
        performMutation(successMessage: "\"\(bookmark.name)\" 책갈피를 삭제했습니다.") { session in
            let result: RHWPOperationStatus = try session.decodeResult(
                RHWPOperationStatus.self,
                operation: "delete_bookmark",
                payload: [
                    "sec": bookmark.sec,
                    "para": bookmark.para,
                    "controlIndex": bookmark.ctrlIdx,
                ]
            )
            guard result.ok else {
                throw NativeBridgeError.nativeFailure(result.error ?? "책갈피를 삭제하지 못했습니다.")
            }
            return self.currentCaret?.position
        }
    }

    func jumpToBookmark(_ bookmark: RHWPBookmark) {
        do {
            try moveCaret(
                to: RHWPCaretPosition(
                    sectionIndex: bookmark.sec,
                    paragraphIndex: bookmark.para,
                    charOffset: bookmark.charPos
                )
            )
            statusMessage = "\"\(bookmark.name)\" 책갈피로 이동했습니다."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateFieldValue(name: String, value: String) {
        guard let session else { return }

        performMutation(successMessage: "\"\(name)\" 필드 값을 적용했습니다.") { _ in
            let result: RHWPOperationStatus = try session.decodeResult(
                RHWPOperationStatus.self,
                operation: "set_field_value_by_name",
                payload: [
                    "name": name,
                    "value": value,
                ]
            )
            guard result.ok else {
                throw NativeBridgeError.nativeFailure(result.error ?? "필드 값을 적용하지 못했습니다.")
            }
            return self.currentCaret?.position
        }
    }

    func replaceTextInInputRange(_ range: NSRange, with text: String, coalescingComposition: Bool = false) {
        guard
            let caret = currentCaret?.position,
            range.location != NSNotFound,
            range.location >= 0,
            range.length >= 0
        else {
            insertText(text)
            return
        }

        if hasSelection, currentInputSelectionRange() == range {
            replaceSelection(with: text)
            return
        }

        let mutationBody: (EditorSession) throws -> RHWPCaretPosition? = { session in
            let baseOffset = max(range.location, 0)
            if range.length > 0 {
                var deletePayload = self.selectionPayload(for: caret)
                deletePayload["charOffset"] = baseOffset
                deletePayload["count"] = range.length
                _ = try session.perform(operation: "delete_text", payload: deletePayload)
            }

            guard !text.isEmpty else {
                return RHWPCaretPosition(
                    sectionIndex: caret.sectionIndex,
                    paragraphIndex: caret.paragraphIndex,
                    charOffset: baseOffset,
                    cellContext: caret.cellContext
                )
            }

            var insertPayload = self.selectionPayload(
                sectionIndex: caret.sectionIndex,
                paragraphIndex: caret.paragraphIndex,
                charOffset: baseOffset,
                cellContext: caret.cellContext
            )
            insertPayload["text"] = text
            _ = try session.perform(operation: "insert_text", payload: insertPayload)

            return RHWPCaretPosition(
                sectionIndex: caret.sectionIndex,
                paragraphIndex: caret.paragraphIndex,
                charOffset: baseOffset + text.count,
                cellContext: caret.cellContext
            )
        }

        if coalescingComposition {
            performCompositionMutation(body: mutationBody)
        } else {
            performMutation(successMessage: nil, refreshPolicy: .editing, body: mutationBody)
        }
    }

    func finishTextComposition() {
        compositionUndoSnapshot = nil
    }

    func applyHeaderFooterTemplate(isHeader: Bool, templateID: Int) {
        guard let session else { return }

        let sectionIndex: Int
        if pageInfos.indices.contains(selectedPageIndex) {
            sectionIndex = pageInfos[selectedPageIndex].sectionIndex
        } else {
            sectionIndex = currentCaret?.position.sectionIndex ?? 0
        }

        let title = isHeader ? "머리말" : "꼬리말"
        let successMessage = templateID == 0
            ? "\(title) 템플릿을 비웠습니다."
            : "\(title) 템플릿을 적용했습니다."

        performMutation(successMessage: successMessage) { _ in
            let result: RHWPOperationStatus = try session.decodeResult(
                RHWPOperationStatus.self,
                operation: "apply_header_footer_template",
                payload: [
                    "sec": sectionIndex,
                    "isHeader": isHeader,
                    "applyTo": 0,
                    "templateId": templateID,
                ]
            )
            guard result.ok else {
                throw NativeBridgeError.nativeFailure(result.error ?? "\(title) 템플릿을 적용하지 못했습니다.")
            }
            return self.currentCaret?.position
        }
    }

    func currentInputSelectionRange() -> NSRange {
        if let bounds = normalizedSelection(),
           sameSelectionContainer(bounds.start, bounds.end),
           bounds.start.paragraphIndex == bounds.end.paragraphIndex {
            return NSRange(
                location: bounds.start.charOffset,
                length: max(bounds.end.charOffset - bounds.start.charOffset, 0)
            )
        }

        guard let caret = currentCaret?.position else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: caret.charOffset, length: 0)
    }

    func attributedSubstringForInput(range: NSRange) -> NSAttributedString? {
        guard
            range.location != NSNotFound,
            range.location >= 0,
            range.length >= 0,
            let session,
            let caret = currentCaret?.position
        else {
            return nil
        }

        do {
            var payload: [String: Any] = [
                "sec": caret.sectionIndex,
                "para": caret.paragraphIndex,
                "charOffset": range.location,
                "count": range.length,
            ]
            if let cellContext = cellContextPayload(caret.cellContext) {
                payload["para"] = caret.cellContext?.cellParaIndex ?? caret.paragraphIndex
                payload["cellContext"] = cellContext
            }
            let text = try session.perform(operation: "get_text_range", payload: payload)
            return NSAttributedString(string: text)
        } catch {
            return nil
        }
    }

    func insertPageBreak() {
        guard let caret = currentCaret?.position else { return }

        performMutation(successMessage: "쪽 나누기를 삽입했습니다.") { session in
            _ = try session.perform(operation: "insert_page_break", payload: self.selectionPayload(for: caret))
            return caret
        }
    }

    func insertColumnBreak() {
        guard let caret = currentCaret?.position else { return }

        performMutation(successMessage: "단 나누기를 삽입했습니다.") { session in
            _ = try session.perform(operation: "insert_column_break", payload: self.selectionPayload(for: caret))
            return caret
        }
    }

    func insertTableRow(after: Bool) {
        guard let target = currentTableTarget() else { return }

        performMutation(successMessage: after ? "행을 아래에 추가했습니다." : "행을 위에 추가했습니다.") { session in
            _ = try session.perform(
                operation: "insert_table_row",
                payload: [
                    "sec": target.sectionIndex,
                    "parentPara": target.parentParaIndex,
                    "controlIndex": target.controlIndex,
                    "row": target.row,
                    "after": after,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func insertTableColumn(after: Bool) {
        guard let target = currentTableTarget() else { return }

        performMutation(successMessage: after ? "열을 오른쪽에 추가했습니다." : "열을 왼쪽에 추가했습니다.") { session in
            _ = try session.perform(
                operation: "insert_table_column",
                payload: [
                    "sec": target.sectionIndex,
                    "parentPara": target.parentParaIndex,
                    "controlIndex": target.controlIndex,
                    "column": target.column,
                    "after": after,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func deleteCurrentTableRow() {
        guard let target = currentTableTarget() else { return }

        performMutation(successMessage: "현재 행을 삭제했습니다.") { session in
            _ = try session.perform(
                operation: "delete_table_row",
                payload: [
                    "sec": target.sectionIndex,
                    "parentPara": target.parentParaIndex,
                    "controlIndex": target.controlIndex,
                    "row": target.row,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func deleteCurrentTableColumn() {
        guard let target = currentTableTarget() else { return }

        performMutation(successMessage: "현재 열을 삭제했습니다.") { session in
            _ = try session.perform(
                operation: "delete_table_column",
                payload: [
                    "sec": target.sectionIndex,
                    "parentPara": target.parentParaIndex,
                    "controlIndex": target.controlIndex,
                    "column": target.column,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func splitCurrentTableCell() {
        guard let target = currentTableTarget() else { return }

        performMutation(successMessage: "현재 셀 병합을 해제했습니다.") { session in
            _ = try session.perform(
                operation: "split_table_cell",
                payload: [
                    "sec": target.sectionIndex,
                    "parentPara": target.parentParaIndex,
                    "controlIndex": target.controlIndex,
                    "row": target.row,
                    "col": target.column,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func mergeCurrentTableCells(toRow endRow: Int, toColumn endColumn: Int) {
        guard let target = currentTableTarget(), let dimensions = currentTableDimensions else { return }

        let safeEndRow = min(max(endRow, target.row), max(dimensions.rowCount - 1, target.row))
        let safeEndColumn = min(max(endColumn, target.column), max(dimensions.colCount - 1, target.column))

        performMutation(successMessage: "셀을 합쳤습니다.") { session in
            _ = try session.perform(
                operation: "merge_table_cells",
                payload: [
                    "sec": target.sectionIndex,
                    "parentPara": target.parentParaIndex,
                    "controlIndex": target.controlIndex,
                    "startRow": target.row,
                    "startCol": target.column,
                    "endRow": safeEndRow,
                    "endCol": safeEndColumn,
                ]
            )
            return self.currentCaret?.position
        }
    }

    func updateCurrentCellProperties(_ props: [String: Any]) {
        guard
            let session,
            let caret = currentCaret?.position,
            let cell = caret.cellContext,
            !cell.isTextBox
        else { return }

        performMutation(successMessage: "셀 속성을 적용했습니다.") { _ in
            _ = try session.perform(
                operation: "set_cell_properties",
                payload: [
                    "sec": caret.sectionIndex,
                    "parentPara": cell.parentParaIndex,
                    "controlIndex": cell.controlIndex,
                    "cellIndex": cell.cellIndex,
                    "props": props,
                ]
            )
            return caret
        }
    }

    func updateCurrentTableProperties(_ props: [String: Any]) {
        guard
            let session,
            let caret = currentCaret?.position,
            let cell = caret.cellContext,
            !cell.isTextBox
        else { return }

        performMutation(successMessage: "표 속성을 적용했습니다.") { _ in
            _ = try session.perform(
                operation: "set_table_properties",
                payload: [
                    "sec": caret.sectionIndex,
                    "parentPara": cell.parentParaIndex,
                    "controlIndex": cell.controlIndex,
                    "props": props,
                ]
            )
            return caret
        }
    }

    func undo() {
        guard let session, let snapshot = undoSnapshots.popLast() else { return }

        do {
            let current = try session.saveSnapshot()
            redoSnapshots.append(current)
            try session.restoreSnapshot(snapshot)
            session.discardSnapshot(snapshot)
            try reloadDocumentState()
            isDirty = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func redo() {
        guard let session, let snapshot = redoSnapshots.popLast() else { return }

        do {
            let current = try session.saveSnapshot()
            undoSnapshots.append(current)
            try session.restoreSnapshot(snapshot)
            session.discardSnapshot(snapshot)
            try reloadDocumentState()
            isDirty = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(at: url)
    }

    private func deleteSelection(status: String? = nil) {
        guard let bounds = normalizedSelection() else { return }
        clearSelection()

        performMutation(successMessage: status, refreshPolicy: .editing) { session in
            let result: RHWPMutationCursorResult = try session.decodeResult(
                RHWPMutationCursorResult.self,
                operation: "delete_range",
                payload: self.selectionPayload(for: bounds)
            )
            return self.position(from: result, fallback: bounds.start)
        }
    }

    private func replaceSelection(with text: String) {
        guard let bounds = normalizedSelection() else {
            if !text.isEmpty {
                insertText(text)
            }
            return
        }

        clearSelection()

        performMutation(successMessage: nil, refreshPolicy: .editing) { session in
            let deleteResult: RHWPMutationCursorResult = try session.decodeResult(
                RHWPMutationCursorResult.self,
                operation: "delete_range",
                payload: self.selectionPayload(for: bounds)
            )
            let insertionPoint = self.position(from: deleteResult, fallback: bounds.start)

            if !text.isEmpty {
                var insertPayload = self.selectionPayload(for: insertionPoint)
                insertPayload["text"] = text
                _ = try session.perform(operation: "insert_text", payload: insertPayload)
                return RHWPCaretPosition(
                    sectionIndex: insertionPoint.sectionIndex,
                    paragraphIndex: insertionPoint.paragraphIndex,
                    charOffset: insertionPoint.charOffset + text.count,
                    cellContext: insertionPoint.cellContext
                )
            }

            return insertionPoint
        }
    }

    private func pasteInternalClipboard() {
        guard let caret = currentCaret?.position else { return }
        let bounds = normalizedSelection()
        clearSelection()

        performMutation(successMessage: "문서를 붙여넣었습니다.", refreshPolicy: .editing) { session in
            let insertionPoint: RHWPCaretPosition
            if let bounds {
                let deleteResult: RHWPMutationCursorResult = try session.decodeResult(
                    RHWPMutationCursorResult.self,
                    operation: "delete_range",
                    payload: self.selectionPayload(for: bounds)
                )
                insertionPoint = self.position(from: deleteResult, fallback: bounds.start)
            } else {
                insertionPoint = caret
            }

            let result: RHWPMutationCursorResult = try session.decodeResult(
                RHWPMutationCursorResult.self,
                operation: "paste_internal",
                payload: self.selectionPayload(for: insertionPoint)
            )
            return self.position(from: result, fallback: insertionPoint)
        }
    }

    private func search(forward: Bool) {
        guard let session, !searchQuery.isEmpty else {
            statusMessage = "찾을 문자열을 입력하세요."
            return
        }

        let origin = currentCaret?.position ?? RHWPCaretPosition(sectionIndex: 0, paragraphIndex: 0, charOffset: 0)

        do {
            let result: RHWPSearchResult = try session.decodeResult(
                RHWPSearchResult.self,
                operation: "search_text",
                payload: [
                    "query": searchQuery,
                    "fromSec": origin.sectionIndex,
                    "fromPara": origin.paragraphIndex,
                    "fromChar": origin.charOffset,
                    "forward": forward,
                    "caseSensitive": searchCaseSensitive,
                ]
            )

            guard result.found, let sec = result.sec, let para = result.para, let charOffset = result.charOffset else {
                searchStatus = "검색 결과가 없습니다."
                statusMessage = searchStatus
                clearSelection()
                return
            }

            let start = RHWPCaretPosition(sectionIndex: sec, paragraphIndex: para, charOffset: charOffset)
            let end = RHWPCaretPosition(sectionIndex: sec, paragraphIndex: para, charOffset: charOffset + (result.length ?? 0))
            currentCaret = try refreshedCaret(for: end)
            selection = RHWPSelectionState(anchor: start, focus: end)
            syncDerivedState()

            searchStatus = result.wrapped == true ? "문서 끝에 도달해 처음부터 다시 찾았습니다." : "검색 결과를 찾았습니다."
            statusMessage = searchStatus
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyCharFormat(_ props: [String: Any]) {
        guard let session, let target = charFormatTarget() else { return }

        performMutation(successMessage: "글자 서식을 적용했습니다.") { _ in
            var payload: [String: Any] = [
                "sec": target.position.sectionIndex,
                "para": target.position.paragraphIndex,
                "startOffset": target.startOffset,
                "endOffset": target.endOffset,
                "props": props,
            ]
            if let cellContext = self.cellContextPayload(target.position.cellContext) {
                payload["cellContext"] = cellContext
            }
            _ = try session.perform(operation: "apply_char_format", payload: payload)
            return self.currentCaret?.position ?? target.position
        }
    }

    private func applyParaFormat(_ props: [String: Any]) {
        guard let session, let caret = currentCaret?.position else { return }

        performMutation(successMessage: "문단 서식을 적용했습니다.") { _ in
            var payload: [String: Any] = [
                "sec": caret.sectionIndex,
                "para": caret.paragraphIndex,
                "props": props,
            ]
            if let cellContext = self.cellContextPayload(caret.cellContext) {
                payload["cellContext"] = cellContext
            }
            _ = try session.perform(operation: "apply_para_format", payload: payload)
            return self.currentCaret?.position ?? caret
        }
    }

    private func adjustFontSize(by delta: Double) {
        guard let size = charProperties?.fontSize else { return }
        let nextSize = max(100, size + delta * 100)
        applyCharFormat(["fontSize": nextSize])
    }

    private func adjustLineSpacing(by delta: Double) {
        let current = paraProperties?.lineSpacing ?? 160
        let nextSpacing = max(50, current + delta)
        applyParaFormat(["lineSpacing": nextSpacing])
    }

    private func performMutation(
        successMessage: String?,
        refreshPolicy: MutationRefreshPolicy = .full,
        body: (EditorSession) throws -> RHWPCaretPosition?
    ) {
        guard let session else { return }

        do {
            let snapshot = try session.saveSnapshot()
            undoSnapshots.append(snapshot)
            redoSnapshots.forEach { session.discardSnapshot($0) }
            redoSnapshots.removeAll()

            let targetPosition = try body(session)
            if let targetPosition {
                currentCaret = RHWPCaretState(
                    position: targetPosition,
                    rect: currentCaret?.rect ?? RHWPCursorRect(pageIndex: selectedPageIndex, x: 0, y: 0, height: 16),
                    preferredX: nil
                )
            }

            isDirty = true
            try refreshAfterMutation(policy: refreshPolicy)

            if let successMessage {
                statusMessage = successMessage
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func performCompositionMutation(
        body: (EditorSession) throws -> RHWPCaretPosition?
    ) {
        guard let session else { return }

        do {
            if compositionUndoSnapshot == nil {
                let snapshot = try session.saveSnapshot()
                undoSnapshots.append(snapshot)
                compositionUndoSnapshot = snapshot
                redoSnapshots.forEach { session.discardSnapshot($0) }
                redoSnapshots.removeAll()
            }

            let targetPosition = try body(session)
            if let targetPosition {
                currentCaret = RHWPCaretState(
                    position: targetPosition,
                    rect: currentCaret?.rect ?? RHWPCursorRect(pageIndex: selectedPageIndex, x: 0, y: 0, height: 16),
                    preferredX: nil
                )
            }

            isDirty = true
            try refreshAfterMutation(policy: .editing)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshAfterMutation(policy: MutationRefreshPolicy) throws {
        switch policy {
        case .full:
            try reloadDocumentState()
        case .editing:
            try refreshEditingState()
            scheduleDeferredRefresh()
        }
    }

    private func refreshEditingState() throws {
        viewportController.invalidateCache()

        if let caret = currentCaret {
            currentCaret = try refreshedCaret(for: caret.position, preferredX: caret.preferredX)
        }

        syncDerivedState()
    }

    private func scheduleDeferredRefresh() {
        cancelDeferredRefresh()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try self.reloadDocumentState()
            } catch {
                self.statusMessage = error.localizedDescription
            }
        }

        deferredRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func cancelDeferredRefresh() {
        deferredRefreshWorkItem?.cancel()
        deferredRefreshWorkItem = nil
    }

    private func moveCaret(
        to position: RHWPCaretPosition,
        selectingFrom anchor: RHWPCaretPosition? = nil,
        preferredX: Double? = nil
    ) throws {
        currentCaret = try refreshedCaret(for: position, preferredX: preferredX)
        if let anchor {
            let nextSelection = RHWPSelectionState(anchor: anchor, focus: position)
            selection = nextSelection.isCollapsed ? nil : nextSelection
        } else {
            selection = nil
        }
        syncDerivedState()
    }

    private func refreshedCaret(for position: RHWPCaretPosition, preferredX: Double? = nil) throws -> RHWPCaretState {
        guard let session else { throw NativeBridgeError.missingSession }
        let rect = try session.decodeResult(
            RHWPCursorRect.self,
            operation: "get_cursor_rect",
            payload: selectionPayload(for: position)
        )
        selectedPageIndex = rect.pageIndex
        return RHWPCaretState(position: position, rect: rect, preferredX: preferredX)
    }

    private func syncDerivedState() {
        do {
            try refreshSelectionRects()
        } catch {
            selectionRects = []
        }

        do {
            try refreshFormattingState()
        } catch {
            charProperties = nil
            paraProperties = nil
        }

        do {
            try refreshTableState()
        } catch {
            currentTableDimensions = nil
            currentCellInfo = nil
        }
    }

    private func refreshSelectionRects() throws {
        guard let session, let bounds = normalizedSelection() else {
            selectionRects = []
            return
        }
        selectionRects = try session.decodeResult(
            [RHWPSelectionRect].self,
            operation: "get_selection_rects",
            payload: selectionPayload(for: bounds)
        )
    }

    private func refreshFormattingState() throws {
        guard let session, let caret = currentCaret?.position else {
            charProperties = nil
            paraProperties = nil
            return
        }

        charProperties = try session.decodeResult(
            RHWPCharProperties.self,
            operation: "get_char_properties",
            payload: selectionPayload(for: caret)
        )

        paraProperties = try session.decodeResult(
            RHWPParaProperties.self,
            operation: "get_para_properties",
            payload: selectionPayload(for: caret)
        )
    }

    private func refreshTableState() throws {
        guard let session, let cell = currentCaret?.position.cellContext, !cell.isTextBox else {
            currentTableDimensions = nil
            currentCellInfo = nil
            currentCellProperties = nil
            currentTableProperties = nil
            return
        }

        currentTableDimensions = try session.decodeResult(
            RHWPTableDimensionsResult.self,
            operation: "get_table_dimensions",
            payload: [
                "sec": currentCaret?.position.sectionIndex ?? 0,
                "parentPara": cell.parentParaIndex,
                "controlIndex": cell.controlIndex,
            ]
        )

        currentCellInfo = try session.decodeResult(
            RHWPCellInfoResult.self,
            operation: "get_cell_info",
            payload: [
                "sec": currentCaret?.position.sectionIndex ?? 0,
                "parentPara": cell.parentParaIndex,
                "controlIndex": cell.controlIndex,
                "cellIndex": cell.cellIndex,
            ]
        )

        currentCellProperties = try session.decodeResult(
            RHWPCellProperties.self,
            operation: "get_cell_properties",
            payload: [
                "sec": currentCaret?.position.sectionIndex ?? 0,
                "parentPara": cell.parentParaIndex,
                "controlIndex": cell.controlIndex,
                "cellIndex": cell.cellIndex,
            ]
        )

        currentTableProperties = try session.decodeResult(
            RHWPTableProperties.self,
            operation: "get_table_properties",
            payload: [
                "sec": currentCaret?.position.sectionIndex ?? 0,
                "parentPara": cell.parentParaIndex,
                "controlIndex": cell.controlIndex,
            ]
        )
    }

    private func refreshBookmarks() throws {
        guard let session else {
            bookmarks = []
            return
        }

        bookmarks = try session.decodeResult(
            [RHWPBookmark].self,
            operation: "get_bookmarks"
        )
    }

    private func refreshFields() throws {
        guard let session else {
            fields = []
            return
        }

        fields = try session.decodeResult(
            [RHWPFieldInfo].self,
            operation: "get_field_list"
        )
    }

    private func normalizedSelection() -> SelectionBounds? {
        guard let selection, sameSelectionContainer(selection.anchor, selection.focus) else {
            return nil
        }

        let isAscending = compare(selection.anchor, selection.focus) <= 0
        let start = isAscending ? selection.anchor : selection.focus
        let end = isAscending ? selection.focus : selection.anchor

        guard start != end else { return nil }
        return SelectionBounds(start: start, end: end)
    }

    private func sameSelectionContainer(_ lhs: RHWPCaretPosition, _ rhs: RHWPCaretPosition) -> Bool {
        guard lhs.sectionIndex == rhs.sectionIndex else { return false }
        switch (lhs.cellContext, rhs.cellContext) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.parentParaIndex == right.parentParaIndex
                && left.controlIndex == right.controlIndex
                && left.cellIndex == right.cellIndex
        default:
            return false
        }
    }

    private func compare(_ lhs: RHWPCaretPosition, _ rhs: RHWPCaretPosition) -> Int {
        if lhs.paragraphIndex != rhs.paragraphIndex {
            return lhs.paragraphIndex < rhs.paragraphIndex ? -1 : 1
        }
        if lhs.charOffset != rhs.charOffset {
            return lhs.charOffset < rhs.charOffset ? -1 : 1
        }
        return 0
    }

    private func charFormatTarget() -> (position: RHWPCaretPosition, startOffset: Int, endOffset: Int)? {
        if let bounds = normalizedSelection() {
            guard sameSelectionContainer(bounds.start, bounds.end), bounds.start.paragraphIndex == bounds.end.paragraphIndex else {
                statusMessage = "글자 서식은 현재 한 문단 범위에서만 적용합니다."
                return nil
            }

            return (
                position: bounds.start,
                startOffset: bounds.start.charOffset,
                endOffset: bounds.end.charOffset
            )
        }

        guard let caret = currentCaret?.position else { return nil }
        let start = max(caret.charOffset - (caret.charOffset > 0 ? 1 : 0), 0)
        let end = max(caret.charOffset, start + 1)
        return (position: caret, startOffset: start, endOffset: end)
    }

    private func currentTableTarget() -> (sectionIndex: Int, parentParaIndex: Int, controlIndex: Int, row: Int, column: Int)? {
        guard
            let caret = currentCaret?.position,
            let cell = caret.cellContext,
            !cell.isTextBox,
            let currentCellInfo
        else {
            statusMessage = "현재 커서가 표 셀 안에 있지 않습니다."
            return nil
        }

        return (
            sectionIndex: caret.sectionIndex,
            parentParaIndex: cell.parentParaIndex,
            controlIndex: cell.controlIndex,
            row: currentCellInfo.row,
            column: currentCellInfo.col
        )
    }

    private func position(from hit: RHWPHitTestResult) -> RHWPCaretPosition {
        RHWPCaretPosition(
            sectionIndex: hit.sectionIndex,
            paragraphIndex: hit.paragraphIndex,
            charOffset: hit.charOffset,
            cellContext: makeCellContext(
                parentParaIndex: hit.parentParaIndex,
                controlIndex: hit.controlIndex,
                cellIndex: hit.cellIndex,
                cellParaIndex: hit.cellParaIndex,
                isTextBox: hit.isTextBox ?? false,
                cellPath: hit.cellPath ?? []
            )
        )
    }

    private func position(from result: RHWPMoveVerticalResult) -> RHWPCaretPosition {
        RHWPCaretPosition(
            sectionIndex: result.sectionIndex,
            paragraphIndex: result.paragraphIndex,
            charOffset: result.charOffset,
            cellContext: makeCellContext(
                parentParaIndex: result.parentParaIndex,
                controlIndex: result.controlIndex,
                cellIndex: result.cellIndex,
                cellParaIndex: result.cellParaIndex,
                isTextBox: result.isTextBox ?? false,
                cellPath: result.cellPath ?? []
            )
        )
    }

    private func position(from result: RHWPMutationCursorResult, fallback: RHWPCaretPosition) -> RHWPCaretPosition {
        let paragraphIndex = result.cellParaIndex ?? result.paraIdx ?? fallback.paragraphIndex
        return RHWPCaretPosition(
            sectionIndex: fallback.sectionIndex,
            paragraphIndex: paragraphIndex,
            charOffset: result.charOffset ?? fallback.charOffset,
            cellContext: updatedCellContext(fallback.cellContext, cellParaIndex: paragraphIndex)
        )
    }

    private func makeCellContext(
        parentParaIndex: Int?,
        controlIndex: Int?,
        cellIndex: Int?,
        cellParaIndex: Int?,
        isTextBox: Bool,
        cellPath: [RHWPCellPathEntry]
    ) -> RHWPCellContext? {
        guard
            let parentParaIndex,
            let controlIndex,
            let cellIndex,
            let cellParaIndex
        else {
            return nil
        }

        return RHWPCellContext(
            parentParaIndex: parentParaIndex,
            controlIndex: controlIndex,
            cellIndex: cellIndex,
            cellParaIndex: cellParaIndex,
            isTextBox: isTextBox,
            cellPath: cellPath
        )
    }

    private func updatedCellContext(_ context: RHWPCellContext?, cellParaIndex: Int) -> RHWPCellContext? {
        guard let context else { return nil }
        return RHWPCellContext(
            parentParaIndex: context.parentParaIndex,
            controlIndex: context.controlIndex,
            cellIndex: context.cellIndex,
            cellParaIndex: cellParaIndex,
            isTextBox: context.isTextBox,
            cellPath: context.cellPath.isEmpty
                ? []
                : context.cellPath.enumerated().map { offset, entry in
                    RHWPCellPathEntry(
                        controlIndex: entry.controlIndex,
                        cellIndex: entry.cellIndex,
                        cellParaIndex: offset == context.cellPath.count - 1 ? cellParaIndex : entry.cellParaIndex
                    )
                }
        )
    }

    private func selectionContainerPayload(for caret: RHWPCaretPosition) -> [String: Any] {
        var payload: [String: Any] = ["sec": caret.sectionIndex]
        if let cellContext = cellContextPayload(caret.cellContext) {
            payload["cellContext"] = cellContext
        }
        return payload
    }

    private func selectionPayload(for caret: RHWPCaretPosition) -> [String: Any] {
        selectionPayload(
            sectionIndex: caret.sectionIndex,
            paragraphIndex: caret.paragraphIndex,
            charOffset: caret.charOffset,
            cellContext: caret.cellContext
        )
    }

    private func selectionPayload(
        sectionIndex: Int,
        paragraphIndex: Int,
        charOffset: Int,
        cellContext: RHWPCellContext?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "sec": sectionIndex,
            "para": paragraphIndex,
            "charOffset": charOffset,
        ]
        if let cellContext = cellContextPayload(cellContext) {
            payload["cellContext"] = cellContext
        }
        return payload
    }

    private func selectionPayload(for bounds: SelectionBounds) -> [String: Any] {
        var payload: [String: Any] = [
            "sec": bounds.start.sectionIndex,
            "startPara": bounds.start.paragraphIndex,
            "startCharOffset": bounds.start.charOffset,
            "endPara": bounds.end.paragraphIndex,
            "endCharOffset": bounds.end.charOffset,
        ]
        if let cellContext = cellContextPayload(bounds.start.cellContext) {
            payload["cellContext"] = cellContext
        }
        return payload
    }

    private func movePayload(for position: RHWPCaretPosition, preferredX: Double, delta: Int) -> [String: Any] {
        var payload: [String: Any] = [
            "sec": position.sectionIndex,
            "para": position.paragraphIndex,
            "charOffset": position.charOffset,
            "delta": delta,
            "preferredX": preferredX,
        ]
        if let cellContext = cellContextPayload(position.cellContext) {
            payload["cellContext"] = cellContext
        }
        return payload
    }

    private func cellContextPayload(_ cellContext: RHWPCellContext?) -> [String: Any]? {
        guard let cellContext else { return nil }
        return [
            "parentPara": cellContext.parentParaIndex,
            "controlIndex": cellContext.controlIndex,
            "cellIndex": cellContext.cellIndex,
            "cellParaIndex": cellContext.cellParaIndex,
        ]
    }

    private func clearHistory() {
        if let session {
            undoSnapshots.forEach { session.discardSnapshot($0) }
            redoSnapshots.forEach { session.discardSnapshot($0) }
        }
        undoSnapshots.removeAll()
        redoSnapshots.removeAll()
        compositionUndoSnapshot = nil
    }

    private func resetLoadedState() {
        cancelDeferredRefresh()
        compositionUndoSnapshot = nil
        isDirty = false
        lastInternalClipboardText = nil
        clearHistory()
        selection = nil
        selectionRects = []
        searchStatus = ""
        currentTableDimensions = nil
        currentCellInfo = nil
        currentCellProperties = nil
        currentTableProperties = nil
        bookmarks = []
        fields = []
        charProperties = nil
        paraProperties = nil
        selectedPageIndex = 0
    }
}
