import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject private var documentController: DocumentController
    @ObservedObject private var viewportController: ViewportController
    @ObservedObject private var inspectorViewModel: InspectorViewModel
    private let initialDocumentURL: URL?
    @AppStorage("ui.inspectorCollapsed") private var isInspectorCollapsed = false

    @State private var newTableRows: Int = 2
    @State private var newTableColumns: Int = 2
    @State private var isFindReplacePresented = false
    @State private var activeDialog: EditorDialogState?
    @State private var didLoadInitialDocument = false

    private let inspectorPanelWidth: CGFloat = 320

    init(
        documentController: DocumentController,
        inspectorViewModel: InspectorViewModel,
        initialDocumentURL: URL? = nil
    ) {
        self.documentController = documentController
        self.viewportController = documentController.viewportController
        self.inspectorViewModel = inspectorViewModel
        self.initialDocumentURL = initialDocumentURL
    }

    var body: some View {
        HStack(spacing: 0) {
            if isInspectorCollapsed {
                collapsedInspectorRail
                Divider()
            } else {
                inspectorPanel
                    .frame(width: inspectorPanelWidth)
                    .background(Color(nsColor: NSColor.windowBackgroundColor))
                Divider()
            }

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    EditorToolbar(
                        documentController: documentController,
                        viewportController: viewportController,
                        newTableRows: $newTableRows,
                        newTableColumns: $newTableColumns,
                        isFindReplacePresented: $isFindReplacePresented,
                        activeDialog: $activeDialog
                    )
                    Divider()
                    EditorRulerView(
                        documentController: documentController,
                        viewportController: viewportController
                    )
                    Divider()
                    EditorCanvasView(
                        documentController: documentController,
                        viewportController: viewportController
                    )
                    Divider()
                    statusBar
                }

                if isFindReplacePresented {
                    FindReplacePanel(
                        documentController: documentController,
                        isPresented: $isFindReplacePresented
                    )
                    .padding(.top, 112)
                    .padding(.trailing, 26)
                    .zIndex(10)
                }

                if activeDialog == .charShape {
                    CharShapeDialogView(
                        documentController: documentController,
                        isPresented: Binding(
                            get: { activeDialog == .charShape },
                            set: { if !$0 { activeDialog = nil } }
                        )
                    )
                    .zIndex(20)
                }

                if activeDialog == .paraShape {
                    ParaShapeDialogView(
                        documentController: documentController,
                        isPresented: Binding(
                            get: { activeDialog == .paraShape },
                            set: { if !$0 { activeDialog = nil } }
                        )
                    )
                    .zIndex(20)
                }

                if activeDialog == .tableProperties {
                    TablePropertiesDialogView(
                        documentController: documentController,
                        isPresented: Binding(
                            get: { activeDialog == .tableProperties },
                            set: { if !$0 { activeDialog = nil } }
                        )
                    )
                    .zIndex(20)
                }

                if activeDialog == .mergeCells {
                    MergeCellsDialogView(
                        documentController: documentController,
                        isPresented: Binding(
                            get: { activeDialog == .mergeCells },
                            set: { if !$0 { activeDialog = nil } }
                        )
                    )
                    .zIndex(20)
                }

                if activeDialog == .bookmarks {
                    BookmarkDialogView(
                        documentController: documentController,
                        isPresented: Binding(
                            get: { activeDialog == .bookmarks },
                            set: { if !$0 { activeDialog = nil } }
                        )
                    )
                    .zIndex(20)
                }

                if activeDialog == .fields {
                    FieldDialogView(
                        documentController: documentController,
                        isPresented: Binding(
                            get: { activeDialog == .fields },
                            set: { if !$0 { activeDialog = nil } }
                        )
                    )
                    .zIndex(20)
                }
            }
        }
        .background(Color(nsColor: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)))
        .animation(.easeInOut(duration: 0.18), value: isInspectorCollapsed)
        .focusedSceneValue(\.activeDocumentController, documentController)
        .onAppear {
            loadInitialDocumentIfNeeded()
            syncInspector()
        }
        .onReceive(documentController.objectWillChange) { _ in
            DispatchQueue.main.async {
                syncInspector()
            }
        }
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inspector")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))

                        Text("문서 정보와 편집 도구")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        isInspectorCollapsed = true
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("인스펙터 접기")
                }

                GroupBox("문서") {
                    VStack(alignment: .leading, spacing: 10) {
                        inspectorRow("파일", inspectorViewModel.fileLabel)
                        inspectorRow("페이지", inspectorViewModel.pageLabel)
                        inspectorRow("줌", "\(inspectorViewModel.zoomPercentage)%")
                        inspectorRow("상태", documentController.isDirty ? "수정됨" : "저장됨")
                        inspectorRow("선택", documentController.hasSelection ? "있음" : "없음")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("찾기/바꾸기") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("찾을 문자열", text: $documentController.searchQuery)
                        TextField("바꿀 문자열", text: $documentController.replaceQuery)

                        HStack(spacing: 8) {
                            Button("이전") {
                                documentController.findPrevious()
                            }
                            Button("다음") {
                                documentController.findNext()
                            }
                        }

                        HStack(spacing: 8) {
                            Button("현재 바꾸기") {
                                documentController.replaceCurrent()
                            }
                            Button("전체 바꾸기") {
                                documentController.replaceAll()
                            }
                        }

                        if !documentController.searchStatus.isEmpty {
                            Text(documentController.searchStatus)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let charProperties = documentController.charProperties {
                    GroupBox("글자 서식") {
                        VStack(alignment: .leading, spacing: 10) {
                            inspectorRow("폰트", charProperties.fontFamily)
                            inspectorRow("크기", "\(Int(charProperties.fontSize))")
                            inspectorRow("굵게", charProperties.bold ? "On" : "Off")
                            inspectorRow("기울임", charProperties.italic ? "On" : "Off")
                            inspectorRow("밑줄", charProperties.underline ? "On" : "Off")
                            colorRow("글자색", charProperties.textColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let paraProperties = documentController.paraProperties {
                    GroupBox("문단 서식") {
                        VStack(alignment: .leading, spacing: 10) {
                            inspectorRow("정렬", paraProperties.alignment)
                            inspectorRow("줄간격", String(format: "%.1f", paraProperties.lineSpacing))
                            inspectorRow("종류", paraProperties.lineSpacingType)
                            inspectorRow("머리 모양", paraProperties.headType)
                            inspectorRow("번호 ID", "\(paraProperties.numberingId)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("표 도구") {
                    VStack(alignment: .leading, spacing: 10) {
                        inspectorRow("표 컨텍스트", documentController.isEditingTable ? "현재 셀" : "없음")
                        inspectorRow("크기", tableSizeLabel)
                        inspectorRow("현재 셀", currentCellLabel)

                        HStack(spacing: 8) {
                            Button("행 위") {
                                documentController.insertTableRow(after: false)
                            }
                            Button("행 아래") {
                                documentController.insertTableRow(after: true)
                            }
                        }
                        .disabled(!documentController.isEditingTable)

                        HStack(spacing: 8) {
                            Button("열 왼쪽") {
                                documentController.insertTableColumn(after: false)
                            }
                            Button("열 오른쪽") {
                                documentController.insertTableColumn(after: true)
                            }
                        }
                        .disabled(!documentController.isEditingTable)

                        HStack(spacing: 8) {
                            Button("행 삭제") {
                                documentController.deleteCurrentTableRow()
                            }
                            Button("열 삭제") {
                                documentController.deleteCurrentTableColumn()
                            }
                        }
                        .disabled(!documentController.isEditingTable)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let caret = documentController.currentCaret {
                    GroupBox("Caret") {
                        VStack(alignment: .leading, spacing: 10) {
                            inspectorRow("Section", "\(caret.position.sectionIndex)")
                            inspectorRow("Paragraph", "\(caret.position.paragraphIndex)")
                            inspectorRow("Offset", "\(caret.position.charOffset)")
                            inspectorRow("Page", "\(caret.rect.pageIndex + 1)")
                            inspectorRow("Cell", caret.position.cellContext == nil ? "본문" : "셀/글상자")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("엔진") {
                    VStack(alignment: .leading, spacing: 10) {
                        inspectorRow("버전", documentController.documentInfo?.version ?? "-")
                        inspectorRow("구역 수", "\(documentController.documentInfo?.sectionCount ?? 0)")
                        inspectorRow("페이지 수", "\(documentController.documentInfo?.pageCount ?? 0)")
                        inspectorRow("Fallback Font", documentController.documentInfo?.fallbackFont ?? "-")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("상태 메시지") {
                    Text(documentController.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
    }

    private var collapsedInspectorRail: some View {
        VStack(spacing: 0) {
            Button {
                isInspectorCollapsed = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .help("인스펙터 열기")

            Spacer()
        }
        .frame(width: 36)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    private var tableSizeLabel: String {
        guard let dims = documentController.currentTableDimensions else { return "-" }
        return "\(dims.rowCount) × \(dims.colCount)"
    }

    private var currentCellLabel: String {
        guard let cell = documentController.currentCellInfo else { return "-" }
        return "r\(cell.row) c\(cell.col)"
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(documentController.isDirty ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            Text(documentController.searchStatus.isEmpty ? documentController.statusMessage : documentController.searchStatus)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            Text(documentController.fileURL?.path ?? "메모리 문서")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: NSColor.controlBackgroundColor))
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorRow(_ label: String, _ hex: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Circle()
                .fill(Color(nsColor: NSColor(cssHex: hex)))
                .frame(width: 12, height: 12)

            Text(hex)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func syncInspector() {
        inspectorViewModel.sync(from: documentController)
    }

    private func loadInitialDocumentIfNeeded() {
        guard !didLoadInitialDocument else { return }
        didLoadInitialDocument = true

        if let initialDocumentURL {
            documentController.openDocument(at: initialDocumentURL)
        } else if !documentController.hasSession {
            documentController.createNewDocument()
        }
    }
}
