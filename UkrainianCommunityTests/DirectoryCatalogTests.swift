import Foundation
import Testing
@testable import UkrainianCommunity

struct DirectoryCatalogTests {
    @Test func articleFormattingKeepsDatesAndNumberedStepsTogether() {
        #expect(DirectoryReadingBlocks.from("Seit 16. Januar 2026 gilt die Regel. Prüfen Sie den Antrag.") == [
            "Seit 16. Januar 2026 gilt die Regel.", "Prüfen Sie den Antrag."
        ])
        #expect(DirectoryReadingBlocks.from("1. Befund. 2. Kostenvoranschlag. 3. Antrag stellen.") == [
            "1. Befund.", "2. Kostenvoranschlag.", "3. Antrag stellen."
        ])
    }

    @Test func articleFormattingPreservesEveryLocalizedSection() {
        func check(_ text: String) {
            let original = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let rendered = DirectoryReadingBlocks.from(text).joined(separator: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(rendered == original)
        }

        for category in DirectoryCatalog.categories {
            for topic in category.topics {
                if category.id == "safety" {
                    for section in DirectorySafetyContent.guides[topic.id]?.sections ?? [] {
                        check(section.body.ukrainian)
                        check(section.body.german)
                    }
                } else {
                    for section in DirectoryGuideCatalog.guide(categoryID: category.id, topicID: topic.id)?.sections ?? [] {
                        check(section.body.ukrainian)
                        check(section.body.german)
                    }
                }
                if DirectoryRegionalContent.applies(categoryID: category.id, topicID: topic.id) {
                    for state in AustrianFederalState.allCases {
                        for section in DirectoryRegionalContent.sections(categoryID: category.id,
                                                                         topicID: topic.id, state: state) {
                            check(section.body.ukrainian)
                            check(section.body.german)
                        }
                    }
                }
            }
        }
    }

    @Test func categoriesAndTopicsHaveStableUniqueIdentifiers() {
        let categories = DirectoryCatalog.categories
        #expect(!categories.isEmpty)
        #expect(categories.reduce(0) { $0 + $1.topics.count } >= 145)
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

    @Test func searchOpensMatchingArticleInsteadOfOnlyItsCategory() {
        let matches = DirectorySearchIndex.search("Anspruchsbeleg", language: .german)
        #expect(matches.contains { $0.route == .topic(categoryID: "health", topicID: "pregnancy") })
        #expect(Set(matches.map(\.id)).count == matches.count)
        #expect(DirectorySearchIndex.search("Wohnen", language: .german).first?.route == .category("housing"))
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

    @Test func safetyGuidesHaveDistinctActionsAndSources() {
        let guides = DirectorySafetyContent.guides
        #expect(guides.count == 12)
        for (topicID, guide) in guides {
            #expect(guide.sections.count >= 3, "\(topicID) needs actionable sections")
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            #expect(Set(guide.sources.map(\.url)).count == guide.sources.count)
            for section in guide.sections {
                #expect(section.body.ukrainian.count >= 70)
                #expect(section.body.german.count >= 70)
            }
        }
    }

    @Test func firstStepsKeepTheArrivalRouteSeparateAndSourceEachAction() throws {
        let arrival = try #require(FirstStepsGuides.guide(for: "arrival"))
        let checklist = try #require(FirstStepsGuides.guide(for: "checklist"))
        #expect(arrival.sections.count == 4)
        #expect(checklist.sections.count == 8)
        #expect(Set(arrival.sections.map(\.id)).isDisjoint(with: Set(checklist.sections.map(\.id))))
        for section in arrival.sections + checklist.sections {
            #expect(section.source?.url.scheme == "https")
            #expect(section.body.ukrainian.count > 100)
            #expect(section.body.german.count > 100)
        }
    }

    @Test func registrationRoutesAreDistinctAndEveryInstructionHasAResponsibleSource() throws {
        let category = try #require(DirectoryCatalog.categories.first { $0.id == "registration" })
        #expect(category.topics.count == 7)
        #expect(!category.topics.contains { $0.id == "appointments" })
        #expect(category.topics.contains { $0.id == "registration-errors" })
        for topic in category.topics {
            let guide = try #require(RegistrationGuides.guide(for: topic.id))
            #expect(guide.sections.count >= 3)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            for section in guide.sections {
                #expect(section.source?.url.scheme == "https", "Missing direct source: \(topic.id)/\(section.id)")
                #expect(section.body.ukrainian.count > 90)
                #expect(section.body.german.count > 90)
            }
        }
    }

    @Test func regionalSafetyAddsLocalServicesWithoutRepeatingEmergencyAdvice() {
        for state in AustrianFederalState.allCases {
            for topicID in ["domestic-violence", "women", "children", "assault"] {
                let sections = DirectoryRegionalContent.sections(categoryID: "safety", topicID: topicID,
                                                                 state: state)
                #expect(sections.count == 1)
                #expect(!sections[0].body.ukrainian.contains("133"))
                #expect(!sections[0].body.ukrainian.contains("112"))
                #expect(!sections[0].body.german.contains("133"))
                #expect(!sections[0].body.german.contains("112"))
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

    @Test func publishedDirectoryTopicsHaveCompleteBilingualGuides() {
        for category in DirectoryCatalog.categories where category.id != "safety" {
            for topic in category.topics {
                let guide = DirectoryGuideCatalog.guide(categoryID: category.id, topicID: topic.id)
                #expect(guide != nil)
                #expect((guide?.sections.count ?? 0) >= 3, "\(category.id)/\(topic.id)")
                #expect(Set(guide?.sections.map(\.id) ?? []).count == guide?.sections.count)
                #expect(guide?.sources.isEmpty == false)
                #expect(guide?.cardSummary.ukrainian.isEmpty == false)
                #expect(guide?.cardSummary.german.isEmpty == false)
                for section in guide?.sections ?? [] {
                    #expect(!section.title.ukrainian.isEmpty)
                    #expect(!section.title.german.isEmpty)
                    #expect(!section.body.ukrainian.isEmpty)
                    #expect(!section.body.german.isEmpty)
                    if let source = section.source {
                        #expect(source.url.scheme == "https")
                    }
                }
                for source in guide?.sources ?? [] {
                    #expect(source.url.scheme == "https")
                    if category.id == "residence" {
                        #expect(["bmi.gv.at", "www.bmi.gv.at", "oesterreich.gv.at",
                                 "www.oesterreich.gv.at", "eausweise.oesterreich.gv.at",
                                 "www.migration.gv.at", "oead.at"].contains(source.url.host ?? ""))
                    }
                    if category.id == "citizenship" {
                        #expect(["www.oesterreich.gv.at", "www.wien.gv.at", "www.bmi.gv.at",
                                 "mfa.gov.ua", "dmsu.gov.ua", "edikte.justiz.gv.at"].contains(source.url.host ?? ""))
                    }
                    if category.id == "health" {
                        #expect(["www.gesundheit.gv.at", "www.oegk.at", "www.basg.gv.at"].contains(source.url.host ?? ""))
                    }
                }
            }
        }
    }

    @Test func everyPublishedTopicAppearsInExactlyOneBilingualGroup() {
        let completed = DirectoryCatalog.startCategories
        #expect(completed.reduce(0) { $0 + $1.topics.count } == 81)
        for category in DirectoryCatalog.categories {
            #expect(DirectoryTopicGroups.isComplete(categoryID: category.id))
            let groups = DirectoryTopicGroups.forCategory(category)
            #expect(!groups.isEmpty)
            #expect(groups.allSatisfy { !$0.title.ukrainian.isEmpty && !$0.title.german.isEmpty })
            let grouped = groups.flatMap(\.topicIDs)
            #expect(grouped.count == Set(grouped).count)
            #expect(Set(grouped) == Set(category.topics.map(\.id)))
        }
    }

    @Test func nearbyConsulatesHaveDirectOfficialLinks() {
        let guide = DocumentGuides.guide(for: "consulates-nearby")
        #expect(guide?.sections.count == 8)
        for section in guide?.sections ?? [] {
            #expect(section.source?.url.host == "mfa.gov.ua")
        }
        #expect(DocumentGuides.guide(for: "consulate-austria")?.sections.first?.source?.url.host == "mfa.gov.ua")
    }

    @Test func documentGuidesHaveTraceableSections() {
        let category = DirectoryCatalog.categories.first { $0.id == "documents" }
        #expect(category?.topics.count == 16)
        for topic in category?.topics ?? [] {
            guard let guide = DocumentGuides.guide(for: topic.id) else {
                Issue.record("Missing document guide: \(topic.id)")
                continue
            }
            #expect(!guide.sections.isEmpty)
            #expect(guide.sections.count == Set(guide.sections.map(\.id)).count)
            for section in guide.sections {
                #expect(section.source?.url.scheme == "https")
                #expect(!section.title.ukrainian.isEmpty && !section.title.german.isEmpty)
                #expect(!section.body.ukrainian.isEmpty && !section.body.german.isEmpty)
            }
        }
    }

    @Test func citizenshipGuidesCoverDistinctRoutesWithDirectSources() {
        let category = DirectoryCatalog.categories.first { $0.id == "citizenship" }
        #expect(category?.topics.count == 14)
        for topic in category?.topics ?? [] {
            guard let guide = CitizenshipGuides.guide(for: topic.id) else {
                Issue.record("Missing citizenship guide: \(topic.id)")
                continue
            }
            #expect(guide.sections.allSatisfy { $0.source?.url.scheme == "https" })
            #expect(guide.sections.count == Set(guide.sections.map(\.id)).count)
        }
        let childPaths = Set(CitizenshipGuides.guide(for: "children")?.sections.map(\.id) ?? [])
        #expect(childPaths.isSuperset(of: ["extend", "own", "adoption"]))
    }

    @Test func insuranceGuidesCoverAllTopicsWithDirectSources() {
        let topics = DirectoryCatalog.categories.first { $0.id == "insurance" }?.topics ?? []
        #expect(topics.count == 4)
        for topic in topics {
            guard let guide = InsuranceGuides.guide(for: topic.id) else {
                Issue.record("Missing insurance guide: \(topic.id)")
                continue
            }
            #expect(guide.sections.count >= 4)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            #expect(guide.sections.allSatisfy { $0.source?.url.scheme == "https" })
            #expect(guide.sections.allSatisfy { !$0.body.ukrainian.isEmpty && !$0.body.german.isEmpty })
        }
        let healthSections = InsuranceGuides.guide(for: "health-cover")?.sections.map(\.id) ?? []
        let familySections = InsuranceGuides.guide(for: "family-cover")?.sections.map(\.id) ?? []
        #expect(healthSections.contains("marginal"))
        #expect(familySections.contains("adult-child"))
    }

    @Test func workGuidesKeepEmploymentAndBusinessRoutesDistinct() {
        let topics = DirectoryCatalog.categories.first { $0.id == "work" }?.topics ?? []
        #expect(topics.count == 4)
        for topic in topics {
            guard let guide = WorkGuides.guide(for: topic.id) else {
                Issue.record("Missing work guide: \(topic.id)")
                continue
            }
            #expect(guide.sections.count >= 4)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            #expect(guide.sections.allSatisfy { $0.source?.url.scheme == "https" })
            #expect(guide.sections.allSatisfy { !$0.body.ukrainian.isEmpty && !$0.body.german.isEmpty })
        }
        let permit = WorkGuides.guide(for: "work-rights")?.sections.map(\.id) ?? []
        let employee = WorkGuides.guide(for: "employee-rights")?.sections.map(\.id) ?? []
        let business = WorkGuides.guide(for: "self-employment")?.sections.map(\.id) ?? []
        #expect(permit.contains("student") && permit.contains("registration"))
        #expect(employee.contains("ill") && employee.contains("termination") && employee.contains("mutual"))
        #expect(business.contains("svs") && business.contains("tax") && business.contains("vat"))
    }

    @Test func qualificationGuidesDistinguishAssessmentLicensingAndCourses() {
        let topics = DirectoryCatalog.categories.first { $0.id == "qualifications" }?.topics ?? []
        #expect(topics.count == 3)
        for topic in topics {
            guard let guide = QualificationGuides.guide(for: topic.id) else {
                Issue.record("Missing qualification guide: \(topic.id)")
                continue
            }
            #expect(guide.sections.count >= 4)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            #expect(guide.sections.allSatisfy { $0.source?.url.scheme == "https" })
            #expect(guide.sections.allSatisfy { !$0.body.ukrainian.isEmpty && !$0.body.german.isEmpty })
        }
        let recognition = QualificationGuides.guide(for: "recognition")?.sections.map(\.id) ?? []
        let regulated = QualificationGuides.guide(for: "regulated-professions")?.sections.map(\.id) ?? []
        let training = QualificationGuides.guide(for: "training")?.sections.map(\.id) ?? []
        #expect(recognition.contains("academic") && recognition.contains("vocational") && recognition.contains("nostrification"))
        #expect(regulated.contains("health-register"))
        #expect(training.contains("provider") && training.contains("cost"))
    }

    @Test func educationGuidesCoverAgeSpecificRoutesAndCurrentFees() {
        let topics = DirectoryCatalog.categories.first { $0.id == "education" }?.topics ?? []
        #expect(topics.count == 4)
        for topic in topics {
            guard let guide = EducationGuides.guide(for: topic.id) else {
                Issue.record("Missing education guide: \(topic.id)")
                continue
            }
            #expect(guide.sections.count >= 5)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            #expect(guide.sections.allSatisfy { $0.source?.url.scheme == "https" })
            #expect(guide.sections.allSatisfy { !$0.body.ukrainian.isEmpty && !$0.body.german.isEmpty })
        }
        let preschool = EducationGuides.guide(for: "kindergarten")?.sections.map(\.id) ?? []
        let school = EducationGuides.guide(for: "school")?.sections.map(\.id) ?? []
        let higher = EducationGuides.guide(for: "higher-education")?.sections.map(\.id) ?? []
        let language = EducationGuides.guide(for: "language")?.sections.map(\.id) ?? []
        #expect(preschool.contains("year") && preschool.contains("no-place") && preschool.contains("cost"))
        #expect(school.contains("until-18") && school.contains("summer"))
        #expect(higher.contains("preparation") && higher.contains("cost") && higher.contains("status"))
        #expect(language.contains("choice") && language.contains("certificate"))
    }

    @Test func regionalEntriesCoverEveryFederalStateWithOfficialDestinations() {
        let regionalTopics = [
            ("safety", "domestic-violence"),
            ("first-steps", "arrival"),
            ("registration", "after-registration"),
            ("residence", "temporary-protection"),
            ("citizenship", "application"),
            ("housing", "housing-support"),
            ("housing", "foreign-buyers"),
            ("health", "specialists"),
            ("health", "clinics"),
            ("health", "pregnancy"),
            ("health", "patient-rights"),
            ("social-support", "basic-support"),
            ("social-support", "benefits"),
            ("community", "local-services"),
            ("accessibility", "disability"),
            ("care", "care-services"),
            ("seniors", "seniors")
        ]
        for state in AustrianFederalState.allCases {
            for (categoryID, topicID) in regionalTopics {
                #expect(DirectoryRegionalContent.applies(categoryID: categoryID, topicID: topicID))
                let sections = DirectoryRegionalContent.sections(categoryID: categoryID, topicID: topicID,
                                                                 state: state)
                #expect(!sections.isEmpty)
                for section in sections {
                    #expect(!section.body.ukrainian.isEmpty)
                    #expect(!section.body.german.isEmpty)
                    #expect(section.source?.url.scheme == "https")
                }
            }
        }
        #expect(!DirectoryRegionalContent.applies(categoryID: "health", topicID: "child-health"))
        #expect(!DirectoryRegionalContent.applies(categoryID: "health", topicID: "doctors"))
    }

    @Test func healthArticlesUseDistinctActionsAndVerifiedRegionalNames() throws {
        let category = try #require(DirectoryCatalog.categories.first { $0.id == "health" })
        #expect(category.topics.count == 11)
        for topic in category.topics {
            let guide = try #require(HealthGuides.guide(for: topic.id))
            #expect(guide.sections.count >= 4)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            for section in guide.sections {
                #expect(section.source?.url.scheme == "https", "\(topic.id)/\(section.id)")
                #expect(section.body.ukrainian.count >= 90)
                #expect(section.body.german.count >= 90)
            }
        }
        for state in AustrianFederalState.allCases {
            for topicID in ["specialists", "clinics", "pregnancy", "patient-rights"] {
                let sections = HealthRegionalContent.sections(for: topicID, state: state)
                #expect(!sections.isEmpty)
                for section in sections {
                    if topicID != "pregnancy" || state != .wien {
                        #expect(section.body.ukrainian.contains(state.displayName))
                        #expect(section.body.german.contains(state.displayName))
                    }
                    #expect(!section.body.ukrainian.contains("state.displayName"))
                    #expect(section.source?.url.scheme == "https")
                }
            }
        }
    }

    @Test func mentalHealthArticlesHaveSeparateHelpRoutesAndOfficialSources() throws {
        let category = try #require(DirectoryCatalog.categories.first { $0.id == "mental-health" })
        #expect(Set(category.topics.map(\.id)) == ["counseling", "crisis", "children"])
        for topic in category.topics {
            let guide = try #require(MentalHealthGuides.guide(for: topic.id))
            #expect(guide.sections.count >= 4)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            for section in guide.sections {
                #expect(section.source?.url.scheme == "https", "\(topic.id)/\(section.id)")
                #expect(section.body.ukrainian.count >= 100)
                #expect(section.body.german.count >= 100)
            }
        }
        #expect(MentalHealthGuides.guide(for: "children")?.sections.contains { $0.id == "free-program" } == true)
        #expect(DirectoryRegionalContent.applies(categoryID: "mental-health", topicID: "crisis"))
        #expect(!DirectoryRegionalContent.applies(categoryID: "mental-health", topicID: "counseling"))
        #expect(!DirectoryRegionalContent.applies(categoryID: "mental-health", topicID: "children"))
    }

    @Test func residenceArticlesSourceEveryActionAndDistinguishProtectionTransition() throws {
        let category = try #require(DirectoryCatalog.categories.first { $0.id == "residence" })
        #expect(category.topics.count == 12)
        for topic in category.topics {
            let guide = try #require(ResidenceGuides.guide(for: topic.id))
            #expect(guide.sections.count >= 4)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            for section in guide.sections {
                #expect(section.source?.url.scheme == "https", "\(topic.id)/\(section.id)")
                #expect(section.body.ukrainian.count >= 90)
                #expect(section.body.german.count >= 90)
            }
        }
        let transition = try #require(ResidenceGuides.guide(for: "rwr-plus"))
        #expect(transition.sections.contains { $0.id == "cost-and-result" })
        #expect(transition.sections.contains { $0.id == "other-titles" })
        #expect(!transition.sections.contains { $0.id == "current-validity" })
    }

    @Test func housingGuidesKeepDistinctSourcedRoutes() throws {
        let category = try #require(DirectoryCatalog.categories.first { $0.id == "housing" })
        #expect(category.topics.count == 18)
        for topic in category.topics {
            let guide = try #require(HousingGuides.guide(for: topic.id))
            #expect(guide.sections.count >= 3)
            #expect(Set(guide.sections.map(\.id)).count == guide.sections.count)
            for section in guide.sections {
                #expect(section.body.ukrainian.count >= 100, "\(topic.id)/\(section.id)")
                #expect(section.body.german.count >= 100, "\(topic.id)/\(section.id)")
                #expect(section.source?.url.scheme == "https", "\(topic.id)/\(section.id)")
            }
        }
        #expect(HousingRegionalContent.applies(to: "housing-support"))
        #expect(HousingRegionalContent.applies(to: "foreign-buyers"))
        #expect(!HousingRegionalContent.applies(to: "find-rental"))
        #expect(!HousingRegionalContent.applies(to: "buying-costs"))
        for state in AustrianFederalState.allCases {
            let sections = HousingRegionalContent.sections(for: "arrival-housing", state: state)
            #expect(sections.count == 1)
            #expect(sections[0].id != "regional-care")
        }
    }
}
