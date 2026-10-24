import FirebaseFunctions
import SwiftUI

struct DirectoryCategoryEditorView: View {
    private enum Confirmation: Equatable {
        case publish, discard, deleteCategory
        case deleteGroup(String), deleteTopic(String)
    }
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    private let focusTopicID: String?
    @State private var original: DirectoryManagedCategory
    @State private var draft: DirectoryManagedCategory
    @State private var expectedRevision: Int = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsValidation = false
    @State private var confirmation: Confirmation?
    @State private var editingLanguage: AppLanguage = .ukrainian
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var hasUnsavedChanges: Bool { draft != original }
    private var isNewCategory: Bool { original.title.ukrainian.isEmpty && original.title.german.isEmpty }

    init(category: DirectoryManagedCategory?, expectedRevision: Int = 0, focusTopicID: String? = nil,
         newPlacement: DirectoryManagedCategory.Placement = .support, newOrder: Int = 0) {
        self.focusTopicID = focusTopicID
        _expectedRevision = State(initialValue: expectedRevision)
        let initial = category ?? DirectoryEditorDrafts.category(placement: newPlacement, order: newOrder)
        _original = State(initialValue: initial)
        _draft = State(initialValue: initial)
    }

    var body: some View {
        Group {
            if let focusTopicID, let index = draft.topics.firstIndex(where: { $0.id == focusTopicID }) {
                DirectoryTopicEditorView(topic: $draft.topics[index], groups: draft.groups)
            } else if isNewCategory {
                DirectoryNewCategoryFormView(draft: $draft, editingLanguage: $editingLanguage)
            } else {
                DirectoryCategoryFormView(
                    draft: $draft, hasUnsavedChanges: hasUnsavedChanges, isSaving: isSaving,
                    onDeleteCategory: { confirmation = .deleteCategory },
                    onDeleteGroup: { confirmation = .deleteGroup($0) },
                    onDeleteTopic: { confirmation = .deleteTopic($0) }
                )
            }
        }
        .disabled(isSaving || !contentStore.canEdit)
        .environment(\.directoryShowsValidation, showsValidation)
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in confirmation = nil; dismiss() }
        .onChange(of: contentStore.canEdit) { _, allowed in if !allowed { confirmation = nil; dismiss() } }
        .navigationBarBackButtonHidden()
        .navigationTitle(focusTopicID.flatMap { id in
            draft.topics.first { $0.id == id }?.title.value(for: language)
        } ?? (draft.title.value(for: language).isEmpty
               ? DirectoryEditorText.value("Нова категорія", "Neuer Bereich")
               : draft.title.value(for: language)))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasUnsavedChanges { confirmation = .discard }
                    else { dismiss() }
                } label: {
                    Label(DirectoryEditorText.value("Назад", "Zurück"), systemImage: "chevron.left")
                }
                .disabled(isSaving)
            }
            if contentStore.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmation = .publish
                    } label: {
                        if isSaving { ProgressView() }
                        else { Text(DirectoryEditorText.value("Опублікувати", "Veröffentlichen")) }
                    }
                    .disabled(isSaving || !hasUnsavedChanges)
                    .accessibilityIdentifier("directory.category.publish")
                }
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmation
        ) { action in
            switch action {
            case .publish:
                Button(DirectoryEditorText.value("Опублікувати", "Veröffentlichen")) {
                    confirmation = nil
                    Task { await save() }
                }
            case .discard:
                Button(DirectoryEditorText.value("Відкинути зміни", "Änderungen verwerfen"), role: .destructive) {
                    confirmation = nil
                    dismiss()
                }
            case .deleteCategory:
                Button(DirectoryEditorText.value("Видалити категорію", "Bereich löschen"), role: .destructive) {
                    confirmation = nil
                    Task { await deleteCategory() }
                }
            case let .deleteGroup(id):
                Button(DirectoryEditorText.value("Видалити підкатегорію зі статтями", "Unterbereich mit Beiträgen löschen"),
                       role: .destructive) {
                    confirmation = nil
                    DirectoryEditorDeletion.deleteGroup(id, from: &draft)
                }
            case let .deleteTopic(id):
                Button(DirectoryEditorText.value("Видалити статтю", "Beitrag löschen"), role: .destructive) {
                    confirmation = nil
                    DirectoryEditorDeletion.deleteTopic(id, from: &draft)
                }
            }
        }
        .alert(DirectoryEditorText.value("Не вдалося зберегти", "Speichern fehlgeschlagen"),
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(DirectoryEditorText.value("Гаразд", "OK")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard !isSaving, contentStore.canEdit, let actorID = authState.user?.id else { return }
        draft = DirectorySourceValidation.normalizingSources(in: draft)
        showsValidation = true
        isSaving = true
        defer { isSaving = false }
        do {
            try await contentStore.save(draft, expectedRevision: expectedRevision, actorID: actorID)
            dismiss()
        } catch {
            if let language = (error as? DirectoryManagedValidation.Failure)?.language {
                editingLanguage = language
            }
            errorMessage = message(for: error)
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .publish:
            DirectoryEditorText.value(
                "Ви перевірили факти та посилання у змінених матеріалах? Опублікувати для всіх читачів?",
                "Haben Sie Fakten und Links der geänderten Inhalte geprüft? Für alle Leser veröffentlichen?"
            )
        case .discard:
            DirectoryEditorText.value("Вийти без збереження змін?", "Änderungen verwerfen?")
        case .deleteCategory:
            DirectoryEditorText.value(
                "Видалити «\(draft.title.ukrainian)» разом з усіма статтями? Це відбудеться одразу.",
                "„\(draft.title.german)“ mit allen Beiträgen löschen? Das geschieht sofort."
            )
        case .deleteGroup:
            DirectoryEditorText.value("Видалити підкатегорію з усіма статтями? Зміна стане видимою після публікації.",
                                      "Unterbereich mit allen Beiträgen löschen? Die Änderung wird nach Veröffentlichung sichtbar.")
        case .deleteTopic:
            DirectoryEditorText.value("Видалити статтю для всіх читачів після публікації?",
                                      "Beitrag nach Veröffentlichung für alle Leser löschen?")
        case nil:
            ""
        }
    }

    private func message(for error: Error) -> String {
        let firebaseError = error as NSError
        if firebaseError.domain == FunctionsErrorDomain,
           (firebaseError.code == FunctionsErrorCode.aborted.rawValue ||
            firebaseError.code == FunctionsErrorCode.failedPrecondition.rawValue) {
            return DirectoryManagedValidation.Failure.conflict.localizedDescription
        }
        if firebaseError.domain == FunctionsErrorDomain,
           firebaseError.code == FunctionsErrorCode.permissionDenied.rawValue {
            return DirectoryManagedValidation.Failure.permissionDenied.localizedDescription
        }
        return error.localizedDescription
    }

    private func deleteCategory() async {
        guard !isSaving, contentStore.canEdit, let actorID = authState.user?.id else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await contentStore.deleteCustomCategory(draft.id,
                                                        expectedRevision: expectedRevision,
                                                        actorID: actorID)
            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

}
