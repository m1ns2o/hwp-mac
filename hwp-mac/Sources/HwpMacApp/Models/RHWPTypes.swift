import AppKit
import Foundation

struct RHWPDocumentInfo: Codable {
    let version: String
    let sectionCount: Int
    let pageCount: Int
    let encrypted: Bool
    let fallbackFont: String
    let fontsUsed: [String]
}

struct RHWPPageInfo: Codable, Identifiable {
    let pageIndex: Int
    let width: Double
    let height: Double
    let sectionIndex: Int
    let marginLeft: Double?
    let marginRight: Double?
    let marginTop: Double?
    let marginBottom: Double?
    let marginHeader: Double?
    let marginFooter: Double?

    var id: Int { pageIndex }
}

struct RHWPCursorRect: Codable, Equatable {
    let pageIndex: Int
    let x: Double
    let y: Double
    let height: Double
}

struct RHWPCellPathEntry: Codable, Equatable {
    let controlIndex: Int
    let cellIndex: Int
    let cellParaIndex: Int
}

struct RHWPCellContext: Codable, Equatable {
    let parentParaIndex: Int
    let controlIndex: Int
    let cellIndex: Int
    let cellParaIndex: Int
    let isTextBox: Bool
    let cellPath: [RHWPCellPathEntry]

    init(
        parentParaIndex: Int,
        controlIndex: Int,
        cellIndex: Int,
        cellParaIndex: Int,
        isTextBox: Bool = false,
        cellPath: [RHWPCellPathEntry] = []
    ) {
        self.parentParaIndex = parentParaIndex
        self.controlIndex = controlIndex
        self.cellIndex = cellIndex
        self.cellParaIndex = cellParaIndex
        self.isTextBox = isTextBox
        self.cellPath = cellPath
    }
}

struct RHWPHitTestResult: Codable {
    let sectionIndex: Int
    let paragraphIndex: Int
    let charOffset: Int
    let parentParaIndex: Int?
    let controlIndex: Int?
    let cellIndex: Int?
    let cellParaIndex: Int?
    let isTextBox: Bool?
    let cellPath: [RHWPCellPathEntry]?
}

struct RHWPMoveVerticalResult: Codable {
    let sectionIndex: Int
    let paragraphIndex: Int
    let charOffset: Int
    let pageIndex: Int
    let x: Double
    let y: Double
    let height: Double
    let preferredX: Double
    let parentParaIndex: Int?
    let controlIndex: Int?
    let cellIndex: Int?
    let cellParaIndex: Int?
    let isTextBox: Bool?
    let cellPath: [RHWPCellPathEntry]?
}

struct RHWPLengthResult: Codable {
    let length: Int
}

struct RHWPCountResult: Codable {
    let count: Int
}

struct RHWPCaretPosition: Codable, Equatable {
    let sectionIndex: Int
    let paragraphIndex: Int
    let charOffset: Int
    let cellContext: RHWPCellContext?

    init(
        sectionIndex: Int,
        paragraphIndex: Int,
        charOffset: Int,
        cellContext: RHWPCellContext? = nil
    ) {
        self.sectionIndex = sectionIndex
        self.paragraphIndex = paragraphIndex
        self.charOffset = charOffset
        self.cellContext = cellContext
    }
}

struct RHWPCaretState: Equatable {
    let position: RHWPCaretPosition
    let rect: RHWPCursorRect
    var preferredX: Double?
}

struct RHWPSelectionRect: Codable, Equatable {
    let pageIndex: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct RHWPSelectionState: Equatable {
    let anchor: RHWPCaretPosition
    let focus: RHWPCaretPosition

    var isCollapsed: Bool {
        anchor == focus
    }
}

struct RHWPClipboardCopyResult: Codable {
    let ok: Bool
    let text: String?
}

struct RHWPBasicResult: Codable {
    let ok: Bool
}

struct RHWPOperationStatus: Codable {
    let ok: Bool
    let error: String?
}

struct RHWPSearchResult: Codable {
    let found: Bool
    let wrapped: Bool?
    let sec: Int?
    let para: Int?
    let charOffset: Int?
    let length: Int?
}

struct RHWPCharProperties: Codable {
    let fontFamily: String
    let fontSize: Double
    let bold: Bool
    let italic: Bool
    let underline: Bool
    let underlineType: String
    let underlineColor: String?
    let strikethrough: Bool
    let strikeColor: String?
    let textColor: String
    let shadeColor: String
    let shadowType: Int?
    let shadowColor: String?
    let shadowOffsetX: Int?
    let shadowOffsetY: Int?
    let outlineType: Int?
    let subscriptEnabled: Bool?
    let superscript: Bool?
    let emboss: Bool?
    let engrave: Bool?
    let emphasisDot: Int?
    let underlineShape: Int?
    let strikeShape: Int?
    let kerning: Bool?
    let fontFamilies: [String]?
    let ratios: [Int]?
    let spacings: [Int]?
    let relativeSizes: [Int]?
    let charOffsets: [Int]?
    let charShapeId: Int

    enum CodingKeys: String, CodingKey {
        case fontFamily
        case fontSize
        case bold
        case italic
        case underline
        case underlineType
        case underlineColor
        case strikethrough
        case strikeColor
        case textColor
        case shadeColor
        case shadowType
        case shadowColor
        case shadowOffsetX
        case shadowOffsetY
        case outlineType
        case subscriptEnabled = "subscript"
        case superscript
        case emboss
        case engrave
        case emphasisDot
        case underlineShape
        case strikeShape
        case kerning
        case fontFamilies
        case ratios
        case spacings
        case relativeSizes
        case charOffsets
        case charShapeId
    }
}

struct RHWPParaProperties: Codable {
    let alignment: String
    let lineSpacing: Double
    let lineSpacingType: String
    let paraShapeId: Int
    let headType: String
    let numberingId: Int
    let paraLevel: Int?
    let marginLeft: Double?
    let marginRight: Double?
    let indent: Double?
    let spacingBefore: Double
    let spacingAfter: Double
    let widowOrphan: Bool?
    let keepWithNext: Bool?
    let keepLines: Bool?
    let pageBreakBefore: Bool?
    let fontLineHeight: Bool?
    let singleLine: Bool?
    let autoSpaceKrEn: Bool?
    let autoSpaceKrNum: Bool?
    let verticalAlign: Int?
    let englishBreakUnit: Int?
    let koreanBreakUnit: Int?
    let tabAutoLeft: Bool?
    let tabAutoRight: Bool?
    let tabStops: [RHWPTabStop]?
    let defaultTabSpacing: Int?
    let borderFillId: Int?
    let borderLeft: RHWPBorderSide?
    let borderRight: RHWPBorderSide?
    let borderTop: RHWPBorderSide?
    let borderBottom: RHWPBorderSide?
    let fillType: String?
    let fillColor: String?
    let patternColor: String?
    let patternType: Int?
    let borderSpacing: [Int]?
}

struct RHWPIdentifierResult: Codable {
    let id: Int
}

struct RHWPBookmark: Codable, Identifiable, Hashable {
    let name: String
    let sec: Int
    let para: Int
    let ctrlIdx: Int
    let charPos: Int

    var id: String {
        "\(sec):\(para):\(ctrlIdx):\(name)"
    }
}

struct RHWPFieldLocationPathEntry: Codable, Hashable {
    let type: String
    let controlIndex: Int
    let cellIndex: Int?
    let paraIndex: Int
}

struct RHWPFieldLocation: Codable, Hashable {
    let sectionIndex: Int
    let paraIndex: Int
    let path: [RHWPFieldLocationPathEntry]?
}

struct RHWPFieldInfo: Codable, Identifiable, Hashable {
    let fieldId: UInt32
    let fieldType: String
    let name: String
    let guide: String
    let command: String
    let value: String
    let location: RHWPFieldLocation

    var id: UInt32 { fieldId }
}

struct RHWPTabStop: Codable, Equatable {
    let position: Int
    let type: Int
    let fill: Int
}

struct RHWPBorderSide: Codable, Equatable {
    let type: Int
    let width: Int
    let color: String
}

struct RHWPCellProperties: Codable {
    let width: Int
    let height: Int
    let paddingLeft: Int
    let paddingRight: Int
    let paddingTop: Int
    let paddingBottom: Int
    let verticalAlign: Int
    let textDirection: Int
    let isHeader: Bool
    let cellProtect: Bool
    let borderFillId: Int
    let borderLeft: RHWPBorderSide
    let borderRight: RHWPBorderSide
    let borderTop: RHWPBorderSide
    let borderBottom: RHWPBorderSide
    let fillType: String
    let fillColor: String
    let patternColor: String
    let patternType: Int
}

struct RHWPTableProperties: Codable {
    let cellSpacing: Int
    let paddingLeft: Int
    let paddingRight: Int
    let paddingTop: Int
    let paddingBottom: Int
    let pageBreak: Int
    let repeatHeader: Bool
    let borderFillId: Int
    let borderLeft: RHWPBorderSide
    let borderRight: RHWPBorderSide
    let borderTop: RHWPBorderSide
    let borderBottom: RHWPBorderSide
    let fillType: String
    let fillColor: String
    let patternColor: String
    let patternType: Int
    let tableWidth: Int
    let tableHeight: Int
    let outerLeft: Int
    let outerRight: Int
    let outerTop: Int
    let outerBottom: Int
    let hasCaption: Bool
    let captionDirection: Int?
    let captionVertAlign: Int?
    let captionWidth: Int?
    let captionSpacing: Int?
    let treatAsChar: Bool
    let textWrap: String
    let vertRelTo: String
    let vertAlign: String
    let horzRelTo: String
    let horzAlign: String
    let vertOffset: Int
    let horzOffset: Int
    let restrictInPage: Bool
    let allowOverlap: Bool
    let keepWithAnchor: Bool
}

struct RHWPTableDimensionsResult: Codable {
    let rowCount: Int
    let colCount: Int
    let cellCount: Int
}

struct RHWPCellInfoResult: Codable {
    let row: Int
    let col: Int
    let rowSpan: Int
    let colSpan: Int
}

struct RHWPMutationCursorResult: Codable {
    let ok: Bool
    let paraIdx: Int?
    let charOffset: Int?
    let cellParaIndex: Int?
}

struct RHWPBoundingBox: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct RHWPPagePayload: Codable {
    let pageIndex: Int
    let width: Double
    let height: Double
    let sectionIndex: Int
}

struct RHWPPageBackgroundPayload: Codable {
    let backgroundColor: String?
    let borderColor: String?
    let borderWidth: Double?
}

struct RHWPTransformPayload: Codable {
    let rotation: Double
    let horzFlip: Bool
    let vertFlip: Bool
}

struct RHWPShadowPayload: Codable {
    let shadowType: Int
    let color: String
    let offsetX: Double
    let offsetY: Double
    let alpha: Int
}

struct RHWPPatternPayload: Codable {
    let patternType: Int
    let patternColor: String
    let backgroundColor: String
}

struct RHWPGradientPayload: Codable {
    let gradientType: Int
    let angle: Int
    let centerX: Int
    let centerY: Int
    let colors: [String]
    let positions: [Double]
}

struct RHWPShapeStylePayload: Codable {
    let fillColor: String?
    let pattern: RHWPPatternPayload?
    let strokeColor: String?
    let strokeWidth: Double?
    let strokeDash: String?
    let opacity: Double?
    let shadow: RHWPShadowPayload?
}

struct RHWPLineStylePayload: Codable {
    let color: String
    let width: Double
    let dash: String
    let lineType: String
    let startArrow: String
    let endArrow: String
    let startArrowSize: Int
    let endArrowSize: Int
    let shadow: RHWPShadowPayload?
}

struct RHWPTextStylePayload: Codable {
    let fontFamily: String
    let fontSize: Double
    let color: String
    let bold: Bool
    let italic: Bool
    let underline: String
    let strikethrough: Bool
    let letterSpacing: Double
    let ratio: Double
    let shadowColor: String
    let shadowOffsetX: Double
    let shadowOffsetY: Double
    let shadeColor: String
}

struct RHWPTextRunPayload: Codable {
    let text: String
    let charX: [Double]?
    let style: RHWPTextStylePayload
    let sectionIndex: Int?
    let paraIndex: Int?
    let charStart: Int?
    let isParaEnd: Bool?
    let rotation: Double?
    let baseline: Double?
}

struct RHWPLinePayload: Codable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
    let style: RHWPLineStylePayload
    let transform: RHWPTransformPayload
}

struct RHWPRectanglePayload: Codable {
    let cornerRadius: Double?
    let style: RHWPShapeStylePayload
    let gradient: RHWPGradientPayload?
    let transform: RHWPTransformPayload
}

struct RHWPEllipsePayload: Codable {
    let style: RHWPShapeStylePayload
    let gradient: RHWPGradientPayload?
    let transform: RHWPTransformPayload
}

struct RHWPPathCommandPayload: Codable {
    let type: String
    let x: Double?
    let y: Double?
    let x1: Double?
    let y1: Double?
    let x2: Double?
    let y2: Double?
    let rx: Double?
    let ry: Double?
    let rotation: Double?
    let largeArc: Bool?
    let sweep: Bool?
}

struct RHWPPathPayload: Codable {
    let commands: [RHWPPathCommandPayload]
    let style: RHWPShapeStylePayload
    let gradient: RHWPGradientPayload?
    let transform: RHWPTransformPayload
}

struct RHWPImagePayload: Codable {
    let dataBase64: String?
    let transform: RHWPTransformPayload
}

struct RHWPRenderNode: Codable {
    let id: Int
    let type: String
    let bbox: RHWPBoundingBox
    let visible: Bool
    let dirty: Bool
    let children: [RHWPRenderNode]

    let page: RHWPPagePayload?
    let pageBackground: RHWPPageBackgroundPayload?
    let textRun: RHWPTextRunPayload?
    let line: RHWPLinePayload?
    let rectangle: RHWPRectanglePayload?
    let ellipse: RHWPEllipsePayload?
    let path: RHWPPathPayload?
    let image: RHWPImagePayload?
    let equation: RHWPEquationPayload?
    let formObject: RHWPFormObjectPayload?
}

struct RHWPEquationPayload: Codable {
    let svgContent: String
    let color: String
    let fontSize: Double
}

struct RHWPFormObjectPayload: Codable {
    let formType: String
    let caption: String
    let text: String
    let foregroundColor: String
    let backgroundColor: String
}

extension RHWPBoundingBox {
    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

extension RHWPCursorRect {
    var rect: CGRect {
        CGRect(x: x, y: y, width: 1, height: height)
    }
}
