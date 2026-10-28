import Combine
import Foundation
import FirebaseFirestore

@MainActor final class SeasonalManagementModel: ObservableObject {
    @Published var library = SeasonalLibrary()
    @Published private(set) var savedLibrary = SeasonalLibrary()
    @Published private(set) var published = SeasonalLibrary()
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoaded = false
    @Published var message: String?
    private var libraryRevision: String?
    private var presentationRevision: String?
    private let repository: any SeasonalRepositoryProtocol
    init(repository: any SeasonalRepositoryProtocol = SeasonalRepository()) { self.repository = repository }
    private var principal: String?
    private var generation = UUID()
    var hasChanges: Bool { library != savedLibrary }
    var hasPublicationChanges: Bool { SeasonalLibrary(themes: savedLibrary.themes.filter(\.isEnabled)) != published }
    var isValid: Bool { (try? library.encoded()) != nil }

    func load(user: AppUser?) async {
        guard PermissionService.isAppOwner(user: user), let id = user?.id else {
            reset(); message = SeasonalText.ownerOnly; return
        }
        guard !isLoading && !isSaving else { return }
        principal = id; let token = generation; isLoading = true; message = nil
        defer { if generation == token { isLoading = false } }
        do {
            async let libraryResult = repository.fetch(path: SeasonalRepository.libraryPath)
            async let publicResult = repository.fetch(path: SeasonalRepository.presentationPath)
            let (privateDocument, publicDocument) = try await (libraryResult, publicResult)
            guard principal == id, generation == token else { return }
            library = privateDocument.library; savedLibrary = library
            published = publicDocument.library
            libraryRevision = privateDocument.revision; presentationRevision = publicDocument.revision
            hasLoaded = true
        } catch { if principal == id, generation == token { message = Self.failureMessage(error) } }
    }

    func save(user: AppUser?, publish: Bool = false, disable: Bool = false) async {
        guard PermissionService.isAppOwner(user: user), let id = user?.id, id == principal else {
            reset(); message = SeasonalText.ownerOnly; return
        }
        guard hasLoaded, !isSaving, !isLoading, (isValid || publish),
              (!publish || disable || !hasChanges) else { return }
        let snapshot = publish ? (disable ? SeasonalLibrary() : SeasonalLibrary(themes: savedLibrary.themes.filter(\.isEnabled))) : library
        let token = generation; isSaving = true; message = nil
        defer { if generation == token { isSaving = false } }
        do {
            let result = try await repository.save(snapshot,
                path: publish ? SeasonalRepository.presentationPath : SeasonalRepository.libraryPath,
                expectedRevision: publish ? presentationRevision : libraryRevision, userID: id)
            guard principal == id, generation == token else { return }
            if publish { published = result.library; presentationRevision = result.revision }
            else { savedLibrary = result.library; library = result.library; libraryRevision = result.revision }
            message = SeasonalText.value(publish ? "published" : "saved", publish ? "Der Zeitplan wurde veröffentlicht." : "In der Bibliothek gespeichert. Noch nicht veröffentlicht.")
        } catch { if principal == id, generation == token { message = Self.failureMessage(error) } }
    }

    static func failureMessage(_ error: Error) -> String {
        if let seasonal = error as? SeasonalError { return seasonal.localizedDescription }
        let failure = error as NSError
        if failure.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: failure.code),
           code == .permissionDenied || code == .unauthenticated { return SeasonalText.ownerOnly }
        return SeasonalText.unavailable
    }

    func reset() {
        generation = UUID(); isLoading = false; isSaving = false
        principal = nil; library = SeasonalLibrary(); savedLibrary = library; published = library
        libraryRevision = nil; presentationRevision = nil; hasLoaded = false; message = nil
    }
}
