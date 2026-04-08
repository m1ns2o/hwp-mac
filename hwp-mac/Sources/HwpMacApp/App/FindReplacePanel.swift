import SwiftUI

private enum FindDirection: String, CaseIterable, Identifiable {
    case down = "아래로"
    case up = "위로"
    case all = "문서 전체"

    var id: String { rawValue }
}

@MainActor
struct FindReplacePanel: View {
    @ObservedObject var documentController: DocumentController
    @Binding var isPresented: Bool

    @State private var direction: FindDirection = .down
    @State private var settledOffset: CGSize = .zero
    @State private var panelOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("찾아 바꾸기")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        panelOffset = value.translation
                    }
                    .onEnded { value in
                        settledOffset = CGSize(
                            width: settledOffset.width + value.translation.width,
                            height: settledOffset.height + value.translation.height
                        )
                        panelOffset = .zero
                    }
            )

            Divider()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    labeledField("찾을 내용", text: $documentController.searchQuery)
                    labeledField("바꿀 내용", text: $documentController.replaceQuery)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("찾을 방향")
                            .font(.system(size: 12, weight: .medium))

                        HStack(spacing: 16) {
                            ForEach(FindDirection.allCases) { value in
                                Button {
                                    direction = value
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: direction == value ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 12))
                                        Text(value.rawValue)
                                            .font(.system(size: 12))
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                            }
                        }
                    }

                    Toggle("대소문자 구분", isOn: $documentController.searchCaseSensitive)
                        .font(.system(size: 12))

                    if !documentController.searchStatus.isEmpty {
                        Text(documentController.searchStatus)
                            .font(.system(size: 11))
                            .foregroundStyle(documentController.searchStatus.contains("없") ? Color.red : .secondary)
                    }
                }

                VStack(spacing: 10) {
                    panelButton("바꾸기", enabled: canExecuteFind) {
                        documentController.replaceCurrent()
                    }
                    panelButton(direction == .up ? "이전 찾기" : "다음 찾기", enabled: canExecuteFind) {
                        runFindAction()
                    }
                    panelButton("모두 바꾸기", enabled: canExecuteFind) {
                        documentController.replaceAll()
                    }
                    panelButton("닫기", enabled: true) {
                        isPresented = false
                    }
                    .padding(.top, 8)
                }
                .frame(width: 104)
            }
            .padding(14)
        }
        .frame(width: 432)
        .offset(
            x: settledOffset.width + panelOffset.width,
            y: settledOffset.height + panelOffset.height
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }
}

private extension FindReplacePanel {
    var canExecuteFind: Bool {
        !documentController.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    func panelButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .disabled(!enabled)
    }

    func runFindAction() {
        switch direction {
        case .down, .all:
            documentController.findNext()
        case .up:
            documentController.findPrevious()
        }
    }
}
