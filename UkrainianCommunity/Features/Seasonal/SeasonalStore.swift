import Combine
import FirebaseFirestore
import Foundation

/// Public presentation is independent of login and never blocks the startup gate.
@MainActor final class SeasonalStore: ObservableObject {
    @Published private(set) var library = SeasonalLibrary()
    private var listener: ListenerRegistration?
    private let cacheURL: URL
    private var generation = UUID()

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("uac-seasonal-v1.json")
        if let data = try? Data(contentsOf: self.cacheURL), let cached = try? SeasonalLibrary.decode(data) {
            library = cached
        }
    }

    func start() {
        guard listener == nil else { return }
        let token = UUID(); generation = token
        listener = Firestore.firestore().document(SeasonalRepository.presentationPath)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, error == nil, let snapshot else { return }
                    // An empty offline snapshot does not invalidate a complete cached package.
                    if !snapshot.exists && snapshot.metadata.isFromCache { return }
                    do {
                        let document = try SeasonalRepository.decode(snapshot)
                        if self.library != document.library { self.library = document.library }
                        if let data = try? document.library.encoded() {
                            try? data.write(to: self.cacheURL, options: .atomic)
                        }
                    } catch {
                        // A malformed/unsupported published package must not keep an old decoration active.
                        self.library = SeasonalLibrary()
                        try? FileManager.default.removeItem(at: self.cacheURL)
                    }
                }
            }
    }

    func stop() {
        generation = UUID(); listener?.remove(); listener = nil
    }
    deinit { listener?.remove() }
}
