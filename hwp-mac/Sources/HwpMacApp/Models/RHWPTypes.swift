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
    let strikethrough: Bool
    let textColor: String
    let shadeColor: String
    let charShapeId: Int
}

struct RHWPParaProperties: Codable {
    let alignment: String
    let lineSpacing: Double
    let lineSpacingType: String
    let paraShapeId: Int
    let headType: String
    let numberingId: Int
    let spacingBefore: Double
    let spacingAfter: Double
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
