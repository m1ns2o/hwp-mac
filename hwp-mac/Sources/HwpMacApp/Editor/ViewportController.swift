import AppKit
import Combine
import Foundation

@MainActor
final class ViewportController: ObservableObject {
    @Published var zoom: CGFloat = 1.0

    private(set) var pageInfos: [RHWPPageInfo] = []
    private(set) var viewportSize: CGSize = .zero
    private var renderTreeCache: [Int: RHWPRenderNode] = [:]

    let pageSpacing: CGFloat = 28
    let pageInset: CGFloat = 40

    func reload(pageInfos: [RHWPPageInfo]) {
        self.pageInfos = pageInfos
    }

    func invalidateCache() {
        renderTreeCache.removeAll()
    }

    func updateViewportSize(_ size: CGSize) {
        guard viewportSize != size else { return }
        viewportSize = size
    }

    func renderTree(for pageIndex: Int, session: EditorSession) throws -> RHWPRenderNode {
        if let cached = renderTreeCache[pageIndex] {
            return cached
        }
        let tree = try session.pageRenderTree(pageIndex)
        renderTreeCache[pageIndex] = tree
        return tree
    }

    func pageRect(at pageIndex: Int) -> CGRect {
        guard pageInfos.indices.contains(pageIndex) else { return .zero }
        let page = pageInfos[pageIndex]
        let scaledWidth = CGFloat(page.width) * zoom
        let scaledHeight = CGFloat(page.height) * zoom
        let x = max(pageInset, floor((canvasWidth - scaledWidth) * 0.5))
        let y = pageOriginY(at: pageIndex)
        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }

    func pageIndex(at point: CGPoint) -> Int? {
        pageInfos.indices.first { pageRect(at: $0).contains(point) }
    }

    func convertToPageSpace(_ point: CGPoint, pageIndex: Int) -> CGPoint {
        let rect = pageRect(at: pageIndex)
        return CGPoint(
            x: (point.x - rect.minX) / zoom,
            y: (point.y - rect.minY) / zoom
        )
    }

    var documentSize: CGSize {
        guard !pageInfos.isEmpty else {
            return CGSize(
                width: max(viewportSize.width, 800),
                height: max(viewportSize.height, 600)
            )
        }

        let totalHeight = pageInfos.enumerated().reduce(pageInset * 2) { partial, entry in
            let spacing = entry.offset == pageInfos.count - 1 ? 0 : pageSpacing
            return partial + CGFloat(entry.element.height) * zoom + spacing
        }

        return CGSize(
            width: max(canvasWidth, 1000),
            height: max(totalHeight, viewportSize.height)
        )
    }

    func visiblePages(in rect: CGRect) -> [Int] {
        pageInfos.indices.filter { pageRect(at: $0).intersects(rect) }
    }

    private var canvasWidth: CGFloat {
        let widestPage = pageInfos.map { CGFloat($0.width) * zoom }.max() ?? 0
        return max(viewportSize.width, widestPage + pageInset * 2)
    }

    private func pageOriginY(at pageIndex: Int) -> CGFloat {
        guard pageIndex > 0 else { return pageInset }
        return pageInfos[..<pageIndex].reduce(pageInset) { partial, page in
            partial + CGFloat(page.height) * zoom + pageSpacing
        }
    }
}
