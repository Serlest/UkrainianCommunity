import Foundation
import Testing
@testable import UkrainianCommunity

struct DirectoryEditorValidationTests {
    private func category() -> DirectoryManagedCategory {
        var draft = DirectoryEditorDrafts.category(placement: .start, order: 0)
        let text = DirectoryText(ukrainian: "Текст", german: "Text")
        draft.title = text; draft.summary = text
        draft.topics[0].title = text; draft.topics[0].summary = text
        draft.topics[0].sections[0].title = text; draft.topics[0].sections[0].body = text
        draft.topics[0].sources[0] = .init(name: "Amt", url: "https://www.oesterreich.gv.at/")
        return draft
    }

    @Test func validDraftAndPreciseMissingLanguage() throws {
        var draft = category()
        _ = try DirectoryManagedValidation.validate(draft)
        draft.topics[0].title = .init(ukrainian: "Текст", german: "")
        do {
            _ = try DirectoryManagedValidation.validate(draft)
            Issue.record("Missing German title was accepted")
        } catch let error as DirectoryManagedValidation.Failure {
            #expect(error.language == .german)
            #expect(error.localizedDescription.contains(DirectoryEditorField.articleTitle.title))
        }
    }

    @Test func sourceErrorsDifferFromContentErrors() throws {
        for url in ["serlest.com", "http://serlest.com", "https://", "https://user:secret@serlest.com", "https://serlest.com/a b"] {
            #expect(DirectorySourceValidation.urlIssue(url) != nil)
        }
        #expect(DirectorySourceValidation.urlIssue("https://serlest.com/path?q=1#section") == nil)
        var draft = category()
        draft.topics[0].sources[0].url = "serlest.com"
        do {
            _ = try DirectoryManagedValidation.validate(draft)
            Issue.record("Bare domain was accepted")
        } catch let error as DirectoryManagedValidation.Failure {
            #expect(error.language == nil)
            #expect(error.localizedDescription.contains("HTTPS"))
        }
    }

    @Test func boundsMatchServerIncludingUnicodeAndOptionalHiddenContent() throws {
        #expect(DirectoryEditorField.articleTitle.issue(for: String(repeating: "a", count: 140), language: .german) == nil)
        #expect(DirectoryEditorField.articleTitle.issue(for: String(repeating: "a", count: 141), language: .german) != nil)
        #expect(DirectoryEditorField.articleTitle.issue(for: String(repeating: "😀", count: 71), language: .german) != nil)
        #expect(DirectoryEditorField.articleTitle.issue(for: "  \n", language: .german) != nil)
        var draft = category()
        draft.topics[0].isHidden = true
        draft.topics[0].summary = .init(ukrainian: "", german: "")
        draft.topics[0].sections[0].isHidden = true
        draft.topics[0].sections[0].body = .init(ukrainian: "", german: "")
        _ = try DirectoryManagedValidation.validate(draft)
    }

    @Test func visibleSectionNeedsAnExplicitOrInheritedSource() throws {
        var draft = category()
        draft.topics[0].sources = []
        #expect(throws: (any Error).self) { try DirectoryManagedValidation.validate(draft) }
        draft.topics[0].sections[0].source = .init(name: "Amt", url: "https://www.oesterreich.gv.at/")
        _ = try DirectoryManagedValidation.validate(draft)
    }
}
