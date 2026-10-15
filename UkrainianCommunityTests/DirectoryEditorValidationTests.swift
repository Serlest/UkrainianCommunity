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
        for url in ["https://", "https://user:secret@serlest.com", "https://serlest.com/a b"] {
            #expect(DirectorySourceValidation.urlIssue(url) != nil)
        }
        #expect(DirectorySourceValidation.urlIssue("https://serlest.com/path?q=1#section") == nil)
        var draft = category()
        draft.topics[0].sources[0].url = "javascript:alert(1)"
        do {
            _ = try DirectoryManagedValidation.validate(draft)
            Issue.record("Unsafe scheme was accepted")
        } catch let error as DirectoryManagedValidation.Failure {
            #expect(error.language == nil)
            #expect(error.localizedDescription.contains("HTTPS"))
        }
    }

    @Test func sourceInputNormalizesWithoutLosingPathQueryOrFragment() {
        let cases = [
            ("serlest.com", "https://serlest.com"),
            ("  serlest.com/path?q=1#section \n", "https://serlest.com/path?q=1#section"),
            ("http://serlest.com/path?x=1", "https://serlest.com/path?x=1"),
            ("HTTP://serlest.com:80/a%20b?q=%2F#part", "https://serlest.com/a%20b?q=%2F#part"),
            ("https://serlest.com/a%20b?q=%2F#part", "https://serlest.com/a%20b?q=%2F#part"),
            ("serlest.com:8443/a?next=https://other.example/path", "https://serlest.com:8443/a?next=https://other.example/path"),
            ("https://localhost/path", "https://localhost/path"),
            ("http://127.0.0.1:8080/path", "https://127.0.0.1:8080/path"),
            ("https://[::1]/path", "https://[::1]/path")
        ]
        for (input, expected) in cases {
            #expect(DirectorySourceValidation.normalizedURL(input) == expected)
            #expect(DirectorySourceValidation.urlIssue(input) == nil)
            #expect(DirectorySourceValidation.normalizedURL(expected) == expected)
        }
    }

    @Test func unsafeAndMalformedSourcesStayInvalid() {
        for input in ["", " \n", "https://", "https:///path", "/relative", "//serlest.com", "javascript:alert(1)",
                      "javascript:80", "mailto:a@serlest.com", "ftp://serlest.com", "file:///etc/passwd",
                      "https:serlest.com", "https://user:password@serlest.com", "user@serlest.com",
                      "https://serlest.com/a b", "serlest.com/\npath", "serlest.com/\u{0}path",
                      "serlest.com\\@evil.com", "serlest.com/%zz", "serlest.com/%2",
                      "https://serlest.com:65536/path"] {
            #expect(DirectorySourceValidation.normalizedURL(input) == nil, "Accepted: \(input)")
            #expect(DirectorySourceValidation.urlIssue(input) != nil)
        }
    }

    @Test func encodedPayloadNormalizesAllSourceLocationsAndDetectsCanonicalDuplicates() throws {
        var draft = category()
        draft.topics[0].sources[0].url = "serlest.com/article?q=1"
        draft.topics[0].sections[0].source = .init(name: "Amt", url: "http://serlest.com/block#section")
        var regional = draft.topics[0].sections[0]
        regional.source?.url = "serlest.com/region?lang=de"
        draft.topics[0].regionalSections[AustrianFederalState.wien.rawValue] = [regional]
        let data = try DirectoryManagedValidation.validate(draft)
        let saved = try JSONDecoder().decode(DirectoryManagedCategory.self, from: data)
        #expect(saved.topics[0].sources[0].url == "https://serlest.com/article?q=1")
        #expect(saved.topics[0].sections[0].source?.url == "https://serlest.com/block#section")
        #expect(saved.topics[0].regionalSections[AustrianFederalState.wien.rawValue]?[0].source?.url == "https://serlest.com/region?lang=de")
        #expect(draft.topics[0].sources[0].url == "serlest.com/article?q=1")
        draft.topics[0].sources.append(.init(name: "Amt", url: "http://serlest.com/article?q=1"))
        #expect(throws: (any Error).self) { try DirectoryManagedValidation.validate(draft) }
    }

    @Test func sourceLimitAppliesAfterAddingHTTPS() {
        let prefix = "serlest.com/"
        let input = prefix + String(repeating: "a", count: DirectorySourceValidation.urlLimit - 8 - prefix.count)
        #expect(DirectorySourceValidation.urlIssue(input) == nil)
        #expect(DirectorySourceValidation.normalizedURL(input)?.utf16.count == DirectorySourceValidation.urlLimit)
        #expect(DirectorySourceValidation.urlIssue(input + "a") != nil)
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
