import SwiftUI

struct TableInsertPopover: View {
    @Binding var rows: Int
    @Binding var columns: Int

    let onInsert: (Int, Int) -> Void
    let onAdvanced: () -> Void

    @State private var hoverRows: Int?
    @State private var hoverColumns: Int?

    private let maxRows = 8
    private let maxColumns = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("표")
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(20), spacing: 4), count: maxColumns), spacing: 4) {
                    ForEach(0..<(maxRows * maxColumns), id: \.self) { index in
                        let row = (index / maxColumns) + 1
                        let column = (index % maxColumns) + 1

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isHighlighted(row: row, column: column) ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.14))
                            .frame(width: 20, height: 20)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.28), lineWidth: 0.6)
                            }
                            .onHover { hovering in
                                if hovering {
                                    hoverRows = row
                                    hoverColumns = column
                                }
                            }
                            .onTapGesture {
                                rows = row
                                columns = column
                                onInsert(row, column)
                            }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                )

                Text("\(previewRows) x \(previewColumns)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("표 만들기...", action: onAdvanced)
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 2)
        }
        .onDisappear {
            hoverRows = nil
            hoverColumns = nil
        }
    }

    private var previewRows: Int {
        hoverRows ?? rows
    }

    private var previewColumns: Int {
        hoverColumns ?? columns
    }

    private func isHighlighted(row: Int, column: Int) -> Bool {
        row <= previewRows && column <= previewColumns
    }
}
