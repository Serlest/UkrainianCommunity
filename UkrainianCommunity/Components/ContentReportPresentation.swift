import SwiftUI

struct ContentReportPresentationConfiguration {
    var present: (ContentReportTarget) -> Void

    static let unavailable = ContentReportPresentationConfiguration(present: { _ in })
}

private struct ContentReportPresentationConfigurationKey: EnvironmentKey {
    static let defaultValue = ContentReportPresentationConfiguration.unavailable
}

extension EnvironmentValues {
    var contentReportPresentation: ContentReportPresentationConfiguration {
        get { self[ContentReportPresentationConfigurationKey.self] }
        set { self[ContentReportPresentationConfigurationKey.self] = newValue }
    }
}

@MainActor
final class ContentReportCoordinator: ObservableObject {
    @Published var target: ContentReportTarget?
    private let repository: ContentSafetyRepository

    init(repository: ContentSafetyRepository) {
        self.repository = repository
    }

    func present(_ target: ContentReportTarget) {
        self.target = target
    }

    func dismiss() {
        target = nil
    }

    func submit(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportReceipt {
        try await repository.submitReport(target: target, reason: reason, details: details)
    }
}
