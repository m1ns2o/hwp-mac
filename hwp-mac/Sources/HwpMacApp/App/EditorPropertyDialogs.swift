import SwiftUI

@MainActor
struct CharShapeDialogView: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var fontFamily: String
    @State private var fontSize: String
    @State private var bold: Bool
    @State private var italic: Bool
    @State private var underline: Bool
    @State private var strikethrough: Bool
    @State private var textColor: String
    @State private var shadeColor: String
    @State private var superscript: Bool
    @State private var subscriptEnabled: Bool
    @State private var outlineType: Int
    @State private var shadowType: Int

    init(documentController: DocumentController, isPresented: Binding<Bool>) {
        self.documentController = documentController
        self._isPresented = isPresented
        let props = documentController.charProperties
        _fontFamily = State(initialValue: props?.fontFamily ?? "맑은 고딕")
        _fontSize = State(initialValue: String(format: "%.1f", props?.fontSize ?? 12))
        _bold = State(initialValue: props?.bold ?? false)
        _italic = State(initialValue: props?.italic ?? false)
        _underline = State(initialValue: props?.underline ?? false)
        _strikethrough = State(initialValue: props?.strikethrough ?? false)
        _textColor = State(initialValue: props?.textColor ?? "#000000")
        _shadeColor = State(initialValue: props?.shadeColor ?? "#ffffff")
        _superscript = State(initialValue: props?.superscript ?? false)
        _subscriptEnabled = State(initialValue: props?.subscriptEnabled ?? false)
        _outlineType = State(initialValue: props?.outlineType ?? 0)
        _shadowType = State(initialValue: props?.shadowType ?? 0)
    }

    var body: some View {
        EditorDialogBackdrop(isPresented: $isPresented) {
            EditorDialogContainer(title: "글자 모양", width: 620, isPresented: $isPresented) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        dialogField("글꼴") {
                            TextField("", text: $fontFamily)
                                .textFieldStyle(.roundedBorder)
                        }
                        dialogField("기준 크기") {
                            TextField("", text: $fontSize)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("pt")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        dialogField("속성") {
                            Toggle("굵게", isOn: $bold)
                            Toggle("기울임", isOn: $italic)
                            Toggle("밑줄", isOn: $underline)
                            Toggle("취소선", isOn: $strikethrough)
                            Toggle("위 첨자", isOn: $superscript)
                            Toggle("아래 첨자", isOn: $subscriptEnabled)
                        }
                        dialogField("색") {
                            TextField("#000000", text: $textColor)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            TextField("#ffffff", text: $shadeColor)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        dialogField("확장") {
                            Stepper("외곽선: \(outlineType)", value: $outlineType, in: 0...7)
                            Stepper("그림자: \(shadowType)", value: $shadowType, in: 0...2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("미리보기")
                            .font(.system(size: 12, weight: .semibold))
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                            .frame(width: 220, height: 150)
                            .overlay {
                                Text("한글 Eng 123 漢字")
                                    .font(.system(size: CGFloat(Double(fontSize) ?? 12), weight: bold ? .bold : .regular))
                                    .italic(italic)
                                    .underline(underline)
                                    .strikethrough(strikethrough)
                                    .foregroundStyle(Color(nsColor: NSColor(cssHex: textColor)))
                            }
                    }
                }
            } actions: {
                Button("취소") { isPresented = false }
                Button("설정") {
                    var mods: [String: Any] = [
                        "bold": bold,
                        "italic": italic,
                        "underline": underline,
                        "underlineType": underline ? "Bottom" : "None",
                        "strikethrough": strikethrough,
                        "textColor": textColor,
                        "shadeColor": shadeColor,
                        "superscript": superscript,
                        "subscript": subscriptEnabled,
                        "outlineType": outlineType,
                        "shadowType": shadowType,
                    ]
                    if let value = Double(fontSize) {
                        mods["fontSize"] = value
                    }
                    documentController.setFontFamily(fontFamily)
                    documentController.applyCharacterProperties(mods)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@MainActor
struct ParaShapeDialogView: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var alignment: String
    @State private var lineSpacing: String
    @State private var lineSpacingType: String
    @State private var marginLeft: String
    @State private var marginRight: String
    @State private var indent: String
    @State private var spacingBefore: String
    @State private var spacingAfter: String
    @State private var headType: String
    @State private var paraLevel: Int
    @State private var pageBreakBefore: Bool
    @State private var keepWithNext: Bool
    @State private var keepLines: Bool

    init(documentController: DocumentController, isPresented: Binding<Bool>) {
        self.documentController = documentController
        self._isPresented = isPresented
        let props = documentController.paraProperties
        _alignment = State(initialValue: props?.alignment ?? "justify")
        _lineSpacing = State(initialValue: String(Int((props?.lineSpacing ?? 160).rounded())))
        _lineSpacingType = State(initialValue: props?.lineSpacingType ?? "Percent")
        _marginLeft = State(initialValue: formatDecimal(props?.marginLeft))
        _marginRight = State(initialValue: formatDecimal(props?.marginRight))
        _indent = State(initialValue: formatDecimal(props?.indent))
        _spacingBefore = State(initialValue: formatDecimal(props?.spacingBefore))
        _spacingAfter = State(initialValue: formatDecimal(props?.spacingAfter))
        _headType = State(initialValue: props?.headType ?? "None")
        _paraLevel = State(initialValue: props?.paraLevel ?? 0)
        _pageBreakBefore = State(initialValue: props?.pageBreakBefore ?? false)
        _keepWithNext = State(initialValue: props?.keepWithNext ?? false)
        _keepLines = State(initialValue: props?.keepLines ?? false)
    }

    var body: some View {
        EditorDialogBackdrop(isPresented: $isPresented) {
            EditorDialogContainer(title: "문단 모양", width: 680, isPresented: $isPresented) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        dialogField("정렬") {
                            Picker("", selection: $alignment) {
                                Text("양쪽").tag("justify")
                                Text("왼쪽").tag("left")
                                Text("오른쪽").tag("right")
                                Text("가운데").tag("center")
                                Text("배분").tag("distribute")
                            }
                            .pickerStyle(.segmented)
                        }
                        dialogField("줄 간격") {
                            Picker("", selection: $lineSpacingType) {
                                Text("Percent").tag("Percent")
                                Text("Fixed").tag("Fixed")
                                Text("Minimum").tag("Minimum")
                            }
                            .frame(width: 120)
                            TextField("", text: $lineSpacing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                        }
                        dialogField("여백/들여쓰기") {
                            EditorLabeledValueField(title: "왼쪽", text: $marginLeft)
                            EditorLabeledValueField(title: "오른쪽", text: $marginRight)
                            EditorLabeledValueField(title: "들여쓰기", text: $indent)
                        }
                        dialogField("간격") {
                            EditorLabeledValueField(title: "문단 위", text: $spacingBefore)
                            EditorLabeledValueField(title: "문단 아래", text: $spacingAfter)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        dialogField("확장") {
                            Picker("머리 모양", selection: $headType) {
                                Text("없음").tag("None")
                                Text("글머리표").tag("Bullet")
                                Text("문단 번호").tag("Number")
                                Text("개요").tag("Outline")
                            }
                            .frame(width: 140)
                            Stepper("수준: \(paraLevel)", value: $paraLevel, in: 0...6)
                        }
                        dialogField("옵션") {
                            Toggle("현재 문단 앞에서 쪽 나누기", isOn: $pageBreakBefore)
                            Toggle("다음 문단과 함께", isOn: $keepWithNext)
                            Toggle("문단 보호", isOn: $keepLines)
                        }
                    }
                }
            } actions: {
                Button("취소") { isPresented = false }
                Button("설정") {
                    var mods: [String: Any] = [
                        "alignment": alignment,
                        "lineSpacingType": lineSpacingType,
                        "headType": headType,
                        "paraLevel": paraLevel,
                        "pageBreakBefore": pageBreakBefore,
                        "keepWithNext": keepWithNext,
                        "keepLines": keepLines,
                    ]
                    if let value = Int(lineSpacing) { mods["lineSpacing"] = value }
                    if let value = Int(marginLeft) { mods["marginLeft"] = value }
                    if let value = Int(marginRight) { mods["marginRight"] = value }
                    if let value = Int(indent) { mods["indent"] = value }
                    if let value = Int(spacingBefore) { mods["spacingBefore"] = value }
                    if let value = Int(spacingAfter) { mods["spacingAfter"] = value }
                    documentController.applyParagraphProperties(mods)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@MainActor
struct TablePropertiesDialogView: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var tableWidth: String
    @State private var tableHeight: String
    @State private var cellSpacing: String
    @State private var repeatHeader: Bool
    @State private var pageBreak: Int
    @State private var cellWidth: String
    @State private var cellHeight: String
    @State private var cellPaddingLeft: String
    @State private var cellPaddingRight: String
    @State private var cellPaddingTop: String
    @State private var cellPaddingBottom: String
    @State private var cellHeader: Bool
    @State private var cellProtect: Bool
    @State private var verticalAlign: Int

    init(documentController: DocumentController, isPresented: Binding<Bool>) {
        self.documentController = documentController
        self._isPresented = isPresented
        let table = documentController.currentTableProperties
        let cell = documentController.currentCellProperties
        _tableWidth = State(initialValue: String(table?.tableWidth ?? 0))
        _tableHeight = State(initialValue: String(table?.tableHeight ?? 0))
        _cellSpacing = State(initialValue: String(table?.cellSpacing ?? 0))
        _repeatHeader = State(initialValue: table?.repeatHeader ?? false)
        _pageBreak = State(initialValue: table?.pageBreak ?? 0)
        _cellWidth = State(initialValue: String(cell?.width ?? 0))
        _cellHeight = State(initialValue: String(cell?.height ?? 0))
        _cellPaddingLeft = State(initialValue: String(cell?.paddingLeft ?? 0))
        _cellPaddingRight = State(initialValue: String(cell?.paddingRight ?? 0))
        _cellPaddingTop = State(initialValue: String(cell?.paddingTop ?? 0))
        _cellPaddingBottom = State(initialValue: String(cell?.paddingBottom ?? 0))
        _cellHeader = State(initialValue: cell?.isHeader ?? false)
        _cellProtect = State(initialValue: cell?.cellProtect ?? false)
        _verticalAlign = State(initialValue: cell?.verticalAlign ?? 0)
    }

    var body: some View {
        EditorDialogBackdrop(isPresented: $isPresented) {
            EditorDialogContainer(title: "표/셀 속성", width: 700, isPresented: $isPresented) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("표")
                            .font(.system(size: 13, weight: .semibold))
                        dialogField("크기") {
                            EditorLabeledValueField(title: "너비", text: $tableWidth)
                            EditorLabeledValueField(title: "높이", text: $tableHeight)
                        }
                        dialogField("표 옵션") {
                            EditorLabeledValueField(title: "셀 간격", text: $cellSpacing)
                            Picker("쪽 나누기", selection: $pageBreak) {
                                Text("없음").tag(0)
                                Text("셀 단위").tag(1)
                                Text("행 단위").tag(2)
                            }
                            .frame(width: 180)
                            Toggle("첫 행 반복", isOn: $repeatHeader)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("셀")
                            .font(.system(size: 13, weight: .semibold))
                        dialogField("크기") {
                            EditorLabeledValueField(title: "너비", text: $cellWidth)
                            EditorLabeledValueField(title: "높이", text: $cellHeight)
                        }
                        dialogField("안 여백") {
                            EditorLabeledValueField(title: "왼쪽", text: $cellPaddingLeft)
                            EditorLabeledValueField(title: "오른쪽", text: $cellPaddingRight)
                            EditorLabeledValueField(title: "위쪽", text: $cellPaddingTop)
                            EditorLabeledValueField(title: "아래쪽", text: $cellPaddingBottom)
                        }
                        dialogField("속성") {
                            Picker("세로 정렬", selection: $verticalAlign) {
                                Text("위").tag(0)
                                Text("가운데").tag(1)
                                Text("아래").tag(2)
                            }
                            .frame(width: 180)
                            Toggle("머리 셀", isOn: $cellHeader)
                            Toggle("셀 보호", isOn: $cellProtect)
                        }
                    }
                }
            } actions: {
                Button("취소") { isPresented = false }
                Button("설정") {
                    documentController.updateCurrentTableProperties([
                        "tableWidth": Int(tableWidth) ?? 0,
                        "tableHeight": Int(tableHeight) ?? 0,
                        "cellSpacing": Int(cellSpacing) ?? 0,
                        "repeatHeader": repeatHeader,
                        "pageBreak": pageBreak,
                    ])
                    documentController.updateCurrentCellProperties([
                        "width": Int(cellWidth) ?? 0,
                        "height": Int(cellHeight) ?? 0,
                        "paddingLeft": Int(cellPaddingLeft) ?? 0,
                        "paddingRight": Int(cellPaddingRight) ?? 0,
                        "paddingTop": Int(cellPaddingTop) ?? 0,
                        "paddingBottom": Int(cellPaddingBottom) ?? 0,
                        "verticalAlign": verticalAlign,
                        "isHeader": cellHeader,
                        "cellProtect": cellProtect,
                    ])
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@MainActor
struct MergeCellsDialogView: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var endRow: Int
    @State private var endColumn: Int

    init(documentController: DocumentController, isPresented: Binding<Bool>) {
        self.documentController = documentController
        self._isPresented = isPresented
        let row = documentController.currentCellInfo?.row ?? 0
        let col = documentController.currentCellInfo?.col ?? 0
        _endRow = State(initialValue: row)
        _endColumn = State(initialValue: col)
    }

    var body: some View {
        EditorDialogBackdrop(isPresented: $isPresented) {
            EditorDialogContainer(title: "셀 합치기", width: 360, isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("현재 셀을 기준으로 합칠 마지막 행과 열을 지정합니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Stepper("마지막 행: \(endRow + 1)", value: $endRow, in: (documentController.currentCellInfo?.row ?? 0)...max((documentController.currentTableDimensions?.rowCount ?? 1) - 1, 0))
                    Stepper("마지막 열: \(endColumn + 1)", value: $endColumn, in: (documentController.currentCellInfo?.col ?? 0)...max((documentController.currentTableDimensions?.colCount ?? 1) - 1, 0))
                }
            } actions: {
                Button("취소") { isPresented = false }
                Button("합치기") {
                    documentController.mergeCurrentTableCells(toRow: endRow, toColumn: endColumn)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

@MainActor
struct BookmarkDialogView: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var selectedBookmarkID: RHWPBookmark.ID?
    @State private var draftName: String = ""

    private var selectedBookmark: RHWPBookmark? {
        guard let selectedBookmarkID else { return nil }
        return documentController.bookmarks.first(where: { $0.id == selectedBookmarkID })
    }

    var body: some View {
        EditorDialogBackdrop(isPresented: $isPresented) {
            EditorDialogContainer(title: "책갈피", width: 560, isPresented: $isPresented) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("등록된 책갈피")
                            .font(.system(size: 12, weight: .semibold))

                        List(selection: $selectedBookmarkID) {
                            ForEach(documentController.bookmarks) { bookmark in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bookmark.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("구역 \(bookmark.sec + 1) · 문단 \(bookmark.para + 1)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .tag(bookmark.id)
                                .padding(.vertical, 3)
                            }
                        }
                        .frame(height: 240)
                    }
                    .frame(width: 236)

                    VStack(alignment: .leading, spacing: 14) {
                        dialogField("이름") {
                            TextField("책갈피 이름", text: $draftName)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("현재 커서 위치에 새 책갈피를 추가하거나, 선택한 항목의 이름을 바꾸고 바로 이동할 수 있습니다.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 8) {
                            Button("현재 위치에 추가") {
                                documentController.addBookmark(named: draftName)
                                selectBookmark(named: draftName)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("선택한 책갈피로 이동") {
                                if let selectedBookmark {
                                    documentController.jumpToBookmark(selectedBookmark)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedBookmark == nil)

                            Button("선택한 이름 변경") {
                                if let selectedBookmark {
                                    documentController.renameBookmark(selectedBookmark, to: draftName)
                                    selectBookmark(named: draftName)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedBookmark == nil || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("선택한 책갈피 삭제", role: .destructive) {
                                if let selectedBookmark {
                                    documentController.deleteBookmark(selectedBookmark)
                                    selectedBookmarkID = nil
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedBookmark == nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } actions: {
                Button("닫기") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            syncSelectionFromBookmarks()
        }
        .onChange(of: documentController.bookmarks) { _, _ in
            syncSelectionFromBookmarks()
        }
        .onChange(of: selectedBookmarkID) { _, _ in
            if let selectedBookmark {
                draftName = selectedBookmark.name
            }
        }
    }

    private func syncSelectionFromBookmarks() {
        if let selectedBookmarkID, documentController.bookmarks.contains(where: { $0.id == selectedBookmarkID }) {
            if let selectedBookmark {
                draftName = selectedBookmark.name
            }
            return
        }

        if let first = documentController.bookmarks.first {
            selectedBookmarkID = first.id
            draftName = first.name
        } else {
            selectedBookmarkID = nil
            if draftName.isEmpty == false {
                draftName = ""
            }
        }
    }

    private func selectBookmark(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let match = documentController.bookmarks.first(where: { $0.name == trimmed }) {
            selectedBookmarkID = match.id
            draftName = match.name
        }
    }
}

@MainActor
struct FieldDialogView: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var selectedFieldID: RHWPFieldInfo.ID?
    @State private var draftValue: String = ""

    private var selectedField: RHWPFieldInfo? {
        guard let selectedFieldID else { return nil }
        return documentController.fields.first(where: { $0.id == selectedFieldID })
    }

    var body: some View {
        EditorDialogBackdrop(isPresented: $isPresented) {
            EditorDialogContainer(title: "필드 입력", width: 640, isPresented: $isPresented) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("문서 필드")
                            .font(.system(size: 12, weight: .semibold))

                        List(selection: $selectedFieldID) {
                            ForEach(documentController.fields) { field in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(field.name.isEmpty ? "(이름 없음)" : field.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(field.fieldType) · \(field.guide.isEmpty ? "안내 없음" : field.guide)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .tag(field.id)
                                .padding(.vertical, 3)
                            }
                        }
                        .frame(height: 260)
                    }
                    .frame(width: 250)

                    VStack(alignment: .leading, spacing: 14) {
                        dialogField("필드 값") {
                            TextField("값 입력", text: $draftValue, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(4, reservesSpace: true)
                        }

                        if let selectedField {
                            VStack(alignment: .leading, spacing: 8) {
                                infoRow("이름", selectedField.name.isEmpty ? "-" : selectedField.name)
                                infoRow("종류", selectedField.fieldType)
                                infoRow("안내", selectedField.guide.isEmpty ? "-" : selectedField.guide)
                                infoRow("문단", "구역 \(selectedField.location.sectionIndex + 1) · 문단 \(selectedField.location.paraIndex + 1)")
                            }
                        } else {
                            Text("왼쪽에서 필드를 선택하면 현재 값을 편집할 수 있습니다.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Button("필드 값 적용") {
                            if let selectedField {
                                documentController.updateFieldValue(name: selectedField.name, value: draftValue)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedField == nil || selectedField?.name.isEmpty == true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } actions: {
                Button("닫기") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            syncSelectedField()
        }
        .onChange(of: documentController.fields) { _, _ in
            syncSelectedField()
        }
        .onChange(of: selectedFieldID) { _, _ in
            draftValue = selectedField?.value ?? ""
        }
    }

    private func syncSelectedField() {
        if let selectedFieldID, documentController.fields.contains(where: { $0.id == selectedFieldID }) {
            draftValue = selectedField?.value ?? ""
            return
        }

        if let first = documentController.fields.first {
            selectedFieldID = first.id
            draftValue = first.value
        } else {
            selectedFieldID = nil
            draftValue = ""
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
        }
    }
}

private struct EditorDialogBackdrop<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            content
        }
    }
}

private struct EditorDialogContainer<Content: View, Actions: View>: View {
    let title: String
    let width: CGFloat
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            content
                .padding(18)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                actions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }
}

private struct EditorLabeledValueField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 56, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
    }
}

@ViewBuilder
private func dialogField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
    }
}

private func formatDecimal(_ value: Double?) -> String {
    guard let value else { return "0" }
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
}
