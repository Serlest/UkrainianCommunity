import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import UIKit
@testable import UkrainianCommunity

@MainActor final class SeasonalSDKTests: XCTestCase {
    func testActualSDKSavePublishConflictPublicReadAndAdminDenial() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Requires isolated Auth/Firestore demo transport") }
        let db = Firestore.firestore()
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              db.settings.host == "127.0.0.1:28080", !db.settings.isSSLEnabled else {
            XCTFail("Refusing non-demo transport"); return
        }
        try? Auth.auth().signOut()
        let owner = try await Auth.auth().signIn(withEmail: "legal18-sdk-owner@uac.test", password: "Emulator-Only-2026!").user
        defer { try? Auth.auth().signOut() }
        let repository = SeasonalRepository()
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SeasonalStore(cacheURL: cache)
        store.start()
        defer { store.stop(); try? FileManager.default.removeItem(at: cache) }
        let empty = try await repository.fetch(path: SeasonalRepository.libraryPath)
        XCTAssertNil(empty.revision)
        var theme = SeasonalTheme.halloween(); theme.isEnabled = true; theme.repeatsYearly = true
        let customImage = UIGraphicsImageRenderer(size: CGSize(width:24,height:24)).image { context in
            UIColor.magenta.setFill();context.cgContext.fillEllipse(in:CGRect(x:2,y:2,width:20,height:20))
        }
        theme.elements[0].artwork = .image
        let png = try XCTUnwrap(customImage.pngData()).base64EncodedString()
        theme.elements[0].pngFrames = [png,png]
        let package = SeasonalLibrary(themes: [theme, .gtaVI(), .christmas(), .newYear()])
        let saved = try await repository.save(package, path: SeasonalRepository.libraryPath, expectedRevision: nil, userID: owner.uid)
        XCTAssertEqual(saved.library, package)
        let publicBefore = try await repository.fetch(path: SeasonalRepository.presentationPath)
        XCTAssertTrue(publicBefore.library.themes.isEmpty)
        let published = try await repository.save(package, path: SeasonalRepository.presentationPath, expectedRevision: nil, userID: owner.uid)
        for _ in 0..<100 where store.library != package { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.library, package)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        let cachedPackage = try SeasonalLibrary.decode(Data(contentsOf: cache))
        XCTAssertEqual(cachedPackage, package)
        let offlineStore = SeasonalStore(cacheURL: cache)
        XCTAssertEqual(offlineStore.library.active(at: theme.startsAt, section: .news)?.id, theme.id)
        var edited = package; edited.themes[0].name = "Next year's retained theme"
        _ = try await repository.save(edited, path: SeasonalRepository.libraryPath, expectedRevision: saved.revision, userID: owner.uid)
        do {
            _ = try await repository.save(package, path: SeasonalRepository.libraryPath, expectedRevision: saved.revision, userID: owner.uid)
            XCTFail("Stale revision must reject")
        } catch SeasonalError.conflict {}
        let unaffected = try await repository.fetch(path: SeasonalRepository.presentationPath)
        XCTAssertEqual(unaffected.revision, published.revision)
        XCTAssertEqual(unaffected.library.themes[0].name, "Halloween")
        try Auth.auth().signOut()
        let anonymousRead = try await repository.fetch(path: SeasonalRepository.presentationPath)
        XCTAssertEqual(anonymousRead.library, package)
        do { _ = try await repository.fetch(path: SeasonalRepository.libraryPath); XCTFail("Private library leaked") } catch {}
        let admin = try await Auth.auth().signIn(withEmail: "support19-sdk-admin@uac.test", password: "Emulator-Only-2026!").user
        do {
            _ = try await repository.save(SeasonalLibrary(), path: SeasonalRepository.presentationPath, expectedRevision: published.revision, userID: admin.uid)
            XCTFail("Admin must not publish")
        } catch {}
        try Auth.auth().signOut()
        _ = try await Auth.auth().signIn(withEmail: "legal18-sdk-owner@uac.test", password: "Emulator-Only-2026!")
        let disabled = try await repository.save(SeasonalLibrary(), path: SeasonalRepository.presentationPath, expectedRevision: published.revision, userID: owner.uid)
        XCTAssertTrue(disabled.library.themes.isEmpty)
        for _ in 0..<100 where !store.library.themes.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(store.library.themes.isEmpty)
        let retained = try await repository.fetch(path: SeasonalRepository.libraryPath)
        XCTAssertEqual(retained.library, edited)
        // Immediate scene selection uses format 3 and retains calendar dates in private storage.
        var manual=retained.library
        for i in manual.themes.indices { manual.themes[i].isEnabled=i==2 }
        manual.manualThemeID=manual.themes[2].id
        let privateManual=try await repository.save(manual,path:SeasonalRepository.libraryPath,expectedRevision:retained.revision,userID:owner.uid)
        XCTAssertEqual(privateManual.library.schemaVersion,3)
        let liveManual=SeasonalLibrary(themes:[manual.themes[2]],manualThemeID:manual.manualThemeID)
        let appliedManual=try await repository.save(liveManual,path:SeasonalRepository.presentationPath,expectedRevision:disabled.revision,userID:owner.uid)
        for _ in 0..<100 where store.library != liveManual { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertEqual(store.library,liveManual)
        XCTAssertEqual(store.library.active(at:Date(),section:.news)?.id,manual.manualThemeID)
        _ = try await repository.save(SeasonalLibrary(),path:SeasonalRepository.presentationPath,expectedRevision:appliedManual.revision,userID:owner.uid)
        let manualRetained=try await repository.fetch(path:SeasonalRepository.libraryPath)
        XCTAssertEqual(manualRetained.library.themes.count,4)

    }
}
