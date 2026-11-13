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
                // 没有照片时不再摆一块 132pt 的空框：一行高、可拖可点的窄条就够，
                // 省下的高度留给价格和机况。
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Token.Ink.tertiary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("拖入或选择照片")
                            .font(Token.Typography.caption)
                            .foregroundStyle(Token.Ink.secondary)
                        Text("入库前会自动压到 1600px")
                            .font(.system(size: 10))
                            .foregroundStyle(Token.Ink.tertiary)
                    }
                    Spacer(minLength: 0)
                    Button("选择…") { importing = true }
                        .controlSize(.small)
                }
                .padding(.horizontal, Token.Space.m)
                .frame(height: 60)
                .background(Token.Surface.sidebar, in: .rect(cornerRadius: Token.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Token.Radius.control)
                        .strokeBorder(
                            isTargeted ? Token.Accent.brand : Token.Border.hairline,
                            lineWidth: isTargeted ? 1.5 : 1
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                let jpeg = ImageScaler.downscaledJPEG(data)
                // 这个回调在后台线程，而 persist 要改 @State，必须回主线程
                Task { @MainActor in persist(jpeg) }
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
