import Foundation

@MainActor
final class CommandBus {
    private unowned let documentController: DocumentController

    init(documentController: DocumentController) {
        self.documentController = documentController
    }

    func newDocument() {
        documentController.createNewDocument()
    }

    func openDocument() {
        documentController.openPanel()
    }

    func saveDocument() {
        documentController.saveDocument()
    }

    func saveDocument(as url: URL) {
        documentController.saveDocument(to: url)
    }

    func insertText(_ text: String) {
        documentController.insertText(text)
    }

    func deleteBackward() {
        documentController.deleteBackward()
    }

    func insertParagraphBreak() {
        documentController.insertParagraphBreak()
    }

    func moveHorizontal(delta: Int, extendSelection: Bool = false) {
        documentController.moveHorizontal(delta: delta, extendSelection: extendSelection)
    }

    func moveVertical(delta: Int, extendSelection: Bool = false) {
        documentController.moveVertical(delta: delta, extendSelection: extendSelection)
    }

    func undo() {
        documentController.undo()
    }

    func redo() {
        documentController.redo()
    }

    func copy() {
        _ = documentController.copySelection()
    }

    func cut() {
        documentController.cutSelection()
    }

    func paste() {
        documentController.pasteFromPasteboard()
    }

    func selectAll() {
        documentController.selectAll()
    }

    func findNext() {
        documentController.findNext()
    }

    func findPrevious() {
        documentController.findPrevious()
    }
}
