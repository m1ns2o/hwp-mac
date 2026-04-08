import AppKit
import Combine
import Foundation

@MainActor
final class ViewportController: ObservableObject {
    @Published var zoom: CGFloat = 1.0

    private(set) var pageInfos: [RHWPPageInfo] = []
    private var renderTreeCache: [Int: RHWPRenderNode] = [:]

    let pageSpacing: CGFloat = 28
    let pageInset: CGFloat = 40

    func reload(pageInfos: [RHWPPageInfo]) {
        self.pageInfos = pageInfos
    }

    func invalidateCache() {
        renderTreeCache.removeAll()
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
        let x = pageInset
        let y = CGFloat(pageIndex) * (scaledHeight + pageSpacing) + pageInset
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
        guard let lastPageIndex = pageInfos.indices.last else {
            return CGSize(width: 800, height: 600)
        }
        let lastRect = pageRect(at: lastPageIndex)
        return CGSize(width: max(lastRect.maxX + pageInset, 1000), height: lastRect.maxY + pageInset)
    }

    func visiblePages(in rect: CGRect) -> [Int] {
        pageInfos.indices.filter { pageRect(at: $0).intersects(rect) }
    }
}
