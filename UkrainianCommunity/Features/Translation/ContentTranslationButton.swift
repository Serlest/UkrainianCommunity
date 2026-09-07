import SwiftUI
import FirebaseFunctions

struct ContentTranslationField {
    let id: String
    let title: String
    let source: String
    let target: Binding<String>
    let limit: Int
    init(_ id: String, _ title: String, source: String, target: Binding<String>, limit: Int) {
        self.id = id; self.title = title; self.source = source; self.target = target; self.limit = limit
    }
}
struct ContentTranslationPreview: Identifiable {
    let id = UUID()
    let userID: String?
    let sources: [String]
    let previousTargets: [String]
    let indices: [Int]
    var translations: [String]
    func isCurrent(userID: String?, sources: [String], targets: [String]) -> Bool {
        self.userID == userID && self.sources == sources && previousTargets == targets
    }
}

@MainActor
enum ContentTranslationService {
    static func translate(kind: String, texts: [String], sourceLanguage: AppLanguage) async throws -> [String] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return texts.map { (sourceLanguage == .ukrainian ? "DE: " : "UK: ") + $0 }
        }
        #endif
        struct Request: Encodable { let kind: String; let texts: [String]; let source: String }
        struct Response: Decodable { let texts: [String] }
        let call: Callable<Request, Response> = Functions.functions(region: "europe-west3").httpsCallable("translateContent")
        return try await call.call(Request(kind: kind, texts: texts, source: sourceLanguage.rawValue)).texts
    }
}

struct ContentTranslationButton: View {
    let kind: String
    let fields: [ContentTranslationField]
    let sourceLanguage: AppLanguage
    private var targetLanguage: AppLanguage { sourceLanguage == .ukrainian ? .german : .ukrainian }
    init(kind: String, fields: [ContentTranslationField], sourceLanguage: AppLanguage = .ukrainian) {
        self.kind = kind; self.fields = fields; self.sourceLanguage = sourceLanguage
    }
    @EnvironmentObject private var authState: AuthState
    @State private var preview: ContentTranslationPreview?
    @State private var error: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: translate) {
                HStack {
                    if busy { ProgressView() } else { Image(systemName: "character.bubble") }
                    Text(targetLanguage == .german ? EditorTranslationStrings.translate : EditorTranslationStrings.translateToUkrainian)
                }.frame(maxWidth: .infinity)
            }.appActionButtonStyle(.secondary)
                .disabled(busy || fields.allSatisfy { $0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                .accessibilityIdentifier("translation.\(kind)")
            Text(EditorTranslationStrings.hint).font(.caption).foregroundStyle(AppTheme.textSecondary)
            if let error { InlineMessageCard(style: .error, message: error) }
        }
        .sheet(item: $preview) { draft in
            NavigationStack { ContentTranslationReview(draft: draft, fields: fields, targetLanguage: targetLanguage) { result in
                guard result.isCurrent(userID: authState.user?.id, sources: fields.map(\.source), targets: fields.map { $0.target.wrappedValue }) else {
                    error = EditorTranslationStrings.changed; return false
                }
                for (offset, index) in result.indices.enumerated() { fields[index].target.wrappedValue = result.translations[offset] }
                error = nil; preview = nil; return true
            } }
        }
        .onChange(of: authState.user?.id) { _, _ in task?.cancel(); preview = nil; busy = false }
        .onDisappear { task?.cancel(); busy = false }
    }
    private func translate() {
        let sources = fields.map(\.source), targets = fields.map { $0.target.wrappedValue }
        let indices = fields.indices.filter { !sources[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let userID = authState.user?.id
        busy = true; error = nil
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await ContentTranslationService.translate(kind: kind, texts: indices.map { sources[$0] }, sourceLanguage: sourceLanguage)
                guard !Task.isCancelled, result.count == indices.count, userID == authState.user?.id else { return }
                preview = ContentTranslationPreview(userID: userID, sources: sources, previousTargets: targets, indices: indices, translations: result)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as NSError).code == FunctionsErrorCode.resourceExhausted.rawValue ? EditorTranslationStrings.limit : EditorTranslationStrings.error
            }
        }
    }
}

private struct ContentTranslationReview: View {
    @State var draft: ContentTranslationPreview
    let fields: [ContentTranslationField]
    let targetLanguage: AppLanguage
    let apply: (ContentTranslationPreview) -> Bool
    @State private var error: String?
    @State private var confirmsReplacement = false
    private var needsReplacementConfirmation: Bool {
        draft.indices.contains { !draft.previousTargets[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var valid: Bool {
        draft.indices.enumerated().allSatisfy { offset, index in
            !draft.translations[offset].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.translations[offset].count <= fields[index].limit
        }
    }
    var body: some View {
        EditorScreenShell(title: EditorTranslationStrings.review, subtitle: EditorTranslationStrings.hint, closeStyle: .cancel) {
            if let error { InlineMessageCard(style: .error, message: error) }
            ForEach(Array(draft.indices.enumerated()), id: \.element) { offset, index in
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        AppEditorSectionTitle(title: fields[index].title)
                        Text(draft.sources[index]).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                        EditorTextArea(targetLanguage.title, text: $draft.translations[offset],
                                       counterText: "\(draft.translations[offset].count)/\(fields[index].limit)", minHeight: 100)
                            .accessibilityIdentifier("translation.result.\(fields[index].id)")
                    }
                }
            }
            if needsReplacementConfirmation {
                AppEditorSectionCard {
                    Toggle(targetLanguage == .german ? EditorTranslationStrings.overwrite : EditorTranslationStrings.overwriteUkrainian,
                           isOn: $confirmsReplacement)
                        .accessibilityIdentifier("translation.confirm")
                }
            }
            PrimaryActionButton(title: EditorTranslationStrings.apply,
                                isEnabled: valid && (!needsReplacementConfirmation || confirmsReplacement),
                                systemImage: "checkmark") { commit() }
                .accessibilityIdentifier("translation.apply")
        }
    }
    private func commit() {
        if !apply(draft) { error = EditorTranslationStrings.changed }
    }
}
