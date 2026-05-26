import SwiftUI

struct ContextItemRow: View {

    let item: ContextItem
    @EnvironmentObject var store: ShelfStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // 아이콘
            Image(systemName: item.displayIcon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)

            // 내용 미리보기
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 삭제 버튼 (hover 시 표시)
            if isHovered {
                Button {
                    store.removeItem(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var iconColor: Color {
        switch item.contentType {
        case .text:  return .blue
        case .file:  return .orange
        case .image: return .purple
        case .url:   return .green
        }
    }

    private var subtitle: String? {
        switch item.contentType {
        case .text:
            let lines = item.rawContent.components(separatedBy: .newlines).count
            return lines > 1 ? "\(lines)줄" : nil
        case .file:
            let lines = item.rawContent.components(separatedBy: .newlines).count
            let lang = item.language.map { " · \($0)" } ?? ""
            return "\(lines)줄\(lang)"
        case .image:
            return nil
        case .url:
            return item.rawContent
        }
    }
}
