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
    @Published private(set) var publicStateUnconfirmed = false
    @Published var message: String?
    private var libraryRevision: String?
    private var presentationRevision: String?
    private let repository: any SeasonalRepositoryProtocol
    private let readDeadline:RefreshRequest.Deadline
    init(repository: (any SeasonalRepositoryProtocol)? = nil,readDeadline:@escaping RefreshRequest.Deadline=RefreshRequest.continuousDeadline) { self.repository = repository ?? SeasonalRepository();self.readDeadline=readDeadline }
    private var principal: String?
    private var generation = UUID()
    var hasChanges: Bool { library != savedLibrary }
    var hasPublicationChanges: Bool { SeasonalLibrary(themes:savedLibrary.themes.filter(\.isEnabled),manualThemeID:savedLibrary.manualThemeID) != published }
    var isValid: Bool { (try? library.encoded()) != nil }

    func load(user: AppUser?) async {
        guard PermissionService.isAppOwner(user: user), let id = user?.id else {
            reset(); message = SeasonalText.ownerOnly; return
        }
        guard !isLoading && !isSaving else { return }
        principal = id; let token = generation; isLoading = true; message = nil
        defer { if generation == token { isLoading = false } }
        do {
            let (privateDocument,publicDocument)=try await RefreshRequest.run(deadline:readDeadline) { [repository] in
                async let a=repository.fetch(path:SeasonalRepository.libraryPath)
                async let b=repository.fetch(path:SeasonalRepository.presentationPath)
                return try await (a,b)
            }
            guard principal == id, generation == token else { return }
            library = privateDocument.library; savedLibrary = library
            published = publicDocument.library
            libraryRevision = privateDocument.revision; presentationRevision = publicDocument.revision
            hasLoaded = true; publicStateUnconfirmed = false
        } catch { if principal == id, generation == token { message = Self.failureMessage(error) } }
    }

    @discardableResult
    func save(user: AppUser?, publish: Bool = false, disable: Bool = false) async -> Bool {
        guard PermissionService.isAppOwner(user: user), let id = user?.id, id == principal else {
            reset(); message = SeasonalText.ownerOnly; return false
        }
        guard hasLoaded, !isSaving, !isLoading, (isValid || publish),
              (!publish || disable || !hasChanges) else { return false }
        let snapshot = publish ? (disable ? SeasonalLibrary() : SeasonalLibrary(themes:savedLibrary.themes.filter(\.isEnabled),manualThemeID:savedLibrary.manualThemeID)) : library
        let token = generation; isSaving = true; message = nil
        defer { if generation == token { isSaving = false } }
        do {
            if publish { publicStateUnconfirmed = true }
            let result = try await repository.save(snapshot,
                path: publish ? SeasonalRepository.presentationPath : SeasonalRepository.libraryPath,
                expectedRevision: publish ? presentationRevision : libraryRevision, userID: id)
            guard principal == id, generation == token else { return false }
            if publish { published = result.library; presentationRevision = result.revision; publicStateUnconfirmed = false }
            else { savedLibrary = result.library; library = result.library; libraryRevision = result.revision }
            message = disable ? SeasonalText.value("disabledNow","Saisonale Gestaltung ist ausgeschaltet."):SeasonalText.value(publish ? "published" : "saved", publish ? "Der Zeitplan wurde veröffentlicht." : "In der Bibliothek gespeichert. Noch nicht veröffentlicht.")
            return true
        } catch { if principal == id, generation == token { message = Self.failureMessage(error) }; return false }
    }

    /// Private selection is saved first; public success is reported only after verified readback.
    /// A failed public write retains the last verified snapshot but marks its live status unknown.
    @discardableResult
    func activate(_ theme:SeasonalTheme,user:AppUser?) async -> Bool {
        await applyScene(theme, user: user, includingDrafts: false)
    }

    /// One explicit action saves reviewed edits and switches the public scene.
    /// Keep the saving lease through both revision-checked writes.
    @discardableResult
    func saveAndActivate(_ theme: SeasonalTheme, user: AppUser?) async -> Bool {
        guard library.themes.contains(where: { $0.id == theme.id }) else { return false }
        return await applyScene(theme, user: user, includingDrafts: true)
    }

    private func applyScene(_ theme: SeasonalTheme, user: AppUser?, includingDrafts: Bool) async -> Bool {
        guard PermissionService.isAppOwner(user:user),let id=user?.id,id==principal,hasLoaded,
              (includingDrafts || !hasChanges),!isSaving,!isLoading else { return false }
        var next=includingDrafts ? library : savedLibrary
        if let index=next.themes.firstIndex(where:{$0.id==theme.id}) { next.themes[index]=theme }
        else { guard next.themes.count<12 else { message=SeasonalText.invalid;return false };next.themes.append(theme) }
        next.manualThemeID=nil // A temporary manual choice never destroys the calendar plan.
        guard (try? next.encoded()) != nil else { message=SeasonalText.invalid;return false }
        let token=generation;isSaving=true;message=nil
        defer { if generation==token { isSaving=false } }
        do {
            let stored = next == savedLibrary ? SeasonalDocument(library:savedLibrary,revision:libraryRevision) : try await repository.save(next,path:SeasonalRepository.libraryPath,expectedRevision:libraryRevision,userID:id)
            guard generation==token,principal==id else { return false }
            savedLibrary=stored.library;library=stored.library;libraryRevision=stored.revision
            guard var selected=stored.library.themes.first(where:{$0.id==theme.id}) else { throw SeasonalError.invalidPackage }
            selected.isEnabled=true
            let live=SeasonalLibrary(themes:[selected],manualThemeID:theme.id)
            publicStateUnconfirmed = true
            let applied=try await repository.save(live,path:SeasonalRepository.presentationPath,expectedRevision:presentationRevision,userID:id)
            guard generation==token,principal==id else { return false }
            published=applied.library;presentationRevision=applied.revision;publicStateUnconfirmed = false
            message=SeasonalText.value("activeNow","Szene ist aktiv, bis Sie sie ausschalten.")
            return true
        } catch { if generation==token,principal==id { message=Self.failureMessage(error) }; return false }
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
        generation = UUID(); isLoading = false; isSaving = false; publicStateUnconfirmed = false
        principal = nil; library = SeasonalLibrary(); savedLibrary = library; published = library
        libraryRevision = nil; presentationRevision = nil; hasLoaded = false; message = nil
    }
}
