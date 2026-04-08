import AppKit
import SwiftUI

private struct EditorCommands: Commands {
    @ObservedObject private var documentController: DocumentController

    init(documentController: DocumentController) {
        _documentController = ObservedObject(wrappedValue: documentController)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 문서") {
                documentController.commandBus.newDocument()
            }
            .keyboardShortcut("n")
        }

        CommandGroup(after: .newItem) {
            Button("문서 열기...") {
                documentController.commandBus.openDocument()
            }
            .keyboardShortcut("o")
        }

        CommandGroup(replacing: .saveItem) {
            Button("저장") {
                documentController.commandBus.saveDocument()
            }
            .keyboardShortcut("s")
            .disabled(!documentController.hasSession)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("실행 취소") {
                documentController.commandBus.undo()
            }
            .keyboardShortcut("z")
            .disabled(!documentController.canUndo)

            Button("다시 실행") {
                documentController.commandBus.redo()
            }
            .keyboardShortcut("Z", modifiers: [.command, .shift])
            .disabled(!documentController.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("잘라내기") {
                documentController.commandBus.cut()
            }
            .keyboardShortcut("x")
            .disabled(!documentController.hasSelection)

            Button("복사") {
                documentController.commandBus.copy()
            }
            .keyboardShortcut("c")
            .disabled(!documentController.hasSelection)

            Button("붙여넣기") {
                documentController.commandBus.paste()
            }
            .keyboardShortcut("v")
            .disabled(!documentController.hasSession)
        }

        CommandGroup(replacing: .textEditing) {
            Button("전체 선택") {
                documentController.commandBus.selectAll()
            }
            .keyboardShortcut("a")
            .disabled(!documentController.hasSession)
        }

        CommandMenu("보기") {
            Button("확대") {
                documentController.setZoom(documentController.viewportController.zoom * 1.1)
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("축소") {
                documentController.setZoom(documentController.viewportController.zoom / 1.1)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Button("100%") {
                documentController.setZoom(1.0)
            }
            .keyboardShortcut("0", modifiers: [.command])
        }

        CommandMenu("검색") {
            Button("다음 찾기") {
                documentController.commandBus.findNext()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(!documentController.hasSession)

            Button("이전 찾기") {
                documentController.commandBus.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!documentController.hasSession)
        }
    }
}

private struct AppSceneView: View {
    @ObservedObject var documentController: DocumentController
    @StateObject private var inspectorViewModel = InspectorViewModel()
    let initialDocumentURL: URL?

    var body: some View {
        ContentView(
            documentController: documentController,
            inspectorViewModel: inspectorViewModel,
            initialDocumentURL: initialDocumentURL
        )
        .frame(minWidth: 1200, minHeight: 760)
        .background(
            WindowAccessor { window in
                AppWindowCoordinator.shared.register(window: window)
            }
        )
        .onAppear {
            EditorShortcutCoordinator.shared.register(documentController: documentController)
            AppWindowCoordinator.shared.activateCurrentWindow()
        }
    }
}

@main
struct HwpMacApp: App {
    @NSApplicationDelegateAdaptor(HwpMacAppDelegate.self) private var appDelegate
    @StateObject private var documentController = DocumentController()

    private var initialDocumentURL: URL? {
        guard CommandLine.arguments.count > 1 else { return nil }
        let candidate = URL(fileURLWithPath: CommandLine.arguments[1])
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    var body: some Scene {
        WindowGroup("RHWP Mac Editor") {
            AppSceneView(
                documentController: documentController,
                initialDocumentURL: initialDocumentURL
            )
        }
        .commands {
            EditorCommands(documentController: documentController)
        }
    }
}
