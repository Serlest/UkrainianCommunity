import Foundation

extension MockContentBuilder {
    nonisolated static func feedbackFixtures() -> [FeedbackItem] {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestFeedbackInbox"] == "1" else { return [] }
        if ProcessInfo.processInfo.environment["UITestFeedbackAudit"] == "1" {
            return feedbackAuditFixtures()
        }
        return [FeedbackItem(
            id: "directory-feedback-fixture", type: .report,
            subject: "Довідник · неточність · registration", message: "Feedback navigation fixture",
            status: .open, createdAt: .now, updatedAt: .now,
            userId: currentUser().id, userDisplayName: "Olena", ownerReply: nil,
            repliedAt: nil, repliedByUserId: nil, lastMessageText: nil,
            lastMessageAt: nil, lastMessageByUserId: nil, lastMessageByRole: nil,
            unreadForOwner: false, unreadForUser: false,
            reportContext: ProcessInfo.processInfo.environment["UITestFeedbackReportContext"] == "1" ? .init(
                targetType: .news, targetId: "news-1", parentType: nil, parentId: nil, targetAuthorId: nil,
                targetTitle: newsPosts()[0].title, targetExcerpt: "Full reported article context", reason: .spam, isUrgent: false,
                slaDueAt: .now.addingTimeInterval(86_400)) : nil
        )]
    }

    nonisolated private static func feedbackAuditFixtures() -> [FeedbackItem] {
        let now = Date()
        let userID = profileRoleFixture()?.id ?? currentUser().id
        func item(_ id: String, status: FeedbackStatus = .open, dsa: String? = nil, index: Int = 0) -> FeedbackItem {
            let decision = DsaDecisionSummary(outcome: "noAction", factsAndCircumstances: "Перевірені обставини / Geprüfte Umstände",
                legalBasis: nil, termsBasis: "Community rules", territorialScope: "Austria", duration: "Permanent",
                redressInformation: "Внутрішня апеляція / Interne Beschwerde", automationUsed: false,
                decidedAt: now, appealDeadline: now.addingTimeInterval(86_400))
            return FeedbackItem(id: id, type: dsa == nil ? .question : .report,
                subject: "Довідник · реєстрація проживання / Ratgeber · Wohnsitzanmeldung · \(index)",
                message: "Потрібно уточнити порядок подання документів. Bitte prüfen Sie die Angaben und die zuständige Stelle.",
                status: status, createdAt: now.addingTimeInterval(-Double(index)), updatedAt: now.addingTimeInterval(-Double(index)),
                userId: userID, userDisplayName: "Олена Марія Коваль / Olena Maria Kowal", ownerReply: nil,
                repliedAt: nil, repliedByUserId: nil, lastMessageText: nil, lastMessageAt: nil,
                lastMessageByUserId: nil, lastMessageByRole: nil, unreadForOwner: true, unreadForUser: false,
                reportContext: dsa == nil ? nil : .init(targetType: .news, targetId: "news-1", parentType: nil, parentId: nil,
                    targetAuthorId: "author-fixture", targetTitle: "Перевірка повідомленого матеріалу / Gemeldeter Inhalt",
                    targetExcerpt: "Повний контекст матеріалу / Vollständiger Kontext", reason: .privacy,
                    isUrgent: true, slaDueAt: now.addingTimeInterval(3600)),
                dsaCase: dsa.map { .init(caseNumber: "UC-AUDIT-\(id)", status: $0, category: "privacy",
                    exactLocation: "https://uac.example.test/news/news-1", illegalExplanation: "Пояснення обставин для перевірки / Sachverhalt zur Prüfung",
                    legalBasis: nil, evidence: "Скріншот / Bildschirmaufnahme", goodFaithConfirmed: true,
                    acknowledgementAt: now, preferredLanguage: "uk", decision: $0 == "open" ? nil : decision,
                    appeal: $0 == "appealed" ? .init(status: "pending", reason: "Додаткові факти / Ergänzende Tatsachen", outcome: nil) : nil) },
                revision: "1000:0")
        }
        var values = [item("feedback-audit-ordinary"), item("feedback-audit-dsa", dsa: "open", index: 1),
                      item("feedback-audit-review", dsa: "appealed", index: 2),
                      item("feedback-audit-closed", status: .closed, dsa: "decided", index: 3)]
        values += (4..<77).map { item("feedback-audit-\($0)", status: $0.isMultiple(of: 3) ? .answered : .open, index: $0) }
        return values
    }
}
