import Foundation
import Testing
@testable import UkrainianCommunity

struct DirectoryCatalogTests {
    @Test func categoriesAndTopicsHaveStableUniqueIdentifiers() {
        let categories = DirectoryCatalog.categories
        #expect(!categories.isEmpty)
        #expect(categories.first?.id == "safety")
        #expect(Set(categories.map(\.id)).count == categories.count)
        for category in categories {
            #expect(!category.topics.isEmpty)
            #expect(Set(category.topics.map(\.id)).count == category.topics.count)
            #expect(!category.title.ukrainian.isEmpty)
            #expect(!category.title.german.isEmpty)
        }
    }

    @Test func searchFindsSafetyTopicsInBothLanguages() {
        let safety = DirectoryCatalog.categories.first { $0.id == "safety" }
        #expect(safety?.matches("насильство", language: .ukrainian) == true)
        #expect(safety?.matches("Gewalt", language: .german) == true)
        #expect(safety?.matches("невідомий запит", language: .ukrainian) == false)
    }

    @Test func everySafetyTopicHasBilingualStepsAndOfficialSources() {
        let topics = DirectoryCatalog.categories.first { $0.id == "safety" }?.topics ?? []
        #expect(!topics.isEmpty)
        #expect(Set(topics.map(\.id)) == Set(DirectorySafetyContent.guides.keys))
        for topic in topics {
            let guide = DirectorySafetyContent.guides[topic.id]
            #expect(guide?.sections.isEmpty == false)
            #expect(guide?.sources.isEmpty == false)
            #expect(guide?.summary.ukrainian.isEmpty == false)
            #expect(guide?.summary.german.isEmpty == false)
            for section in guide?.sections ?? [] {
                #expect(!section.body.ukrainian.isEmpty)
                #expect(!section.body.german.isEmpty)
                for contact in section.contacts {
                    #expect(contact.phoneURL.scheme == "tel")
                }
            }
            for source in guide?.sources ?? [] {
                #expect(source.url.scheme == "https")
            }
        }
    }

    @Test func previouslyCombinedSubjectsHaveSeparateDestinations() {
        let ids = Set(DirectoryCatalog.categories.map(\.id))
        for id in ["residence", "documents", "citizenship", "work", "qualifications",
                   "education", "family", "finances", "social-support", "communication",
                   "digital", "community", "leisure", "accessibility", "care", "seniors"] {
            #expect(ids.contains(id))
        }
        #expect(DirectoryCatalog.categories.first(where: { $0.id == "citizenship" })?
            .matches("Staatsbürgerschaft", language: .german) == true)
    }

    @Test func newBannerSectionDoesNotReviveRetiredGuideValue() {
        #expect(FeaturedBannerVisibleSection.supportedCases.contains(.directory))
        #expect(FeaturedBannerVisibleSection(rawValue: "guide") == .unsupportedLegacy)
        #expect(FeaturedBannerVisibleSection(rawValue: "directory") == .directory)
    }

    @Test func firstStepsRegistrationAndResidenceTopicsHaveCompleteBilingualGuides() {
        for categoryID in ["first-steps", "registration", "residence"] {
            let category = DirectoryCatalog.categories.first { $0.id == categoryID }
            #expect(category != nil)
            for topic in category?.topics ?? [] {
                let guide = DirectoryGuideCatalog.guide(categoryID: categoryID, topicID: topic.id)
                #expect(guide != nil)
                #expect(guide?.sections.isEmpty == false)
                #expect(guide?.sources.isEmpty == false)
                #expect(guide?.cardSummary.ukrainian.isEmpty == false)
                #expect(guide?.cardSummary.german.isEmpty == false)
                for section in guide?.sections ?? [] {
                    #expect(!section.title.ukrainian.isEmpty)
                    #expect(!section.title.german.isEmpty)
                    #expect(!section.body.ukrainian.isEmpty)
                    #expect(!section.body.german.isEmpty)
                }
                for source in guide?.sources ?? [] {
                    #expect(source.url.scheme == "https")
                    if categoryID == "residence" {
                        #expect(["bmi.gv.at", "www.bmi.gv.at", "oesterreich.gv.at",
                                 "www.oesterreich.gv.at", "eausweise.oesterreich.gv.at",
                                 "www.migration.gv.at"].contains(source.url.host ?? ""))
                    }
                }
            }
        }
    }
}
