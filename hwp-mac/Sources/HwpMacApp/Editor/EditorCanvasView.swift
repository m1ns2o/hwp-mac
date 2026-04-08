import AppKit
import SwiftUI

struct EditorCanvasView: NSViewRepresentable {
    @ObservedObject var documentController: DocumentController
    @ObservedObject var viewportController: ViewportController

    func makeNSView(context: Context) -> EditorScrollView {
        let scrollView = EditorScrollView()
        scrollView.editorView.documentController = documentController
        scrollView.editorView.viewportController = viewportController
        scrollView.editorView.refreshLayout()
        return scrollView
    }

    func updateNSView(_ nsView: EditorScrollView, context: Context) {
        nsView.editorView.documentController = documentController
        nsView.editorView.viewportController = viewportController
        nsView.editorView.refreshLayout()
    }
}

@MainActor
final class EditorScrollView: NSScrollView {
    let editorView = EditorCanvasNSView(frame: .zero)

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
}

@MainActor
final class EditorCanvasNSView: NSView {
    weak var documentController: DocumentController?
    weak var viewportController: ViewportController?

    private let renderer = PageRenderer()
    private var markedTextStorage: NSAttributedString?
    private var markedSelection = NSRange(location: NSNotFound, length: 0)
    private var isDraggingSelection = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func refreshLayout() {
        let size = viewportController?.documentSize ?? CGSize(width: 1000, height: 700)
        if frame.size != size {
            setFrameSize(size)
        }
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

            drawSelectionRects(pageIndex: pageIndex, pageRect: pageRect)

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

            drawMarkedTextIfNeeded(pageIndex: pageIndex, pageRect: pageRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let documentController, let viewportController else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let pageIndex = viewportController.pageIndex(at: point) else { return }
        let pagePoint = viewportController.convertToPageSpace(point, pageIndex: pageIndex)
        isDraggingSelection = true
        documentController.setCaretFromHit(pageIndex: pageIndex, x: pagePoint.x, y: pagePoint.y, extendSelection: true, updateStatus: false)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingSelection {
            needsDisplay = true
        }
        isDraggingSelection = false
    }

    override func keyDown(with event: NSEvent) {
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
                return true
            case "x":
                documentController.cutSelection()
                return true
            case "v":
                documentController.pasteFromPasteboard()
                return true
            case "a":
                documentController.selectAll()
                return true
            default:
                break
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard let documentController, let viewportController else { return }
        let nextZoom = viewportController.zoom * (1 + event.magnification)
        documentController.setZoom(nextZoom)
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

        markedTextStorage = nil
        markedSelection = NSRange(location: NSNotFound, length: 0)

        guard !text.isEmpty else { return }
        documentController.insertText(text)
        refreshLayout()
    }

    override func doCommand(by selector: Selector) {
        guard let documentController else { return }

        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            documentController.deleteBackward()
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
            case "cancelOperation:":
                markedTextStorage = nil
                markedSelection = NSRange(location: NSNotFound, length: 0)
            default:
                break
            }
        }

        refreshLayout()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let attributed: NSAttributedString
        if let value = string as? NSAttributedString {
            attributed = value
        } else if let text = string as? String {
            attributed = NSAttributedString(string: text)
        } else {
            attributed = NSAttributedString(string: "")
        }

        markedTextStorage = attributed.length == 0 ? nil : attributed
        markedSelection = selectedRange
        needsDisplay = true
    }

    func unmarkText() {
        markedTextStorage = nil
        markedSelection = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        guard let caret = documentController?.currentCaret?.position else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: caret.charOffset, length: 0)
    }

    func markedRange() -> NSRange {
        guard let markedTextStorage else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let base = selectedRange()
        guard base.location != NSNotFound else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: max(base.location, 0), length: markedTextStorage.length)
    }

    func hasMarkedText() -> Bool {
        markedTextStorage != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let markedTextStorage else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }
        actualRange?.pointee = NSRange(location: 0, length: markedTextStorage.length)
        return markedTextStorage
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.foregroundColor, .backgroundColor, .underlineStyle]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range

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
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor)
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

    private func drawMarkedTextIfNeeded(pageIndex: Int, pageRect: CGRect) {
        guard
            let markedTextStorage,
            let viewportController,
            let caret = documentController?.currentCaret,
            caret.rect.pageIndex == pageIndex
        else { return }

        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let attributed = NSMutableAttributedString(attributedString: markedTextStorage)
        attributed.addAttributes(attributes, range: NSRange(location: 0, length: attributed.length))

        let drawRect = CGRect(
            x: pageRect.minX + caret.rect.x * viewportController.zoom,
            y: pageRect.minY + caret.rect.y * viewportController.zoom - 20,
            width: max(80, CGFloat(attributed.length) * font.pointSize),
            height: 24
        )
        attributed.draw(in: drawRect)
    }
}
