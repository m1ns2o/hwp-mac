import AppKit
import SwiftUI

@MainActor
struct EditorToolbar: View {
    @ObservedObject var documentController: DocumentController
    @ObservedObject var viewportController: ViewportController

    @Binding var newTableRows: Int
    @Binding var newTableColumns: Int
    @Binding var isFindReplacePresented: Bool
    @Binding var activeDialog: EditorDialogState?

    @State private var draftDisplayName = ""
    @State private var isRibbonCollapsed = false
    @State private var activePopover: ToolbarPopover?

    var body: some View {
        VStack(spacing: 0) {
            titleBarTop
            Divider()
            titleBarBottom
            if !isRibbonCollapsed {
                Divider()
                ribbonToolbarRow
            } else {
                Divider()
                collapsedRibbonBar
            }
            Divider()
            formatToolbarRow
        }
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .onAppear(perform: syncTitleDraft)
        .onChange(of: documentController.displayName) { _, _ in
            syncTitleDraft()
        }
    }
}

private extension EditorToolbar {
    var collapsedRibbonBar: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRibbonCollapsed = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("도구 모음 펼치기")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: NSColor.controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.35), lineWidth: 1)
            }
            .padding(.trailing, 12)
        }
        .frame(height: 32)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    var titleBarTop: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                HwpBrandBadge()

                HStack(spacing: 8) {
                    titleField

                    statusCapsule(
                        autosaveMessage,
                        tint: documentController.isDirty ? .orange : .green
                    )

                    utilityIconButton("message", enabled: false) {}
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                utilityIconButton("command") {
                    showShortcutGuide()
                }

                VerticalHairline(height: 18)

                Button {
                    togglePopover(.help)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: popoverBinding(for: .help),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    toolbarPopoverPanel(.help) {
                        menuAction("도움말", systemImage: "questionmark.circle") {
                            showUnsupportedFeature("도움말")
                        }
                        menuAction("한글 정보...", systemImage: "info.circle") {
                            NSApp.orderFrontStandardAboutPanel(nil)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    var titleBarBottom: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    toolbarMenu("파일", popover: .file) { fileMenuContent }
                    titleMenuSeparator
                    toolbarMenu("편집", popover: .edit) { editMenuContent }
                    titleMenuSeparator
                    toolbarMenu("보기", popover: .view) { viewMenuContent }
                    titleMenuSeparator
                    toolbarMenu("입력", popover: .insert) { insertMenuContent }
                    titleMenuSeparator
                    toolbarMenu("서식", popover: .format) { formatMenuContent }
                    titleMenuSeparator
                    toolbarMenu("쪽", popover: .page) { pageMenuContent }
                    titleMenuSeparator
                    toolbarMenu("표", popover: .table) { tableMenuContent }
                    titleMenuSeparator
                    toolbarMenu("검토", popover: .review) { reviewMenuContent }
                    titleMenuSeparator
                    toolbarMenu("도구", popover: .tools) { toolsMenuContent }
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    var ribbonToolbarRow: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRibbonCollapsed = true
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)

            VerticalHairline(height: 58)
                .padding(.trailing, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ribbonGroup {
                        ribbonToolbarButton(
                            "저장하기",
                            systemImage: "square.and.arrow.down",
                            isEnabled: documentController.hasSession && documentController.isDirty
                        ) {
                            documentController.commandBus.saveDocument()
                        }
                    }

                    ribbonSeparator

                    ribbonGroup {
                        ribbonToolbarButton("오려\n두기", systemImage: "scissors", isEnabled: documentController.hasSelection) {
                            documentController.commandBus.cut()
                        }
                        ribbonToolbarButton("복사하기", systemImage: "doc.on.doc", isEnabled: documentController.hasSelection) {
                            documentController.commandBus.copy()
                        }
                        ribbonToolbarButton("붙이기", systemImage: "clipboard", isEnabled: documentController.hasSession) {
                            documentController.commandBus.paste()
                        }
                        ribbonToolbarButton("모양\n복사", systemImage: "paintbrush.pointed", isEnabled: false) {
                            showUnsupportedFeature("모양 복사")
                        }
                    }

                    ribbonSeparator

                    ribbonGroup {
                        ribbonMenuButton("찾기", systemImage: "magnifyingglass", popover: .ribbonFind, isEnabled: documentController.hasSession) {
                            findMenuContent
                        }
                    }

                    ribbonSeparator

                    ribbonGroup {
                        ribbonMenuButton("도형", systemImage: "scribble.variable", popover: .ribbonInsertShape, isEnabled: false) {
                            insertShapeMenuContent
                        }
                        ribbonToolbarButton("그림", systemImage: "photo", isEnabled: false) {
                            showUnsupportedFeature("그림")
                        }
                        ribbonMenuButton("표", systemImage: "tablecells", popover: .ribbonTable, isEnabled: documentController.hasSession) {
                            tableQuickMenuContent
                        }
                        ribbonMenuButton("차트", systemImage: "chart.bar", popover: .ribbonChart, isEnabled: false) {
                            chartMenuContent
                        }
                        ribbonToolbarButton("웹\n동영상", systemImage: "play.rectangle.on.rectangle", isEnabled: false) {
                            showUnsupportedFeature("웹 동영상")
                        }
                    }

                    ribbonSeparator

                    ribbonGroup {
                        ribbonToolbarButton("각주", systemImage: "text.insert", isEnabled: documentController.hasSession) {
                            documentController.insertFootnote()
                        }
                        ribbonToolbarButton("미주", systemImage: "note.text", isEnabled: false) {
                            showUnsupportedFeature("미주")
                        }
                        ribbonToolbarButton("하이퍼\n링크", systemImage: "link", isEnabled: false) {
                            showUnsupportedFeature("하이퍼링크")
                        }
                        ribbonToolbarButton("문자표", systemImage: "character.book.closed", isEnabled: false) {
                            showUnsupportedFeature("문자표")
                        }
                    }

                    ribbonSeparator

                    ribbonGroup {
                        ribbonToolbarButton("글자\n모양", systemImage: "character.cursor.ibeam", isEnabled: documentController.hasSession) {
                            openDialog(.charShape)
                        }
                        ribbonToolbarButton("문단\n모양", systemImage: "text.alignleft", isEnabled: documentController.hasSession) {
                            openDialog(.paraShape)
                        }
                        ribbonToolbarButton("개체\n속성", systemImage: "slider.horizontal.3", isEnabled: false) {
                            showUnsupportedFeature("개체 속성")
                        }
                    }

                    ribbonSeparator

                    ribbonGroup {
                        ribbonMenuButton("머리말", systemImage: "rectangle.topthird.inset.filled", popover: .ribbonHeader, isEnabled: documentController.hasSession) {
                            headerFooterMenuContent(isHeader: true)
                        }
                        ribbonMenuButton("꼬리말", systemImage: "rectangle.bottomthird.inset.filled", popover: .ribbonFooter, isEnabled: documentController.hasSession) {
                            headerFooterMenuContent(isHeader: false)
                        }
                        ribbonToolbarButton("조판\n부호", systemImage: "paragraphsign", isEnabled: false) {
                            showUnsupportedFeature("조판 부호")
                        }
                        ribbonToolbarButton("문단\n부호", systemImage: "return", isEnabled: false) {
                            showUnsupportedFeature("문단 부호")
                        }
                        ribbonToolbarButton("격자\n보기", systemImage: "square.grid.3x3", isEnabled: false) {
                            showUnsupportedFeature("격자 보기")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
        .frame(height: 88)
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

    var formatToolbarRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                compactToolbarButton("arrow.uturn.backward", isEnabled: documentController.canUndo) {
                    documentController.commandBus.undo()
                }
                compactToolbarButton("arrow.uturn.forward", isEnabled: documentController.canRedo) {
                    documentController.commandBus.redo()
                }

                compactSeparator

                comboMenuField(styleNameLabel, width: 148, popover: .styleName) {
                    menuAction("바탕글") {
                        documentController.statusMessage = "현재 스타일은 바탕글입니다."
                    }
                }
                comboMenuField("대표", width: 84, popover: .fontLanguage) {
                    ForEach(["대표", "한글", "영문", "한자", "일어", "외국어", "기호", "사용자"], id: \.self) { language in
                        menuAction(language) {
                            documentController.statusMessage = "\(language) 글꼴 범위 선택 UI를 웹 버전과 맞추는 중입니다."
                        }
                    }
                }
                comboMenuField(selectedFontDisplayName, width: 176, popover: .fontName) {
                    fontNameMenuContent
                }
                metricComboField(
                    value: fontSizeLabel,
                    unit: "pt",
                    width: 56,
                    popover: .fontSize,
                    isEnabled: documentController.hasSession,
                    presetValues: ["8", "9", "10", "11", "12", "14", "16", "18", "20", "22", "24", "26", "36", "48", "72"],
                    applyValue: { value in
                        if let size = Double(value) {
                            documentController.setFontSize(size)
                        }
                    },
                    decrementAction: { documentController.decreaseFontSize() },
                    incrementAction: { documentController.increaseFontSize() }
                )

                compactSeparator

                textFormatButton(kind: .bold, isActive: documentController.charProperties?.bold == true, isEnabled: documentController.hasSession) {
                    documentController.toggleBold()
                }
                textFormatButton(kind: .italic, isActive: documentController.charProperties?.italic == true, isEnabled: documentController.hasSession) {
                    documentController.toggleItalic()
                }
                lineStyleMenuButton(kind: .underline, popover: .underline, isActive: documentController.charProperties?.underline == true, isEnabled: documentController.hasSession) {
                    documentController.toggleUnderline()
                }
                lineStyleMenuButton(kind: .strike, popover: .strikethrough, isActive: documentController.charProperties?.strikethrough == true, isEnabled: documentController.hasSession) {
                    documentController.toggleStrikethrough()
                }
                Button {
                    togglePopover(.textColor)
                } label: {
                    colorGlyphButton(text: "가", color: currentTextColor, isEnabled: documentController.hasSession)
                }
                .buttonStyle(.plain)
                .disabled(!documentController.hasSession)
                .opacity(documentController.hasSession ? 1 : 0.35)
                .popover(
                    isPresented: popoverBinding(for: .textColor),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    toolbarPopoverPanel(.textColor) {
                        textColorMenuContent
                    }
                }

                Button {
                    togglePopover(.highlight)
                } label: {
                    colorGlyphButton(icon: "highlighter", color: currentHighlightColor, isEnabled: documentController.hasSession)
                }
                .buttonStyle(.plain)
                .disabled(!documentController.hasSession)
                .opacity(documentController.hasSession ? 1 : 0.35)
                .popover(
                    isPresented: popoverBinding(for: .highlight),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    toolbarPopoverPanel(.highlight) {
                        highlightColorMenuContent
                    }
                }

                compactSeparator

                alignmentButton(style: .justify, isActive: documentController.paraProperties?.alignment == "justify", isEnabled: documentController.hasSession) {
                    documentController.setAlignment("justify")
                }
                alignmentButton(style: .left, isActive: documentController.paraProperties?.alignment == "left", isEnabled: documentController.hasSession) {
                    documentController.setAlignment("left")
                }
                alignmentButton(style: .center, isActive: documentController.paraProperties?.alignment == "center", isEnabled: documentController.hasSession) {
                    documentController.setAlignment("center")
                }
                alignmentButton(style: .right, isActive: documentController.paraProperties?.alignment == "right", isEnabled: documentController.hasSession) {
                    documentController.setAlignment("right")
                }
                alignmentButton(style: .distribute, isActive: false, isEnabled: false) {
                    showUnsupportedFeature("배분 정렬")
                }
                alignmentButton(style: .split, isActive: false, isEnabled: false) {
                    showUnsupportedFeature("나눔 정렬")
                }

                compactSeparator

                comboMenuField(lineSpacingLabelWithUnit, width: 88, leading: AnyView(lineSpacingGlyph), popover: .lineSpacing) {
                    ForEach(["100", "130", "160", "180", "200", "300"], id: \.self) { value in
                        Button("\(value) %") {
                            activePopover = nil
                            documentController.setLineSpacing(Double(value) ?? 160)
                        }
                        .buttonStyle(ToolbarMenuRowButtonStyle())
                    }
                }

                compactSeparator

                listMenuButton(systemImage: "list.bullet", popover: .bulletList, isEnabled: documentController.hasSession) {
                    bulletListMenuContent
                }
                listMenuButton(systemImage: "list.number", popover: .numberingList, isEnabled: documentController.hasSession) {
                    numberingListMenuContent
                }

                compactSeparator

                compactToolbarButton("increase.indent", isEnabled: documentController.hasSession) {
                    documentController.increaseParagraphLevel()
                }
                compactToolbarButton("decrease.indent", isEnabled: documentController.hasSession) {
                    documentController.decreaseParagraphLevel()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(height: 40)
        .background(Color(nsColor: NSColor.underPageBackgroundColor).opacity(0.78))
    }
}

private extension EditorToolbar {
    var titleField: some View {
        HStack(spacing: 8) {
            TextField("이름 바꾸기", text: $draftDisplayName, onCommit: commitDisplayName)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 320)

            Text(documentController.fileURL == nil ? "로컬 문서" : "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: NSColor.textBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    var autosaveMessage: String {
        if !documentController.hasSession {
            return "문서를 열어주세요."
        }
        return documentController.isDirty ? "변경 사항이 저장되지 않았습니다." : "자동 저장되었습니다."
    }

    var styleNameLabel: String {
        "바탕글"
    }

    var selectedFontDisplayName: String {
        let currentName = documentController.charProperties?.fontFamily ?? "Malgun Gothic"
        if let sample = fontSamples.first(where: { $0.familyName == currentName || $0.displayName == currentName }) {
            return sample.displayName
        }
        return currentName
    }

    var fontSizeLabel: String {
        guard let size = documentController.charProperties?.fontSize else { return "12.0" }
        return String(format: "%.1f", size / 100)
    }

    var lineSpacingLabelWithUnit: String {
        "\(lineSpacingLabel) %"
    }

    var lineSpacingLabel: String {
        let spacing = documentController.paraProperties?.lineSpacing ?? 160
        return String(Int(spacing.rounded()))
    }

    var currentTextColor: Color {
        guard
            let hex = documentController.charProperties?.textColor,
            let nsColor = NSColor(hexString: hex)
        else {
            return .red
        }
        return Color(nsColor: nsColor)
    }

    var currentHighlightColor: Color {
        guard
            let hex = documentController.charProperties?.shadeColor,
            let nsColor = NSColor(hexString: hex)
        else {
            return Color.yellow.opacity(0.9)
        }
        return Color(nsColor: nsColor)
    }

    var titleMenuSeparator: some View {
        VerticalHairline(height: 18)
            .padding(.horizontal, 2)
    }

    var ribbonSeparator: some View {
        VerticalHairline(height: 58)
            .padding(.horizontal, 8)
    }

    var compactSeparator: some View {
        VerticalHairline(height: 24)
            .padding(.horizontal, 8)
    }

    var fontSamples: [FontMenuSample] {
        [
            FontMenuSample(displayName: "맑은 고딕", familyName: "Malgun Gothic"),
            FontMenuSample(displayName: "Apple SD 산돌고딕 Neo", familyName: "Apple SD Gothic Neo"),
            FontMenuSample(displayName: "나눔고딕", familyName: "NanumGothic"),
            FontMenuSample(displayName: "Pretendard", familyName: "Pretendard"),
            FontMenuSample(displayName: "SpoqaHanSans", familyName: "SpoqaHanSans"),
            FontMenuSample(displayName: "해피니스 산스 볼드", familyName: "Happiness Sans Bold"),
            FontMenuSample(displayName: "해피니스 산스 레귤러", familyName: "Happiness Sans Regular"),
            FontMenuSample(displayName: "HY견고딕", familyName: "HY견고딕"),
            FontMenuSample(displayName: "HY견명조", familyName: "HY견명조"),
            FontMenuSample(displayName: "Arial", familyName: "Arial"),
            FontMenuSample(displayName: "Times New Roman", familyName: "Times New Roman"),
        ]
    }

    @ViewBuilder
    var fontNameMenuContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("글꼴")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 2)

            Divider()
                .padding(.horizontal, 4)

            ForEach(fontSamples, id: \.self) { sample in
                Button {
                    activePopover = nil
                    documentController.setFontFamily(sample.familyName)
                } label: {
                    fontMenuRow(
                        sample: sample,
                        isSelected: documentController.charProperties?.fontFamily == sample.familyName
                            || documentController.charProperties?.fontFamily == sample.displayName
                    )
                }
                .buttonStyle(ToolbarMenuRowButtonStyle())
            }
        }
    }

    @ViewBuilder
    var fileMenuContent: some View {
        menuAction("저장하기", systemImage: "square.and.arrow.down", shortcut: "Cmd+S", enabled: documentController.hasSession) {
            documentController.commandBus.saveDocument()
        }
        menuAction("다른 이름으로 저장하기", systemImage: "square.and.arrow.down.on.square", enabled: documentController.hasSession) {
            documentController.saveDocumentAs()
        }
        Divider()
        menuAction("공유", systemImage: "square.and.arrow.up", enabled: false) {
            showUnsupportedFeature("공유")
        }
        Divider()
        menuAction("이름 바꾸기", systemImage: "pencil", enabled: documentController.hasSession) {
            documentController.statusMessage = "상단 제목 필드에서 이름을 바꿀 수 있습니다."
        }
        menuAction("다운로드", systemImage: "arrow.down.to.line", enabled: false) {
            showUnsupportedFeature("다운로드")
        }
        menuAction("PDF로 다운로드", systemImage: "doc.richtext", enabled: false) {
            showUnsupportedFeature("PDF로 다운로드")
        }
        Divider()
        menuAction("편집 용지...", systemImage: "doc.text.magnifyingglass", shortcut: "F7", enabled: documentController.hasSession) {
            openDialog(.pageSetup)
        }
        menuAction("인쇄", systemImage: "printer", shortcut: "Cmd+P", enabled: false) {
            showUnsupportedFeature("인쇄")
        }
        Divider()
        menuAction("문서 정보...", systemImage: "info.circle", enabled: documentController.documentInfo != nil) {
            showDocumentInfo()
        }
    }

    @ViewBuilder
    var editMenuContent: some View {
        menuAction("되돌리기", systemImage: "arrow.uturn.backward", shortcut: "Cmd+Z", enabled: documentController.canUndo) {
            documentController.commandBus.undo()
        }
        menuAction("다시 실행", systemImage: "arrow.uturn.forward", shortcut: "Cmd+Shift+Z", enabled: documentController.canRedo) {
            documentController.commandBus.redo()
        }
        Divider()
        menuAction("오려 두기", systemImage: "scissors", shortcut: "Cmd+X", enabled: documentController.hasSelection) {
            documentController.commandBus.cut()
        }
        menuAction("복사하기", systemImage: "doc.on.doc", shortcut: "Cmd+C", enabled: documentController.hasSelection) {
            documentController.commandBus.copy()
        }
        menuAction("붙이기", systemImage: "clipboard", shortcut: "Cmd+V", enabled: documentController.hasSession) {
            documentController.commandBus.paste()
        }
        menuAction("모양 복사...", systemImage: "paintbrush.pointed", shortcut: "Opt+C", enabled: false) {
            showUnsupportedFeature("모양 복사")
        }
        Divider()
        menuAction("지우기", systemImage: "delete.left", shortcut: "Cmd+E", enabled: documentController.hasSession) {
            documentController.deleteBackward()
        }
        menuAction("조판 부호 지우기", systemImage: "eraser.line.dashed", enabled: false) {
            showUnsupportedFeature("조판 부호 지우기")
        }
        Divider()
        menuAction("모두 선택", systemImage: "selection.pin.in.out", shortcut: "Cmd+A", enabled: documentController.hasSession) {
            documentController.commandBus.selectAll()
        }
        Divider()
        Menu {
            menuAction("찾기...", systemImage: "magnifyingglass", shortcut: "Cmd+F", enabled: true) {
                openFindReplaceDialog()
            }
            menuAction("찾아 바꾸기...", systemImage: "character.cursor.ibeam", shortcut: "Cmd+Shift+H", enabled: true) {
                openFindReplaceDialog()
            }
            menuAction("찾아가기", systemImage: "arrowshape.turn.up.right", shortcut: "Opt+G", enabled: false) {
                showUnsupportedFeature("찾아가기")
            }
        } label: {
            menuRowLabel("찾기", systemImage: "magnifyingglass")
        }
    }

    @ViewBuilder
    var viewMenuContent: some View {
        Menu {
            zoomPresetButton("50%", value: 0.5)
            zoomPresetButton("75%", value: 0.75)
            zoomPresetButton("100%", value: 1.0)
            zoomPresetButton("125%", value: 1.25)
            zoomPresetButton("150%", value: 1.5)
            zoomPresetButton("200%", value: 2.0)
            zoomPresetButton("300%", value: 3.0)
            Divider()
            menuAction("쪽 맞춤", systemImage: "rectangle.compress.vertical", enabled: documentController.hasSession) {
                fitPage()
            }
            menuAction("폭 맞춤", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", enabled: documentController.hasSession) {
                fitWidth()
            }
        } label: {
            menuRowLabel("확대/축소", systemImage: "plus.magnifyingglass")
        }

        Menu {
            menuAction("한 쪽", enabled: false) { showUnsupportedFeature("한 쪽 보기") }
            menuAction("두 쪽", enabled: false) { showUnsupportedFeature("두 쪽 보기") }
            menuAction("세 쪽", enabled: false) { showUnsupportedFeature("세 쪽 보기") }
        } label: {
            menuRowLabel("쪽 모양", systemImage: "rectangle.on.rectangle")
        }

        menuAction("쪽 윤곽", systemImage: "doc", shortcut: "Ctrl+G+L", enabled: false) {
            showUnsupportedFeature("쪽 윤곽")
        }

        Menu {
            menuAction("조판 부호", systemImage: "paragraphsign", shortcut: "Ctrl+G+C", enabled: false) {
                showUnsupportedFeature("조판 부호")
            }
            menuAction("문단 부호", systemImage: "return", shortcut: "Ctrl+G+T", enabled: false) {
                showUnsupportedFeature("문단 부호")
            }
            menuAction("투명 선", systemImage: "line.diagonal", enabled: false) {
                showUnsupportedFeature("투명 선")
            }
        } label: {
            menuRowLabel("표시/숨기기")
        }

        menuAction("격자 보기", systemImage: "square.grid.3x3", enabled: false) {
            showUnsupportedFeature("격자 보기")
        }

        Menu {
            menuAction("기본", enabled: false) { showUnsupportedFeature("기본 도구 상자") }
            menuAction("서식", enabled: false) { showUnsupportedFeature("서식 도구 상자") }
        } label: {
            menuRowLabel("도구 상자", systemImage: "square.grid.2x2")
        }

        Menu {
            menuAction("눈금자", enabled: false) { showUnsupportedFeature("눈금자") }
        } label: {
            menuRowLabel("문서 창")
        }

        Menu {
            menuAction("모든 메모 표시", enabled: false) { showUnsupportedFeature("모든 메모 표시") }
            menuAction("메모 안내선 표시", enabled: false) { showUnsupportedFeature("메모 안내선 표시") }
        } label: {
            menuRowLabel("메모", systemImage: "text.bubble")
        }
    }

    @ViewBuilder
    var insertMenuContent: some View {
        Menu {
            menuAction("가로 글상자", enabled: false) { showUnsupportedFeature("가로 글상자") }
            menuAction("직사각형", enabled: false) { showUnsupportedFeature("직사각형") }
            menuAction("타원", enabled: false) { showUnsupportedFeature("타원") }
            menuAction("직선", enabled: false) { showUnsupportedFeature("직선") }
            menuAction("호", enabled: false) { showUnsupportedFeature("호") }
        } label: {
            menuRowLabel("도형", systemImage: "scribble.variable")
        }

        menuAction("그림...", systemImage: "photo", shortcut: "Ctrl+N+I", enabled: false) {
            showUnsupportedFeature("그림")
        }
        menuAction("표...", systemImage: "tablecells", enabled: documentController.hasSession) {
            documentController.createTable(rows: newTableRows, columns: newTableColumns)
        }
        menuAction("차트...", systemImage: "chart.bar", enabled: false) {
            showUnsupportedFeature("차트")
        }
        menuAction("글상자", systemImage: "textbox", shortcut: "Ctrl+N+B", enabled: false) {
            showUnsupportedFeature("글상자")
        }
        menuAction("웹 동영상...", systemImage: "play.rectangle", enabled: false) {
            showUnsupportedFeature("웹 동영상")
        }
        Divider()
        menuAction("수식...", systemImage: "function", enabled: false) {
            showUnsupportedFeature("수식")
        }
        Divider()
        menuAction("문자표...", systemImage: "character.book.closed", shortcut: "Cmd+F10", enabled: false) {
            showUnsupportedFeature("문자표")
        }
        Divider()
        menuAction("필드 입력...", systemImage: "tag", shortcut: "Ctrl+K+E", enabled: documentController.hasSession) {
            openDialog(.fields)
        }
        menuAction("문단 띠", systemImage: "minus.rectangle", shortcut: "Ctrl+N+L", enabled: false) {
            showUnsupportedFeature("문단 띠")
        }
        Divider()
        Menu {
            menuAction("각주", systemImage: "text.insert", enabled: documentController.hasSession) {
                documentController.insertFootnote()
            }
            menuAction("미주", systemImage: "note.text", enabled: false) { showUnsupportedFeature("미주") }
        } label: {
            menuRowLabel("주석")
        }
        Menu {
            menuAction("위", enabled: false) { showUnsupportedFeature("캡션") }
            menuAction("왼쪽 위", enabled: false) { showUnsupportedFeature("캡션") }
            menuAction("오른쪽 위", enabled: false) { showUnsupportedFeature("캡션") }
            menuAction("아래", enabled: false) { showUnsupportedFeature("캡션") }
            menuAction("캡션 없음", enabled: false) { showUnsupportedFeature("캡션") }
        } label: {
            menuRowLabel("캡션 넣기")
        }
        Divider()
        menuAction("메모", systemImage: "text.bubble", enabled: false) {
            showUnsupportedFeature("메모")
        }
        menuAction("하이퍼링크...", systemImage: "link", shortcut: "Ctrl+K+H", enabled: false) {
            showUnsupportedFeature("하이퍼링크")
        }
        menuAction("책갈피...", systemImage: "bookmark", shortcut: "Ctrl+K+B", enabled: documentController.hasSession) {
            openDialog(.bookmarks)
        }
    }

    @ViewBuilder
    var formatMenuContent: some View {
        menuAction("글자 모양...", systemImage: "character.cursor.ibeam", shortcut: "Cmd+L", enabled: documentController.hasSession) {
            openDialog(.charShape)
        }
        Divider()
        menuAction("문단 모양...", systemImage: "text.alignleft", shortcut: "Cmd+T", enabled: documentController.hasSession) {
            openDialog(.paraShape)
        }
        Divider()
        menuAction("글머리표 모양...", systemImage: "list.bullet", enabled: false) {
            showUnsupportedFeature("글머리표 모양")
        }
        menuAction("문단 번호 모양...", systemImage: "list.number", shortcut: "Ctrl+K+N", enabled: false) {
            showUnsupportedFeature("문단 번호 모양")
        }
        Divider()
        menuAction("한 수준 증가", systemImage: "increase.indent", shortcut: "Ctrl+Num -", enabled: false) {
            showUnsupportedFeature("한 수준 증가")
        }
        menuAction("한 수준 감소", systemImage: "decrease.indent", shortcut: "Ctrl+Num +", enabled: false) {
            showUnsupportedFeature("한 수준 감소")
        }
        Divider()
        menuAction("스타일...", systemImage: "text.badge.plus", shortcut: "F6", enabled: false) {
            showUnsupportedFeature("스타일")
        }
        Divider()
        menuAction("개체 속성...", systemImage: "slider.horizontal.3", shortcut: "P", enabled: false) {
            showUnsupportedFeature("개체 속성")
        }
    }

    @ViewBuilder
    var pageMenuContent: some View {
        menuAction("편집 용지...", systemImage: "doc.text.magnifyingglass", shortcut: "F7", enabled: documentController.hasSession) {
            openDialog(.pageSetup)
        }
        Divider()
        Menu {
            headerFooterTemplates(isHeader: true)
        } label: {
            menuRowLabel("머리말", systemImage: "rectangle.topthird.inset.filled")
        }
        Menu {
            headerFooterTemplates(isHeader: false)
        } label: {
            menuRowLabel("꼬리말", systemImage: "rectangle.bottomthird.inset.filled")
        }
        menuAction("새 번호로 시작...", systemImage: "number", enabled: false) {
            showUnsupportedFeature("새 번호로 시작")
        }
        menuAction("현재 쪽만 감추기...", systemImage: "eye.slash", shortcut: "Ctrl+N+S", enabled: false) {
            showUnsupportedFeature("현재 쪽만 감추기")
        }
        Divider()
        menuAction("쪽 나누기", systemImage: "rectangle.split.3x1", shortcut: "Ctrl+Return", enabled: documentController.hasSession) {
            documentController.insertPageBreak()
        }
        menuAction("단 나누기", systemImage: "square.split.2x1", shortcut: "Ctrl+Shift+Return", enabled: documentController.hasSession) {
            documentController.insertColumnBreak()
        }
        Divider()
        Menu {
            menuAction("하나", enabled: false) { showUnsupportedFeature("단") }
            menuAction("둘", enabled: false) { showUnsupportedFeature("단") }
            menuAction("셋", enabled: false) { showUnsupportedFeature("단") }
            menuAction("왼쪽", enabled: false) { showUnsupportedFeature("단") }
            menuAction("오른쪽", enabled: false) { showUnsupportedFeature("단") }
        } label: {
            menuRowLabel("단", systemImage: "rectangle.split.2x1")
        }
        menuAction("다단 설정 나누기", systemImage: "rectangle.3.group", shortcut: "Ctrl+Opt+Return", enabled: false) {
            showUnsupportedFeature("다단 설정 나누기")
        }
    }

    @ViewBuilder
    var tableMenuContent: some View {
        menuAction("표 만들기...", systemImage: "tablecells", shortcut: "Ctrl+N+T", enabled: documentController.hasSession) {
            documentController.createTable(rows: newTableRows, columns: newTableColumns)
        }
        menuAction("표/셀 속성...", systemImage: "rectangle.and.pencil.and.ellipsis", enabled: documentController.isEditingTable) {
            openDialog(.tableProperties)
        }
        Divider()
        Menu {
            menuAction("각 셀마다 적용...", enabled: false) { showUnsupportedFeature("셀 테두리/배경") }
            menuAction("하나의 셀처럼 적용...", enabled: false) { showUnsupportedFeature("셀 테두리/배경") }
        } label: {
            menuRowLabel("셀 테두리/배경")
        }
        Menu {
            menuAction("위쪽에 줄 추가하기", enabled: documentController.isEditingTable) {
                documentController.insertTableRow(after: false)
            }
            menuAction("아래쪽에 줄 추가하기", shortcut: "Ctrl+Return", enabled: documentController.isEditingTable) {
                documentController.insertTableRow(after: true)
            }
            Divider()
            menuAction("왼쪽에 칸 추가하기", shortcut: "Ctrl+I", enabled: documentController.isEditingTable) {
                documentController.insertTableColumn(after: false)
            }
            menuAction("오른쪽에 칸 추가하기", enabled: documentController.isEditingTable) {
                documentController.insertTableColumn(after: true)
            }
        } label: {
            menuRowLabel("줄/칸 추가하기")
        }
        Menu {
            menuAction("줄 지우기", shortcut: "Ctrl+Delete", enabled: documentController.isEditingTable) {
                documentController.deleteCurrentTableRow()
            }
            Divider()
            menuAction("칸 지우기", shortcut: "Ctrl+D", enabled: documentController.isEditingTable) {
                documentController.deleteCurrentTableColumn()
            }
        } label: {
            menuRowLabel("줄/칸 지우기")
        }
        Divider()
        menuAction("셀 나누기...", systemImage: "square.split.2x2", shortcut: "S", enabled: documentController.isEditingTable) {
            documentController.splitCurrentTableCell()
        }
        menuAction("셀 합치기", systemImage: "square.grid.2x2", shortcut: "M", enabled: documentController.isEditingTable) {
            openDialog(.mergeCells)
        }
        menuAction("셀 높이를 같게", systemImage: "arrow.up.and.down", shortcut: "H", enabled: false) {
            showUnsupportedFeature("셀 높이를 같게")
        }
        menuAction("셀 너비를 같게", systemImage: "arrow.left.and.right", shortcut: "W", enabled: false) {
            showUnsupportedFeature("셀 너비를 같게")
        }
    }

    @ViewBuilder
    var reviewMenuContent: some View {
        Menu {
            menuAction("변경 내용 추적", enabled: false) { showUnsupportedFeature("변경 내용 추적") }
            Divider()
            menuAction("적용 후 다음으로 이동", enabled: false) { showUnsupportedFeature("변경 내용 추적") }
            menuAction("취소 후 다음으로 이동", enabled: false) { showUnsupportedFeature("변경 내용 추적") }
            menuAction("다음", enabled: false) { showUnsupportedFeature("변경 내용 추적") }
            menuAction("이전", enabled: false) { showUnsupportedFeature("변경 내용 추적") }
            Divider()
            Menu {
                menuAction("삽입 및 삭제", enabled: false) { showUnsupportedFeature("변경 내용 보기") }
                menuAction("서식", enabled: false) { showUnsupportedFeature("변경 내용 보기") }
            } label: {
                menuRowLabel("변경 내용 보기")
            }
            Divider()
            menuAction("최종본 및 변경 내용", enabled: false) { showUnsupportedFeature("최종본 및 변경 내용") }
            menuAction("최종본", enabled: false) { showUnsupportedFeature("최종본") }
        } label: {
            menuRowLabel("변경 내용 추적", systemImage: "text.redaction")
        }
    }

    @ViewBuilder
    var toolsMenuContent: some View {
        Menu {
            menuAction("'곧은 따옴표'를 '둥근 따옴표'로 자동 바꾸기", enabled: false) {
                showUnsupportedFeature("빠른 교정")
            }
        } label: {
            menuRowLabel("빠른 교정", systemImage: "wand.and.stars")
        }
        Menu {
            menuAction("스크린 리더 지원 사용", shortcut: "Ctrl+Opt+F1", enabled: false) {
                showUnsupportedFeature("접근성 설정")
            }
        } label: {
            menuRowLabel("접근성 설정", systemImage: "figure.wave")
        }
        menuAction("채팅", systemImage: "message", enabled: false) {
            showUnsupportedFeature("채팅")
        }
    }

    @ViewBuilder
    var findMenuContent: some View {
        menuAction("찾기...", systemImage: "magnifyingglass", shortcut: "Cmd+F", enabled: true) {
            openFindReplaceDialog()
        }
        menuAction("찾아 바꾸기...", systemImage: "character.cursor.ibeam", shortcut: "Cmd+Shift+H", enabled: true) {
            openFindReplaceDialog()
        }
        menuAction("찾아가기", systemImage: "arrow.turn.down.right", shortcut: "Opt+G", enabled: false) {
            showUnsupportedFeature("찾아가기")
        }
    }

    @ViewBuilder
    var insertShapeMenuContent: some View {
        menuAction("가로 글상자", enabled: false) { showUnsupportedFeature("가로 글상자") }
        menuAction("직사각형", enabled: false) { showUnsupportedFeature("직사각형") }
        menuAction("타원", enabled: false) { showUnsupportedFeature("타원") }
        menuAction("직선", enabled: false) { showUnsupportedFeature("직선") }
        menuAction("호", enabled: false) { showUnsupportedFeature("호") }
    }

    @ViewBuilder
    var tableQuickMenuContent: some View {
        TableInsertPopover(
            rows: $newTableRows,
            columns: $newTableColumns,
            onInsert: { rows, columns in
                activePopover = nil
                documentController.createTable(rows: rows, columns: columns)
            },
            onAdvanced: {
                activePopover = nil
                documentController.createTable(rows: newTableRows, columns: newTableColumns)
            }
        )
        .disabled(!documentController.hasSession)
        .opacity(documentController.hasSession ? 1 : 0.35)
        Divider()
        menuAction("현재 설정 표 삽입", enabled: documentController.hasSession) {
            documentController.createTable(rows: newTableRows, columns: newTableColumns)
        }
        menuAction("표 만들기...", systemImage: "tablecells", enabled: documentController.hasSession) {
            documentController.createTable(rows: newTableRows, columns: newTableColumns)
        }
    }

    @ViewBuilder
    var chartMenuContent: some View {
        ForEach([
            "세로 막대형",
            "누적 세로 막대형",
            "꺾은선형",
            "가로 막대형",
            "원형",
            "도넛형",
            "영역형",
            "방사형",
        ], id: \.self) { title in
            menuAction(title) {
                showUnsupportedFeature(title)
            }
        }
    }

    @ViewBuilder
    func headerFooterMenuContent(isHeader: Bool) -> some View {
        headerFooterTemplates(isHeader: isHeader)
    }

    @ViewBuilder
    func headerFooterTemplates(isHeader: Bool) -> some View {
        let title = isHeader ? "머리말" : "꼬리말"

        menuAction("(모양 없음)", enabled: documentController.hasSession) {
            documentController.applyHeaderFooterTemplate(isHeader: isHeader, templateID: 0)
        }
        menuAction("왼쪽 쪽 번호", enabled: documentController.hasSession) {
            documentController.applyHeaderFooterTemplate(isHeader: isHeader, templateID: 1)
        }
        menuAction("가운데 쪽 번호", enabled: documentController.hasSession) {
            documentController.applyHeaderFooterTemplate(isHeader: isHeader, templateID: 2)
        }
        menuAction("오른쪽 쪽 번호", enabled: documentController.hasSession) {
            documentController.applyHeaderFooterTemplate(isHeader: isHeader, templateID: 3)
        }
        Divider()
        menuAction("\(title) 설정...", systemImage: "slider.horizontal.3", enabled: documentController.hasSession) {
            openDialog(isHeader ? .headerSetup : .footerSetup)
        }
        Divider()
        Text("\(title) 템플릿은 현재 구역 기준으로 적용됩니다.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    var bulletListMenuContent: some View {
        menuAction("없음") {
            documentController.clearParagraphList()
        }
        Divider()
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 4), spacing: 6) {
            ForEach(["•", "◦", "▪", "–", "✓", "◆", "★", "○", "●", "□", "■", "◇"], id: \.self) { bullet in
                Button {
                    activePopover = nil
                    documentController.applyBulletList(bulletCharacter: bullet)
                } label: {
                    Text(bullet)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .underPageBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    var numberingListMenuContent: some View {
        menuAction("없음") {
            documentController.clearParagraphList()
        }
        Divider()
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 2), spacing: 6) {
            ForEach(["1.", "1)", "(1)", "가.", "가)", "I.", "A.", "i."], id: \.self) { format in
                Button {
                    activePopover = nil
                    documentController.applyNumberingList()
                    documentController.statusMessage = "\(format) 번호 형식 적용 경로를 연결했습니다."
                } label: {
                    Text(format)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 48, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .underPageBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    var textColorMenuContent: some View {
        ForEach(colorPresets, id: \.hex) { preset in
            Button {
                activePopover = nil
                documentController.setTextColor(preset.hex)
            } label: {
                colorMenuLabel(name: preset.name, color: Color(nsColor: NSColor(cssHex: preset.hex)))
            }
            .buttonStyle(ToolbarMenuRowButtonStyle())
        }
    }

    @ViewBuilder
    var highlightColorMenuContent: some View {
        Button("없음") {
            activePopover = nil
            documentController.clearHighlightColor()
        }
        .buttonStyle(ToolbarMenuRowButtonStyle())
        Divider()
        ForEach(highlightPresets, id: \.hex) { preset in
            Button {
                activePopover = nil
                documentController.setHighlightColor(preset.hex)
            } label: {
                colorMenuLabel(name: preset.name, color: Color(nsColor: NSColor(cssHex: preset.hex)))
            }
            .buttonStyle(ToolbarMenuRowButtonStyle())
        }
    }

    func fitWidth() {
        guard let page = documentController.pageInfos.first else { return }
        let availableWidth = max(viewportController.viewportSize.width - viewportController.pageInset * 2, 320)
        let zoom = availableWidth / max(CGFloat(page.width), 1)
        documentController.setZoom(zoom)
    }

    func fitPage() {
        guard let page = documentController.pageInfos.first else { return }
        let availableWidth = max(viewportController.viewportSize.width - viewportController.pageInset * 2, 320)
        let availableHeight = max(viewportController.viewportSize.height - viewportController.pageInset * 2, 320)
        let zoomWidth = availableWidth / max(CGFloat(page.width), 1)
        let zoomHeight = availableHeight / max(CGFloat(page.height), 1)
        documentController.setZoom(min(zoomWidth, zoomHeight))
    }

    func zoomPresetButton(_ label: String, value: CGFloat) -> some View {
        menuAction(label, enabled: documentController.hasSession) {
            documentController.setZoom(value)
        }
    }

    func syncTitleDraft() {
        draftDisplayName = documentController.displayName
    }

    func commitDisplayName() {
        documentController.renameDisplayName(draftDisplayName)
        syncTitleDraft()
    }

    func showShortcutGuide() {
        documentController.statusMessage = "단축키는 메뉴 항목 옆 표시를 참고하세요."
    }

    func openFindReplaceDialog() {
        activePopover = nil
        isFindReplacePresented = true
    }

    func openDialog(_ dialog: EditorDialogState) {
        activePopover = nil
        activeDialog = dialog
    }

    func showDocumentInfo() {
        guard let info = documentController.documentInfo else {
            documentController.statusMessage = "문서 정보가 없습니다."
            return
        }
        documentController.statusMessage = "문서 정보: \(info.pageCount)쪽, 섹션 \(info.sectionCount), 버전 \(info.version)"
    }

    func showUnsupportedFeature(_ name: String) {
        documentController.statusMessage = "\(name) UI는 구조만 먼저 맞췄고, 동작 연결은 다음 단계입니다."
    }

    func popoverBinding(for popover: ToolbarPopover) -> Binding<Bool> {
        Binding(
            get: { activePopover == popover },
            set: { isPresented in
                if isPresented {
                    activePopover = popover
                } else if activePopover == popover {
                    activePopover = nil
                }
            }
        )
    }

    func togglePopover(_ popover: ToolbarPopover) {
        activePopover = activePopover == popover ? nil : popover
    }

    func activatePopoverOnHover(_ popover: ToolbarPopover) {
        guard let activePopover, activePopover.isTitleMenu, activePopover != popover else { return }
        self.activePopover = popover
    }

    func toolbarPopoverPanel<Content: View>(_ popover: ToolbarPopover, @ViewBuilder content: () -> Content) -> some View {
        ToolbarPopoverPanel(width: popover.width, maxHeight: popover.maxHeight) {
            content()
        }
    }

    func toolbarMenu<Content: View>(_ title: String, popover: ToolbarPopover, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button {
            togglePopover(popover)
        } label: {
            ToolbarTabLabel(title: title, isActive: activePopover == popover)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                activatePopoverOnHover(popover)
            }
        }
        .popover(
            isPresented: popoverBinding(for: popover),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            toolbarPopoverPanel(popover) {
                content()
            }
        }
    }

    func statusCapsule(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.11))
            )
    }

    func utilityIconButton(_ systemImage: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.35), lineWidth: 1)
        }
        .opacity(enabled ? 1 : 0.38)
        .disabled(!enabled)
    }

    func ribbonGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4, content: content)
    }

    func ribbonToolbarButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RibbonButtonLabel(
                title: title,
                systemImage: systemImage,
                showsMenuIndicator: false,
                isActive: false
            )
        }
        .buttonStyle(RibbonToolbarButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    func ribbonMenuButton<Content: View>(
        _ title: String,
        systemImage: String,
        popover: ToolbarPopover,
        isEnabled: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Button {
            togglePopover(popover)
        } label: {
            RibbonButtonLabel(
                title: title,
                systemImage: systemImage,
                showsMenuIndicator: true,
                isActive: activePopover == popover
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .popover(
            isPresented: popoverBinding(for: popover),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            toolbarPopoverPanel(popover) {
                content()
            }
        }
    }

    func compactToolbarButton(
        _ systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.clear)
        )
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    func comboMenuField<Content: View>(
        _ value: String,
        width: CGFloat,
        leading: AnyView? = nil,
        popover: ToolbarPopover,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Button {
            togglePopover(popover)
        } label: {
            dropdownFieldView(value, width: width, leading: leading)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: popoverBinding(for: popover),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            toolbarPopoverPanel(popover) {
                content()
            }
        }
    }

    func dropdownFieldView(_ value: String, width: CGFloat, leading: AnyView? = nil) -> some View {
        HStack(spacing: 6) {
            if let leading {
                leading
            }

            Text(value)
                .font(.system(size: 12))
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: NSColor.textBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    func metricComboField(
        value: String,
        unit: String,
        width: CGFloat,
        popover: ToolbarPopover,
        isEnabled: Bool,
        presetValues: [String],
        applyValue: @escaping (String) -> Void,
        decrementAction: @escaping () -> Void,
        incrementAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                togglePopover(popover)
            } label: {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: width + 24, height: 28)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 28)

            VStack(spacing: 0) {
                arrowButton("chevron.up", enabled: isEnabled, action: incrementAction)
                Divider()
                arrowButton("chevron.down", enabled: isEnabled, action: decrementAction)
            }
            .frame(width: 16, height: 28)
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: NSColor.textBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color(nsColor: NSColor.separatorColor).opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .opacity(isEnabled ? 1 : 0.45)
        .popover(
            isPresented: popoverBinding(for: popover),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            toolbarPopoverPanel(popover) {
                ForEach(presetValues, id: \.self) { preset in
                    menuAction("\(preset) \(unit)") {
                        applyValue(preset)
                    }
                }
            }
        }
    }

    func arrowButton(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    func textFormatButton(
        kind: TextFormatKind,
        isActive: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            kind.label
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(kind.help)
    }

    func lineStyleMenuButton(
        kind: TextFormatKind,
        popover: ToolbarPopover,
        isActive: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            togglePopover(popover)
        } label: {
            HStack(spacing: 3) {
                kind.label
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .popover(
            isPresented: popoverBinding(for: popover),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            toolbarPopoverPanel(popover) {
                menuAction("실선", enabled: isEnabled, action: action)
                menuAction("파선", enabled: false) { showUnsupportedFeature(kind.help) }
                menuAction("점선", enabled: false) { showUnsupportedFeature(kind.help) }
            }
        }
    }

    func colorGlyphButton(text: String? = nil, icon: String? = nil, color: Color, isEnabled: Bool) -> some View {
        HStack(spacing: 4) {
            if let text {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
            }

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
            }

            Rectangle()
                .fill(color)
                .frame(width: 13, height: 3)
                .clipShape(Capsule(style: .continuous))

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 38, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.clear)
        )
        .opacity(isEnabled ? 1 : 0.35)
    }

    func colorMenuLabel(name: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
        }
    }

    var lineSpacingGlyph: some View {
        Image(systemName: "arrow.up.and.down.text.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 14, height: 14)
    }

    func alignmentButton(
        style: ParagraphAlignStyle,
        isActive: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ParagraphAlignGlyph(style: style)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(style.help)
    }

    func listMenuButton<Content: View>(
        systemImage: String,
        popover: ToolbarPopover,
        isEnabled: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Button {
            togglePopover(popover)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .popover(
            isPresented: popoverBinding(for: popover),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            toolbarPopoverPanel(popover) {
                content()
            }
        }
    }

    func menuAction(
        _ title: String,
        systemImage: String? = nil,
        shortcut: String? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if enabled {
                activePopover = nil
            }
            action()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16, height: 16)

                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 24)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(ToolbarMenuRowButtonStyle())
        .disabled(!enabled)
    }

    func menuRowLabel(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 12) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)

            Text(title)
            Spacer(minLength: 18)
        }
    }

    func fontMenuRow(sample: FontMenuSample, isSelected: Bool) -> some View {
        HStack(spacing: 16) {
            Text(sample.displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .frame(width: 128, alignment: .leading)

            Text(sample.previewText)
                .font(.custom(sample.familyName, size: 13))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private extension EditorToolbar {
    var colorPresets: [(name: String, hex: String)] {
        [
            ("검정", "#000000"),
            ("진회색", "#4a4a4a"),
            ("파랑", "#1f5bd8"),
            ("빨강", "#d12f19"),
            ("초록", "#2f7d32"),
            ("보라", "#7b3fc7"),
            ("주황", "#f28c28"),
        ]
    }

    var highlightPresets: [(name: String, hex: String)] {
        [
            ("노랑", "#fff59d"),
            ("연두", "#c5e1a5"),
            ("하늘", "#b3e5fc"),
            ("분홍", "#f8bbd0"),
            ("주황", "#ffcc80"),
        ]
    }
}

private enum ToolbarPopover: Hashable {
    case help
    case file
    case edit
    case view
    case insert
    case format
    case page
    case table
    case review
    case tools
    case ribbonFind
    case ribbonInsertShape
    case ribbonTable
    case ribbonChart
    case ribbonHeader
    case ribbonFooter
    case styleName
    case fontLanguage
    case fontName
    case fontSize
    case underline
    case strikethrough
    case textColor
    case highlight
    case lineSpacing
    case bulletList
    case numberingList

    var isTitleMenu: Bool {
        switch self {
        case .file, .edit, .view, .insert, .format, .page, .table, .review, .tools:
            return true
        default:
            return false
        }
    }

    var width: CGFloat {
        switch self {
        case .help:
            return 180
        case .fontName:
            return 348
        case .bulletList, .numberingList:
            return 180
        case .ribbonChart:
            return 260
        default:
            return 270
        }
    }

    var maxHeight: CGFloat? {
        switch self {
        case .fontName:
            return 360
        default:
            return nil
        }
    }
}

private struct ToolbarPopoverPanel<Content: View>: View {
    let width: CGFloat
    let maxHeight: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(showsIndicators: maxHeight != nil) {
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .padding(.leading, 14)
            .padding(.trailing, 12)
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ToolbarMenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

private struct FontMenuSample: Hashable {
    let displayName: String
    let familyName: String
    let previewText: String

    init(displayName: String, familyName: String, previewText: String = "가나다 ABC 123") {
        self.displayName = displayName
        self.familyName = familyName
        self.previewText = previewText
    }
}

private struct ToolbarTabLabel: View {
    let title: String
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((isActive || isHovered) ? Color.accentColor.opacity(isActive ? 0.16 : 0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct RibbonButtonLabel: View {
    let title: String
    let systemImage: String
    let showsMenuIndicator: Bool
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 22, height: 22)

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .frame(minHeight: 24)

            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .frame(width: 56, height: 70)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
        )
    }
}

private struct RibbonToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.12) : Color.clear)
            )
    }
}

private struct VerticalHairline: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: NSColor.separatorColor).opacity(0.75))
            .frame(width: 1, height: height)
    }
}

private struct HwpBrandBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor.controlAccentColor),
                                Color(nsColor: NSColor.controlAccentColor).opacity(0.78),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("H")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)

            Text("한글")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

private enum TextFormatKind: Equatable {
    case bold
    case italic
    case underline
    case strike

    var help: String {
        switch self {
        case .bold:
            return "진하게"
        case .italic:
            return "기울임"
        case .underline:
            return "밑줄"
        case .strike:
            return "취소선"
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .bold:
            Text("가")
                .font(.system(size: 15, weight: .bold))
        case .italic:
            Text("가")
                .font(.system(size: 15, weight: .medium))
                .italic()
        case .underline:
            Text("간")
                .font(.system(size: 13, weight: .medium))
                .underline()
        case .strike:
            Text("가")
                .font(.system(size: 13, weight: .medium))
                .strikethrough()
        }
    }
}

private enum ParagraphAlignStyle {
    case left
    case center
    case right
    case justify
    case distribute
    case split

    var help: String {
        switch self {
        case .left:
            return "왼쪽 정렬"
        case .center:
            return "가운데 정렬"
        case .right:
            return "오른쪽 정렬"
        case .justify:
            return "양쪽 정렬"
        case .distribute:
            return "배분 정렬"
        case .split:
            return "나눔 정렬"
        }
    }
}

private struct ParagraphAlignGlyph: View {
    let style: ParagraphAlignStyle

    var body: some View {
        VStack(spacing: 2) {
            line(width: 14, alignment: .leading)
            line(width: secondWidth, alignment: secondAlignment)
            line(width: 14, alignment: .leading)
            lastLine
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
    }

    private var secondWidth: CGFloat {
        switch style {
        case .left:
            return 9
        case .center:
            return 10
        case .right:
            return 9
        case .justify, .distribute, .split:
            return 14
        }
    }

    private var secondAlignment: Alignment {
        switch style {
        case .left, .justify, .distribute, .split:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }

    @ViewBuilder
    private var lastLine: some View {
        switch style {
        case .distribute:
            HStack(spacing: 2.5) {
                Capsule().fill(Color.primary.opacity(0.85)).frame(width: 3.3, height: 1.6)
                Capsule().fill(Color.primary.opacity(0.85)).frame(width: 3.3, height: 1.6)
                Capsule().fill(Color.primary.opacity(0.85)).frame(width: 3.3, height: 1.6)
            }
            .frame(width: 14, alignment: .leading)
        case .split:
            HStack(spacing: 2) {
                Capsule().fill(Color.primary.opacity(0.85)).frame(width: 6, height: 1.6)
                Capsule().fill(Color.primary.opacity(0.85)).frame(width: 6, height: 1.6)
            }
            .frame(width: 14, alignment: .leading)
        case .left:
            line(width: 7, alignment: .leading)
        case .center:
            line(width: 8, alignment: .center)
        case .right:
            line(width: 7, alignment: .trailing)
        case .justify:
            line(width: 9, alignment: .leading)
        }
    }

    private func line(width: CGFloat, alignment: Alignment) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.85))
            .frame(width: width, height: 1.6)
            .frame(width: 14, alignment: alignment)
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 || hex.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        let red, green, blue, alpha: CGFloat
        if hex.count == 8 {
            red = CGFloat((value & 0xFF000000) >> 24) / 255
            green = CGFloat((value & 0x00FF0000) >> 16) / 255
            blue = CGFloat((value & 0x0000FF00) >> 8) / 255
            alpha = CGFloat(value & 0x000000FF) / 255
        } else {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
