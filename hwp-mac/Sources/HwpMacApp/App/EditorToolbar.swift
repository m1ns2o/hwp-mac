import SwiftUI

@MainActor
struct EditorToolbar: View {
    @ObservedObject var documentController: DocumentController
    @ObservedObject var viewportController: ViewportController
    @ObservedObject var inspectorViewModel: InspectorViewModel

    @Binding var newTableRows: Int
    @Binding var newTableColumns: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                documentOverviewCard
                Spacer(minLength: 0)
                zoomControls
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    documentCommandsSection
                    clipboardSection
                    historySection
                    typographySection
                    paragraphSection
                    tableSection
                    searchSection
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor.windowBackgroundColor),
                    Color(nsColor: NSColor.controlBackgroundColor),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var documentOverviewCard: some View {
        toolbarCard("문서", minWidth: 340) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(documentController.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)

                        Text(documentController.fileURL?.path ?? "메모리 문서")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(documentController.isDirty ? "편집 중" : "저장됨")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(documentController.isDirty ? Color.orange : Color.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill((documentController.isDirty ? Color.orange : Color.green).opacity(0.12))
                        )
                }

                HStack(spacing: 8) {
                    toolbarMetric("엔진", documentController.documentInfo?.version ?? "-")
                    toolbarMetric("선택", documentController.hasSelection ? "활성" : "없음")
                    toolbarMetric("표", documentController.isEditingTable ? currentCellLabel : "-")
                }
            }
        }
    }

    private var zoomControls: some View {
        toolbarCard("보기", minWidth: 300) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    toolbarMetric("줌", "\(inspectorViewModel.zoomPercentage)%")
                    toolbarMetric("페이지", inspectorViewModel.pageLabel)
                }

                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { viewportController.zoom },
                            set: { documentController.setZoom($0) }
                        ),
                        in: 0.25...4.0
                    )

                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var documentCommandsSection: some View {
        toolbarCard("파일", minWidth: 220) {
            HStack(spacing: 8) {
                toolbarTileButton("새 문서", systemImage: "doc.badge.plus") {
                    documentController.commandBus.newDocument()
                }
                toolbarTileButton("열기", systemImage: "folder") {
                    documentController.commandBus.openDocument()
                }
                toolbarTileButton("저장", systemImage: "square.and.arrow.down", prominent: true, isEnabled: documentController.hasSession) {
                    documentController.commandBus.saveDocument()
                }
            }
        }
    }

    private var clipboardSection: some View {
        toolbarCard("클립보드", minWidth: 220) {
            HStack(spacing: 8) {
                toolbarTileButton("붙여넣기", systemImage: "doc.on.clipboard", prominent: true, isEnabled: documentController.hasSession) {
                    documentController.commandBus.paste()
                }

                VStack(spacing: 8) {
                    toolbarMiniButton("잘라내기", systemImage: "scissors", isEnabled: documentController.hasSelection) {
                        documentController.commandBus.cut()
                    }
                    toolbarMiniButton("복사", systemImage: "doc.on.doc", isEnabled: documentController.hasSelection) {
                        documentController.commandBus.copy()
                    }
                }
            }
        }
    }

    private var historySection: some View {
        toolbarCard("기록", minWidth: 160) {
            HStack(spacing: 8) {
                toolbarTileButton("실행 취소", systemImage: "arrow.uturn.backward", isEnabled: documentController.canUndo) {
                    documentController.commandBus.undo()
                }
                toolbarTileButton("다시 실행", systemImage: "arrow.uturn.forward", isEnabled: documentController.canRedo) {
                    documentController.commandBus.redo()
                }
            }
        }
    }

    private var typographySection: some View {
        toolbarCard("글꼴", minWidth: 270) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    toolbarValueChip("서체", documentController.charProperties?.fontFamily ?? "문단 스타일")
                    toolbarValueChip("크기", fontSizeLabel)
                    toolbarValueChip("색상", documentController.charProperties?.textColor ?? "-")
                }

                HStack(spacing: 8) {
                    toolbarToggleButton("B", systemImage: "bold", isActive: documentController.charProperties?.bold == true) {
                        documentController.toggleBold()
                    }
                    toolbarToggleButton("I", systemImage: "italic", isActive: documentController.charProperties?.italic == true) {
                        documentController.toggleItalic()
                    }
                    toolbarToggleButton("U", systemImage: "underline", isActive: documentController.charProperties?.underline == true) {
                        documentController.toggleUnderline()
                    }
                }
            }
        }
    }

    private var paragraphSection: some View {
        toolbarCard("문단", minWidth: 250) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    toolbarValueChip("정렬", alignmentLabel)
                    toolbarValueChip("줄간격", lineSpacingLabel)
                }

                HStack(spacing: 8) {
                    alignmentToolbarButton(systemImage: "text.alignleft", active: documentController.paraProperties?.alignment == "left") {
                        documentController.setAlignment("left")
                    }
                    alignmentToolbarButton(systemImage: "text.aligncenter", active: documentController.paraProperties?.alignment == "center") {
                        documentController.setAlignment("center")
                    }
                    alignmentToolbarButton(systemImage: "text.alignright", active: documentController.paraProperties?.alignment == "right") {
                        documentController.setAlignment("right")
                    }
                    alignmentToolbarButton(systemImage: "text.justify", active: documentController.paraProperties?.alignment == "justify") {
                        documentController.setAlignment("justify")
                    }
                }
            }
        }
    }

    private var tableSection: some View {
        toolbarCard("표", minWidth: 320) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    toolbarValueChip("행", "\(newTableRows)")
                    Stepper("", value: $newTableRows, in: 1...20)
                        .labelsHidden()
                        .controlSize(.small)

                    toolbarValueChip("열", "\(newTableColumns)")
                    Stepper("", value: $newTableColumns, in: 1...12)
                        .labelsHidden()
                        .controlSize(.small)

                    if documentController.isEditingTable {
                        toolbarValueChip("현재 셀", currentCellLabel)
                    }
                }

                HStack(spacing: 8) {
                    toolbarMiniButton("표 삽입", systemImage: "tablecells", isEnabled: documentController.hasSession) {
                        documentController.createTable(rows: newTableRows, columns: newTableColumns)
                    }
                    toolbarMiniButton("행 추가", systemImage: "rectangle.split.3x1", isEnabled: documentController.isEditingTable) {
                        documentController.insertTableRow(after: true)
                    }
                    toolbarMiniButton("열 추가", systemImage: "rectangle.split.1x3", isEnabled: documentController.isEditingTable) {
                        documentController.insertTableColumn(after: true)
                    }
                    toolbarMiniButton("행 삭제", systemImage: "trash", isEnabled: documentController.isEditingTable) {
                        documentController.deleteCurrentTableRow()
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        toolbarCard("찾기/바꾸기", minWidth: 320) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("찾을 문자열", text: $documentController.searchQuery)
                    .textFieldStyle(.roundedBorder)

                TextField("바꿀 문자열", text: $documentController.replaceQuery)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    toolbarMiniButton("이전", systemImage: "arrow.up.circle", isEnabled: documentController.hasSession) {
                        documentController.findPrevious()
                    }
                    toolbarMiniButton("다음", systemImage: "arrow.down.circle", isEnabled: documentController.hasSession) {
                        documentController.findNext()
                    }
                    toolbarMiniButton("현재 바꾸기", systemImage: "character.cursor.ibeam", isEnabled: documentController.hasSession) {
                        documentController.replaceCurrent()
                    }
                    toolbarMiniButton("전체 바꾸기", systemImage: "text.append", isEnabled: documentController.hasSession) {
                        documentController.replaceAll()
                    }
                }
            }
        }
    }

    private var fontSizeLabel: String {
        guard let size = documentController.charProperties?.fontSize else { return "-" }
        return String(Int(size.rounded()))
    }

    private var alignmentLabel: String {
        switch documentController.paraProperties?.alignment {
        case "left":
            return "왼쪽"
        case "center":
            return "가운데"
        case "right":
            return "오른쪽"
        case "justify":
            return "양쪽"
        default:
            return "-"
        }
    }

    private var lineSpacingLabel: String {
        guard let spacing = documentController.paraProperties?.lineSpacing else { return "-" }
        return String(format: "%.1f", spacing)
    }

    private var currentCellLabel: String {
        guard let cell = documentController.currentCellInfo else { return "-" }
        return "r\(cell.row) c\(cell.col)"
    }
}

private extension EditorToolbar {
    func toolbarCard<Content: View>(_ title: String, minWidth: CGFloat? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            content()
        }
        .padding(12)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.9))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    func toolbarTileButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22, height: 18)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(width: 62, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.black.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    func toolbarMiniButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    func toolbarToggleButton(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 40, height: 38)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.black.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!documentController.hasSession)
        .opacity(documentController.hasSession ? 1 : 0.42)
    }

    func alignmentToolbarButton(systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 32)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.14) : Color.black.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .disabled(!documentController.hasSession)
        .opacity(documentController.hasSession ? 1 : 0.42)
    }

    func toolbarValueChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    func toolbarMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}
