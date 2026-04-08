import AppKit
import Foundation

final class PageRenderer {
    private let imageCache = NSCache<NSString, NSImage>()

    func draw(
        tree: RHWPRenderNode,
        in context: CGContext,
        pageOrigin: CGPoint,
        zoom: CGFloat,
        caret: RHWPCaretState?
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: pageOrigin.x, y: pageOrigin.y)
        context.scaleBy(x: zoom, y: zoom)
        draw(node: tree, in: context)

        if let caret {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(max(1.0 / zoom, 1.0))
            context.move(to: CGPoint(x: caret.rect.x, y: caret.rect.y))
            context.addLine(to: CGPoint(x: caret.rect.x, y: caret.rect.y + caret.rect.height))
            context.strokePath()
        }
    }

    private func draw(node: RHWPRenderNode, in context: CGContext) {
        guard node.visible else { return }

        switch node.type {
        case "PageBackground":
            if let pageBackground = node.pageBackground {
                if let background = pageBackground.backgroundColor {
                    context.setFillColor(NSColor(cssHex: background).cgColor)
                    context.fill(node.bbox.rect)
                }
                if let border = pageBackground.borderColor, let width = pageBackground.borderWidth, width > 0 {
                    context.setStrokeColor(NSColor(cssHex: border).cgColor)
                    context.setLineWidth(width)
                    context.stroke(node.bbox.rect)
                }
            }
        case "TextRun":
            if let textRun = node.textRun {
                drawTextRun(textRun, bbox: node.bbox.rect, in: context)
            }
        case "Line":
            if let line = node.line {
                drawLine(line, in: context)
            }
        case "Rectangle":
            if let rectangle = node.rectangle {
                drawRectangle(rectangle, bbox: node.bbox.rect, in: context)
            }
        case "Ellipse":
            if let ellipse = node.ellipse {
                drawEllipse(ellipse, bbox: node.bbox.rect, in: context)
            }
        case "Path":
            if let path = node.path {
                drawPath(path, in: context)
            }
        case "Image":
            if let image = node.image {
                drawImage(image, bbox: node.bbox.rect, in: context)
            }
        case "FormObject":
            if let form = node.formObject {
                drawForm(form, bbox: node.bbox.rect, in: context)
            }
        case "Equation":
            if let equation = node.equation {
                drawEquationPlaceholder(equation, bbox: node.bbox.rect, in: context)
            }
        default:
            break
        }

        node.children.forEach { draw(node: $0, in: context) }
    }

    private func drawTextRun(_ run: RHWPTextRunPayload, bbox: CGRect, in context: CGContext) {
        guard !run.text.isEmpty else { return }

        if run.style.shadeColor.lowercased() != "#ffffff" {
            context.setFillColor(NSColor(cssHex: run.style.shadeColor, alpha: 0.16).cgColor)
            context.fill(bbox)
        }

        let font = resolvedFont(style: run.style)
        let drawOriginY = textOriginY(for: run, bbox: bbox, font: font)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cssHex: run.style.color),
            .underlineStyle: run.style.underline == "None" ? 0 : NSUnderlineStyle.single.rawValue,
            .strikethroughStyle: run.style.strikethrough ? NSUnderlineStyle.single.rawValue : 0,
        ]

        if drawTextRunUsingResolvedPositions(
            run,
            bbox: bbox,
            originY: drawOriginY,
            attributes: textAttributes,
            in: context
        ) {
            return
        }

        let fallbackAttributes = textAttributes.merging(
            [.kern: run.style.letterSpacing],
            uniquingKeysWith: { _, new in new }
        )
        NSString(string: run.text).draw(
            at: CGPoint(x: bbox.minX, y: drawOriginY),
            withAttributes: fallbackAttributes
        )
    }

    private func drawLine(_ line: RHWPLinePayload, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor(cssHex: line.style.color).cgColor)
        context.setLineWidth(max(line.style.width, 0.5))
        applyDash(line.style.dash, to: context)
        context.move(to: CGPoint(x: line.x1, y: line.y1))
        context.addLine(to: CGPoint(x: line.x2, y: line.y2))
        context.strokePath()
        context.restoreGState()
    }

    private func drawRectangle(_ rectangle: RHWPRectanglePayload, bbox: CGRect, in context: CGContext) {
        context.saveGState()
        let path = CGPath(roundedRect: bbox, cornerWidth: rectangle.cornerRadius ?? 0, cornerHeight: rectangle.cornerRadius ?? 0, transform: nil)
        if let fillColor = rectangle.style.fillColor {
            context.addPath(path)
            context.setFillColor(NSColor(cssHex: fillColor, alpha: CGFloat(rectangle.style.opacity ?? 1)).cgColor)
            context.fillPath()
        }
        if let strokeColor = rectangle.style.strokeColor {
            context.addPath(path)
            context.setStrokeColor(NSColor(cssHex: strokeColor).cgColor)
            context.setLineWidth(max(rectangle.style.strokeWidth ?? 0.5, 0.5))
            applyDash(rectangle.style.strokeDash ?? "Solid", to: context)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawEllipse(_ ellipse: RHWPEllipsePayload, bbox: CGRect, in context: CGContext) {
        context.saveGState()
        if let fillColor = ellipse.style.fillColor {
            context.setFillColor(NSColor(cssHex: fillColor, alpha: CGFloat(ellipse.style.opacity ?? 1)).cgColor)
            context.fillEllipse(in: bbox)
        }
        if let strokeColor = ellipse.style.strokeColor {
            context.setStrokeColor(NSColor(cssHex: strokeColor).cgColor)
            context.setLineWidth(max(ellipse.style.strokeWidth ?? 0.5, 0.5))
            applyDash(ellipse.style.strokeDash ?? "Solid", to: context)
            context.strokeEllipse(in: bbox)
        }
        context.restoreGState()
    }

    private func drawPath(_ pathPayload: RHWPPathPayload, in context: CGContext) {
        let path = CGMutablePath()
        for command in pathPayload.commands {
            switch command.type {
            case "MoveTo":
                path.move(to: CGPoint(x: command.x ?? 0, y: command.y ?? 0))
            case "LineTo":
                path.addLine(to: CGPoint(x: command.x ?? 0, y: command.y ?? 0))
            case "CurveTo":
                path.addCurve(
                    to: CGPoint(x: command.x ?? 0, y: command.y ?? 0),
                    control1: CGPoint(x: command.x1 ?? 0, y: command.y1 ?? 0),
                    control2: CGPoint(x: command.x2 ?? 0, y: command.y2 ?? 0)
                )
            case "ClosePath":
                path.closeSubpath()
            default:
                continue
            }
        }

        context.saveGState()
        if let fillColor = pathPayload.style.fillColor {
            context.addPath(path)
            context.setFillColor(NSColor(cssHex: fillColor, alpha: CGFloat(pathPayload.style.opacity ?? 1)).cgColor)
            context.fillPath()
        }
        if let strokeColor = pathPayload.style.strokeColor {
            context.addPath(path)
            context.setStrokeColor(NSColor(cssHex: strokeColor).cgColor)
            context.setLineWidth(max(pathPayload.style.strokeWidth ?? 0.5, 0.5))
            applyDash(pathPayload.style.strokeDash ?? "Solid", to: context)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawImage(_ payload: RHWPImagePayload, bbox: CGRect, in context: CGContext) {
        guard
            let dataBase64 = payload.dataBase64,
            let image = image(from: dataBase64)
        else { return }
        image.draw(in: bbox)
    }

    private func drawEquationPlaceholder(_ equation: RHWPEquationPayload, bbox: CGRect, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(equation.fontSize, 12), weight: .medium),
            .foregroundColor: NSColor(cssHex: equation.color),
        ]
        NSString(string: "∑").draw(in: bbox, withAttributes: attributes)
    }

    private func drawForm(_ form: RHWPFormObjectPayload, bbox: CGRect, in context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor(cssHex: form.backgroundColor).cgColor)
        context.fill(bbox)
        context.setStrokeColor(NSColor(cssHex: form.foregroundColor).cgColor)
        context.setLineWidth(1)
        context.stroke(bbox)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(cssHex: form.foregroundColor),
        ]
        let text = form.caption.isEmpty ? form.text : form.caption
        NSString(string: text).draw(in: bbox.insetBy(dx: 6, dy: 4), withAttributes: attributes)
        context.restoreGState()
    }

    private func resolvedFont(style: RHWPTextStylePayload) -> NSFont {
        let base = NSFont(name: style.fontFamily, size: max(style.fontSize, 11))
            ?? NSFont.systemFont(ofSize: max(style.fontSize, 11))

        var font = base
        let manager = NSFontManager.shared
        if style.bold {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if style.italic {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private func drawTextRunUsingResolvedPositions(
        _ run: RHWPTextRunPayload,
        bbox: CGRect,
        originY: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) -> Bool {
        guard
            let charX = run.charX,
            !charX.isEmpty
        else {
            return false
        }

        let scalars = Array(run.text.unicodeScalars)
        guard charX.count >= scalars.count + 1 else {
            return false
        }

        for (index, scalar) in scalars.enumerated() {
            let origin = CGPoint(
                x: bbox.minX + charX[index],
                y: originY
            )
            drawScalar(
                String(scalar),
                at: origin,
                style: run.style,
                attributes: attributes,
                in: context
            )
        }

        return true
    }

    private func drawScalar(
        _ scalar: String,
        at origin: CGPoint,
        style: RHWPTextStylePayload,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) {
        let ratio = max(style.ratio, 0.1)
        if abs(ratio - 1.0) > 0.001 {
            context.saveGState()
            context.translateBy(x: origin.x, y: 0)
            context.scaleBy(x: ratio, y: 1)
            NSString(string: scalar).draw(at: CGPoint(x: 0, y: origin.y), withAttributes: attributes)
            context.restoreGState()
            return
        }

        NSString(string: scalar).draw(at: origin, withAttributes: attributes)
    }

    private func textOriginY(for run: RHWPTextRunPayload, bbox: CGRect, font: NSFont) -> CGFloat {
        let baseline = run.baseline.map { CGFloat($0) } ?? font.ascender
        return bbox.minY + max(baseline - font.ascender, 0)
    }

    private func applyDash(_ dash: String, to context: CGContext) {
        switch dash {
        case "Dash":
            context.setLineDash(phase: 0, lengths: [6, 4])
        case "Dot":
            context.setLineDash(phase: 0, lengths: [2, 3])
        case "DashDot":
            context.setLineDash(phase: 0, lengths: [8, 3, 2, 3])
        case "DashDotDot":
            context.setLineDash(phase: 0, lengths: [8, 3, 2, 3, 2, 3])
        default:
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    private func image(from base64: String) -> NSImage? {
        if let cached = imageCache.object(forKey: base64 as NSString) {
            return cached
        }
        guard let data = Data(base64Encoded: base64), let image = NSImage(data: data) else {
            return nil
        }
        imageCache.setObject(image, forKey: base64 as NSString)
        return image
    }
}
