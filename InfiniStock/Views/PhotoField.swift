import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 照片框：支持拖拽与文件选择，入库前统一压到 1600px JPEG，避免数据库膨胀。
struct PhotoField: View {
    @Bindable var item: Item

    @State private var importing = false
    @State private var isTargeted = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = item.photoData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(.rect(cornerRadius: 8))
                HStack {
                    Button("更换照片…") { importing = true }
                    Button("删除", role: .destructive) {
                        item.photoData = nil
                        try? item.modelContext?.save()
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Token.Radius.control)
                        .fill(Token.Surface.sidebar)
                    RoundedRectangle(cornerRadius: Token.Radius.control)
                        .strokeBorder(
                            isTargeted ? Token.Accent.brand : Token.Border.hairline,
                            lineWidth: isTargeted ? 1.5 : 1
                        )
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Token.Ink.tertiary)
                        Text("把照片拖到这里")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.secondary)
                        Button("选择照片…") { importing = true }
                            .controlSize(.small)
                    }
                }
                .frame(height: 132)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                persist(ImageScaler.downscaledJPEG(data))
            }
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    errorMessage = "无法读取该文件"
                    return
                }
                persist(ImageScaler.downscaledJPEG(data))
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("照片导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func persist(_ data: Data?) {
        guard let data else {
            errorMessage = "无法解码这张图片"
            return
        }
        Task { @MainActor in
            item.photoData = data
            try? item.modelContext?.save()
        }
    }
}
