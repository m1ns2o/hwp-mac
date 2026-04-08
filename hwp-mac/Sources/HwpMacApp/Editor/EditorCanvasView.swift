import AppKit
import SwiftUI

struct EditorCanvasView: NSViewRepresentable {
    @ObservedObject var documentController: DocumentController
    @ObservedObject var viewportController: ViewportController

    func makeNSView(context: Context) -> EditorScrollView {
        let scrollView = EditorScrollView()
        scrollView.editorView.documentController = documentController
        scrollView.editorView.viewportController = viewportController
        scrollView.configureViewport()
        return scrollView
    }

    func updateNSView(_ nsView: EditorScrollView, context: Context) {
        nsView.editorView.documentController = documentController
        nsView.editorView.viewportController = viewportController
        nsView.synchronizeViewportState()
    }
}

@MainActor
final class EditorScrollView: NSScrollView {
    let editorView = EditorCanvasNSView(frame: .zero)
    private var lastAppliedZoom: CGFloat = 1.0

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        documentView = editorView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        synchronizeViewportMetrics()
        editorView.refreshLayout()
    }

    override func becomeFirstResponder() -> Bool {
        guard let window else { return super.becomeFirstResponder() }
        return window.makeFirstResponder(editorView)
    }

    override func keyDown(with event: NSEvent) {
        editorView.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if editorView.performKeyEquivalent(with: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func selectAll(_ sender: Any?) {
        editorView.selectAll(sender)
    }

    @objc func copy(_ sender: Any?) {
        editorView.copy(sender)
    }

    @objc func cut(_ sender: Any?) {
        editorView.cut(sender)
    }

    @objc func paste(_ sender: Any?) {
        editorView.paste(sender)
    }

    @objc func undo(_ sender: Any?) {
        editorView.undo(sender)
    }

    @objc func redo(_ sender: Any?) {
        editorView.redo(sender)
    }

    func configureViewport() {
        synchronizeViewportMetrics()
        lastAppliedZoom = editorView.viewportController?.zoom ?? 1.0
        editorView.refreshLayout()
    }

    func synchronizeViewportState() {
        synchronizeViewportMetrics()

        guard let viewportController = editorView.viewportController else {
            editorView.refreshLayout()
            return
        }

        if abs(viewportController.zoom - lastAppliedZoom) > 0.0001 {
            applyZoom(viewportController.zoom, anchorInDocumentView: nil, updateModel: false)
            return
        }

        editorView.refreshLayout()
    }

    func applyZoom(_ zoom: CGFloat, anchorInDocumentView anchorPoint: CGPoint?, updateModel: Bool) {
        let previousVisibleRect = contentView.bounds
        let previousDocumentSize = maxDocumentSize(editorView.frame.size)
        let normalizedAnchor = normalizedAnchorPoint(
            anchorPoint: anchorPoint,
            visibleRect: previousVisibleRect,
            documentSize: previousDocumentSize
        )
        let viewportAnchorOffset = anchorOffset(anchorPoint: anchorPoint, visibleRect: previousVisibleRect)

        if updateModel {
            editorView.documentController?.setZoom(zoom)
        }

        synchronizeViewportMetrics()
        editorView.refreshLayout()

        let nextDocumentSize = maxDocumentSize(editorView.frame.size)
        let nextAnchorPoint = CGPoint(
            x: normalizedAnchor.x * nextDocumentSize.width,
            y: normalizedAnchor.y * nextDocumentSize.height
        )
        let nextOrigin = CGPoint(
            x: nextAnchorPoint.x - viewportAnchorOffset.x,
            y: nextAnchorPoint.y - viewportAnchorOffset.y
        )

        scrollToClampedOrigin(nextOrigin)
        lastAppliedZoom = editorView.viewportController?.zoom ?? zoom
    }

    private func synchronizeViewportMetrics() {
        editorView.viewportController?.updateViewportSize(contentSize)
    }

    private func normalizedAnchorPoint(
        anchorPoint: CGPoint?,
        visibleRect: CGRect,
        documentSize: CGSize
    ) -> CGPoint {
        let referencePoint = anchorPoint ?? CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        return CGPoint(
            x: clamp(referencePoint.x / max(documentSize.width, 1), min: 0, max: 1),
            y: clamp(referencePoint.y / max(documentSize.height, 1), min: 0, max: 1)
        )
    }

    private func anchorOffset(anchorPoint: CGPoint?, visibleRect: CGRect) -> CGPoint {
        if let anchorPoint {
            return CGPoint(
                x: anchorPoint.x - visibleRect.minX,
                y: anchorPoint.y - visibleRect.minY
            )
        }

        return CGPoint(x: visibleRect.width * 0.5, y: visibleRect.height * 0.5)
    }

    private func scrollToClampedOrigin(_ origin: CGPoint) {
        let documentSize = maxDocumentSize(editorView.frame.size)
        let viewportSize = contentView.bounds.size
        let clampedOrigin = CGPoint(
            x: clamp(origin.x, min: 0, max: max(documentSize.width - viewportSize.width, 0)),
            y: clamp(origin.y, min: 0, max: max(documentSize.height - viewportSize.height, 0))
        )

        contentView.scroll(to: clampedOrigin)
        reflectScrolledClipView(contentView)
    }

    private func maxDocumentSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

@MainActor
final class EditorCanvasNSView: NSView {
    weak var documentController: DocumentController?
    weak var viewportController: ViewportController?

    private let renderer = PageRenderer()
    private var markedTextStorage: NSAttributedString?
    private var markedBaseRange = NSRange(location: NSNotFound, length: 0)
    private var markedSelection = NSRange(location: NSNotFound, length: 0)
    private var isDraggingSelection = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else { return }
        if window.firstResponder == nil || window.firstResponder === window.contentView {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            inputContext?.invalidateCharacterCoordinates()
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        inputContext?.discardMarkedText()
        clearMarkedText()
        documentController?.finishTextComposition()
        return super.resignFirstResponder()
    }

    func refreshLayout() {
        let size = viewportController?.documentSize ?? CGSize(width: 1000, height: 700)
        if frame.size != size {
            setFrameSize(size)
        }
        inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.95, alpha: 1).setFill()
        dirtyRect.fill()

        guard
            let documentController,
            let viewportController,
            !documentController.pageInfos.isEmpty
        else {
            drawPlaceholder(in: dirtyRect)
            return
        }

        let visiblePages = viewportController.visiblePages(in: visibleRect.insetBy(dx: -200, dy: -200))
        for pageIndex in visiblePages {
            let pageRect = viewportController.pageRect(at: pageIndex)
            drawPageChrome(pageRect)

            guard
                let context = NSGraphicsContext.current?.cgContext,
                let tree = try? documentController.renderTree(for: pageIndex)
            else {
                continue
            }

            let caret = documentController.currentCaret?.rect.pageIndex == pageIndex
                ? documentController.currentCaret
                : nil

            renderer.draw(
                tree: tree,
                in: context,
                pageOrigin: pageRect.origin,
                zoom: viewportController.zoom,
                caret: caret
            )

            drawSelectionRects(pageIndex: pageIndex, pageRect: pageRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        inputContext?.discardMarkedText()
        clearMarkedText()
        documentController?.finishTextComposition()
        isDraggingSelection = false

        guard
            let documentController,
            let viewportController
        else { return }

        let point = convert(event.locationInWindow, from: nil)
        guard let pageIndex = viewportController.pageIndex(at: point) else { return }
        let pagePoint = viewportController.convertToPageSpace(point, pageIndex: pageIndex)
        let extendSelection = event.modifierFlags.contains(.shift)
        documentController.setCaretFromHit(pageIndex: pageIndex, x: pagePoint.x, y: pagePoint.y, extendSelection: extendSelection)
        inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let documentController, let viewportController else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let pageIndex = viewportController.pageIndex(at: point) else { return }
        let pagePoint = viewportController.convertToPageSpace(point, pageIndex: pageIndex)
        isDraggingSelection = true
        documentController.setCaretFromHit(pageIndex: pageIndex, x: pagePoint.x, y: pagePoint.y, extendSelection: true, updateStatus: false)
        inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingSelection {
            needsDisplay = true
        }
        isDraggingSelection = false
    }

    override func keyDown(with event: NSEvent) {
        if inputContext?.handleEvent(event) == true {
            return
        }
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let documentController else {
            return super.performKeyEquivalent(with: event)
        }

        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                _ = documentController.copySelection()
                refreshLayout()
                return true
            case "x":
                documentController.cutSelection()
                refreshLayout()
                return true
            case "v":
                documentController.pasteFromPasteboard()
                refreshLayout()
                return true
            case "a":
                documentController.selectAll()
                refreshLayout()
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard let viewportController else { return }
        let nextZoom = viewportController.zoom * (1 + event.magnification)
        let anchor = convert(event.locationInWindow, from: nil)
        (enclosingScrollView as? EditorScrollView)?.applyZoom(nextZoom, anchorInDocumentView: anchor, updateModel: true)
        inputContext?.invalidateCharacterCoordinates()
    }

    @objc func copy(_ sender: Any?) {
        _ = documentController?.copySelection()
        refreshLayout()
    }

    @objc func cut(_ sender: Any?) {
        documentController?.cutSelection()
        refreshLayout()
    }

    @objc func paste(_ sender: Any?) {
        documentController?.pasteFromPasteboard()
        refreshLayout()
    }

    override func selectAll(_ sender: Any?) {
        documentController?.selectAll()
        refreshLayout()
    }

    @objc func undo(_ sender: Any?) {
        documentController?.undo()
        refreshLayout()
    }

    @objc func redo(_ sender: Any?) {
        documentController?.redo()
        refreshLayout()
    }
}

@MainActor
extension EditorCanvasNSView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let documentController else { return }
        let text: String

        if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else if let plain = string as? String {
            text = plain
        } else {
            return
        }

        let targetRange = currentMarkedRange() ?? sanitizedDocumentRange(replacementRange)
        let previousMarkedText = markedTextStorage?.string
        clearMarkedText()

        guard !text.isEmpty else {
            documentController.finishTextComposition()
            return
        }
        if let targetRange {
            if previousMarkedText != text || targetRange.length != text.count {
                documentController.replaceTextInInputRange(
                    targetRange,
                    with: text,
                    coalescingComposition: true
                )
            }
        } else {
            documentController.insertText(text)
        }
        documentController.finishTextComposition()
        refreshLayout()
    }

    override func doCommand(by selector: Selector) {
        guard let documentController else { return }

        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            documentController.deleteBackward()
        case #selector(NSResponder.deleteForward(_:)):
            documentController.deleteForward()
        case #selector(NSResponder.insertNewline(_:)):
            documentController.insertParagraphBreak()
        case #selector(NSResponder.insertTab(_:)):
            documentController.insertText("\t")
        default:
            let name = selector.description
            let extendSelection = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            switch name {
            case "moveLeft:":
                documentController.moveHorizontal(delta: -1, extendSelection: extendSelection)
            case "moveRight:":
                documentController.moveHorizontal(delta: 1, extendSelection: extendSelection)
            case "moveUp:":
                documentController.moveVertical(delta: -1, extendSelection: extendSelection)
            case "moveDown:":
                documentController.moveVertical(delta: 1, extendSelection: extendSelection)
            case "moveToBeginningOfLine:", "moveToBeginningOfParagraph:":
                documentController.moveToParagraphBoundary(toEnd: false, extendSelection: extendSelection)
            case "moveToEndOfLine:", "moveToEndOfParagraph:":
                documentController.moveToParagraphBoundary(toEnd: true, extendSelection: extendSelection)
            case "cancelOperation:":
                clearMarkedText()
                documentController.finishTextComposition()
            default:
                break
            }
        }

        inputContext?.invalidateCharacterCoordinates()
        refreshLayout()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let documentController else { return }

        let attributed: NSAttributedString
        if let value = string as? NSAttributedString {
            attributed = value
        } else if let text = string as? String {
            attributed = NSAttributedString(string: text)
        } else {
            attributed = NSAttributedString(string: "")
        }

        let targetRange = currentMarkedRange()
            ?? sanitizedDocumentRange(replacementRange)
            ?? sanitizedDocumentRange(documentController.currentInputSelectionRange())

        guard let targetRange else { return }

        documentController.replaceTextInInputRange(
            targetRange,
            with: attributed.string,
            coalescingComposition: true
        )

        guard attributed.length > 0 else {
            clearMarkedText()
            needsDisplay = true
            return
        }

        markedTextStorage = attributed
        markedBaseRange = NSRange(location: targetRange.location, length: attributed.length)
        markedSelection = selectedRange
        inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true
    }

    func unmarkText() {
        clearMarkedText()
        documentController?.finishTextComposition()
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        if let markedRange = currentMarkedRange() {
            let location = markedRange.location + max(markedSelection.location, 0)
            return NSRange(location: location, length: max(markedSelection.length, 0))
        }

        return documentController?.currentInputSelectionRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        currentMarkedRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedTextStorage != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        if
            let markedTextStorage,
            let markedRange = currentMarkedRange()
        {
            let intersection = NSIntersectionRange(range, markedRange)
            if intersection.length > 0 {
                let relative = NSRange(
                    location: max(intersection.location - markedRange.location, 0),
                    length: intersection.length
                )
                actualRange?.pointee = intersection
                return markedTextStorage.attributedSubstring(from: relative)
            }
        }

        if let substring = documentController?.attributedSubstringForInput(range: range) {
            actualRange?.pointee = range
            return substring
        }

        actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.foregroundColor, .backgroundColor, .underlineStyle]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range

        if
            let viewportController,
            let caret = documentController?.currentCaret,
            let markedRange = currentMarkedRange(),
            NSLocationInRange(range.location, markedRange)
        {
            let pageRect = viewportController.pageRect(at: caret.rect.pageIndex)
            let caretHeight = max(16, caret.rect.height * viewportController.zoom)
            let font = markedTextFont(caretHeight: caretHeight)
            let prefixWidth = markedPrefixWidth(
                for: range.location - markedRange.location,
                font: font
            )
            let localRect = CGRect(
                x: pageRect.minX + caret.rect.x * viewportController.zoom + prefixWidth,
                y: pageRect.minY + caret.rect.y * viewportController.zoom,
                width: max(1, viewportController.zoom),
                height: caretHeight
            )
            let windowRect = convert(localRect, to: nil)
            return window?.convertToScreen(windowRect) ?? windowRect
        }

        guard
            let caret = documentController?.currentCaret?.rect,
            let viewportController
        else {
            return .zero
        }

        let pageRect = viewportController.pageRect(at: caret.pageIndex)
        let localRect = CGRect(
            x: pageRect.minX + caret.x * viewportController.zoom,
            y: pageRect.minY + caret.y * viewportController.zoom,
            width: max(1, viewportController.zoom),
            height: max(16, caret.height * viewportController.zoom)
        )
        let windowRect = convert(localRect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        documentController?.currentCaret?.position.charOffset ?? 0
    }

    func conversationIdentifier() -> Int {
        hash
    }
}

@MainActor
private extension EditorCanvasNSView {
    private func drawPlaceholder(in rect: NSRect) {
        let message = "HWP/HWPX 문서를 열거나 새 문서를 만들어 편집을 시작하세요."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = message.size(withAttributes: attributes)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        message.draw(at: origin, withAttributes: attributes)
    }

    private func drawPageChrome(_ pageRect: CGRect) {
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 10), blur: 26, color: NSColor.black.withAlphaComponent(0.12).cgColor)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
            context.restoreGState()

            context.saveGState()
            context.setStrokeColor(NSColor(calibratedWhite: 0.82, alpha: 1).cgColor)
            context.setLineWidth(1)
            context.stroke(pageRect)
            context.restoreGState()
        }
    }

    private func drawSelectionRects(pageIndex: Int, pageRect: CGRect) {
        guard
            let context = NSGraphicsContext.current?.cgContext,
            let viewportController,
            let documentController
        else { return }

        let rects = documentController.selectionRects.filter { $0.pageIndex == pageIndex }
        guard !rects.isEmpty else { return }

        context.saveGState()
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor)
        for rect in rects {
            let scaledRect = CGRect(
                x: pageRect.minX + rect.x * viewportController.zoom,
                y: pageRect.minY + rect.y * viewportController.zoom,
                width: rect.width * viewportController.zoom,
                height: rect.height * viewportController.zoom
            )
            context.fill(scaledRect)
        }
        context.restoreGState()
    }

    private func clearMarkedText() {
        markedTextStorage = nil
        markedBaseRange = NSRange(location: NSNotFound, length: 0)
        markedSelection = NSRange(location: NSNotFound, length: 0)
        inputContext?.invalidateCharacterCoordinates()
    }

    private func currentMarkedRange() -> NSRange? {
        guard let markedTextStorage, markedBaseRange.location != NSNotFound else {
            return nil
        }
        return NSRange(location: max(markedBaseRange.location, 0), length: markedTextStorage.length)
    }

    private func sanitizedDocumentRange(_ range: NSRange) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else {
            return nil
        }
        return range
    }

    private func markedPrefixWidth(for location: Int, font: NSFont) -> CGFloat {
        guard let markedTextStorage else { return 0 }
        let clampedLength = max(0, min(location, markedTextStorage.length))
        guard clampedLength > 0 else { return 0 }
        let prefix = markedTextStorage.attributedSubstring(from: NSRange(location: 0, length: clampedLength))
        let measure = NSMutableAttributedString(attributedString: prefix)
        measure.addAttribute(.font, value: font, range: NSRange(location: 0, length: measure.length))
        return measure.size().width
    }

    private func markedTextFont(caretHeight: CGFloat) -> NSFont {
        NSFont.systemFont(
            ofSize: max(10, min(34, caretHeight * 0.82)),
            weight: .medium
        )
    }
}
