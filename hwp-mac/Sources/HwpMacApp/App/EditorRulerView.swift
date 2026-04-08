import SwiftUI

struct EditorRulerView: View {
    @ObservedObject var documentController: DocumentController
    @ObservedObject var viewportController: ViewportController

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(nsColor: .windowBackgroundColor)

                if let pageInfo = documentController.pageInfos.first {
                    let pageWidth = CGFloat(pageInfo.width) * viewportController.zoom
                    let rulerWidth = min(max(pageWidth, 320), max(geometry.size.width - 48, 320))

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        Canvas { context, size in
                            let baselineY = size.height - 8
                            let trackRect = CGRect(x: 0, y: baselineY - 12, width: size.width, height: 20)

                            context.fill(
                                Path(roundedRect: trackRect, cornerRadius: 2),
                                with: .color(Color(nsColor: .controlBackgroundColor))
                            )
                            context.stroke(
                                Path(roundedRect: trackRect, cornerRadius: 2),
                                with: .color(Color.black.opacity(0.08)),
                                lineWidth: 1
                            )

                            for mark in 0...20 {
                                let progress = CGFloat(mark) / 20
                                let x = size.width * progress
                                let isMajor = mark < 20
                                let tickHeight: CGFloat = isMajor ? 9 : 6

                                var tick = Path()
                                tick.move(to: CGPoint(x: x, y: baselineY - tickHeight))
                                tick.addLine(to: CGPoint(x: x, y: baselineY))
                                context.stroke(tick, with: .color(Color.black.opacity(0.45)), lineWidth: 1)

                                if mark < 20 {
                                    let label = context.resolve(
                                        Text("\(mark)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    )
                                    context.draw(label, at: CGPoint(x: x + 10, y: baselineY - 10), anchor: .center)
                                }

                                if mark < 20 {
                                    for minor in 1...4 {
                                        let minorX = x + (size.width / 20) * (CGFloat(minor) / 5)
                                        var minorTick = Path()
                                        minorTick.move(to: CGPoint(x: minorX, y: baselineY - 5))
                                        minorTick.addLine(to: CGPoint(x: minorX, y: baselineY))
                                        context.stroke(minorTick, with: .color(Color.black.opacity(0.28)), lineWidth: 0.8)
                                    }
                                }
                            }
                        }
                        .frame(width: rulerWidth, height: 30)
                        .overlay(alignment: .leading) {
                            rulerMarker
                                .offset(x: 44, y: 4)
                        }
                        .overlay(alignment: .trailing) {
                            rulerMarker
                                .rotationEffect(.degrees(180))
                                .offset(x: -44, y: 4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("눈금자")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var rulerMarker: some View {
        VStack(spacing: 0) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            Rectangle()
                .fill(Color(nsColor: .secondaryLabelColor))
                .frame(width: 1, height: 10)
        }
    }
}
