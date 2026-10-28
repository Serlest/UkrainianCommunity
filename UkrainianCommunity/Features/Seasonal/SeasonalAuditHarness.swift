#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import UIKit

@MainActor final class SeasonalMemoryRepository: SeasonalRepositoryProtocol {
    private var documents: [String: SeasonalDocument] = [:]
    func fetch(path: String) async throws -> SeasonalDocument { documents[path] ?? SeasonalDocument() }
    func save(_ library: SeasonalLibrary, path: String, expectedRevision: String?, userID: String) async throws -> SeasonalDocument {
        guard documents[path]?.revision == expectedRevision else { throw SeasonalError.conflict }
        let result = SeasonalDocument(library: try library.validated(), revision: UUID().uuidString)
        documents[path] = result; return result
    }
}

/// Explicit simulator fixtures. No Firestore access or device/Release availability.
struct SeasonalAuditHarness: View {
    @StateObject private var model = SeasonalManagementModel(repository: SeasonalMemoryRepository())
    @State private var selected = 0
    @State private var details = false
    @State private var effects = ProcessInfo.processInfo.environment["UITestSeasonalEffects"] != "0"
    @State private var theme = Self.fixture()
    private static func fixture() -> SeasonalTheme {
        let preset=ProcessInfo.processInfo.environment["UITestSeasonalScope"] ?? "home"
        var theme:SeasonalTheme = switch preset {
        case "gta","editor-gta": .gtaVI()
        case "christmas","editor-christmas": .christmas()
        case "newyear","editor-newyear": .newYear()
        case "legacy": .halloween()
        default: .halloweenScene()
        }
        if ProcessInfo.processInfo.environment["UITestSeasonalCustomArtwork"] == "1" {
            theme.elements[0].artwork = .image
            theme.elements[0].pngFrames = [UIColor.magenta, UIColor(red:1,green:0.1,blue:0.9,alpha:1)].map { color in
                UIGraphicsImageRenderer(size: CGSize(width:24,height:24)).image { context in
                    color.setFill();context.cgContext.fillEllipse(in:CGRect(x:2,y:2,width:20,height:20))
                }.pngData()!.base64EncodedString()
            }
        }
        return theme
    }
    private var scope: String { ProcessInfo.processInfo.environment["UITestSeasonalScope"] ?? "home" }
    var body: some View {
        Group {
            if scope == "management" {
                NavigationStack { SeasonalManagementView(model: model) }
                    .environmentObject(AuthService.shared.authState).environmentObject(SeasonalStore())
            } else if scope.hasPrefix("editor") {
                SeasonalThemeEditor(theme: theme) { theme = $0 }
            } else {
                TabView(selection: $selected) {
                    ForEach(0..<5) { index in
                        NavigationStack {
                            ScrollView {
                                VStack(spacing: 18) {
                                    AppBrandHeader {
                                        Button {} label: { Image(systemName:"bell").frame(width:44,height:44) }
                                            .accessibilityIdentifier("seasonal.fixture.bell")
                                    }
                                    Image(systemName: "mountain.2.fill").resizable().scaledToFit()
                                        .frame(height: 130).frame(maxWidth: .infinity)
                                        .foregroundStyle(.orange.gradient).background(.blue.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                    ForEach(0..<(scope == "scroll" || ProcessInfo.processInfo.environment["UITestSeasonalLongFeed"] == "1" ? 60:3),id:\.self) { _ in
                                        HStack {
                                            Image(systemName: "newspaper").font(.title)
                                            VStack(alignment: .leading) {
                                                Text(AppStrings.Tabs.home).font(.caption).foregroundStyle(.green)
                                                Text(AppStrings.Home.brandTitle).font(.headline)
                                                Text(verbatim: scope == "scroll" ? "Halloween · 31.10" : theme.name).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                                            }
                                            Spacer()
                                        }.padding().background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
                                    }
                                    NavigationLink(AppStrings.Action.open) {
                                        Text(AppStrings.Action.open).accessibilityIdentifier("seasonal.fixture.detail")
                                            .frame(maxWidth:.infinity,maxHeight:.infinity).background { AppBackgroundView() }
                                            .overlay { if effects && selected == index { SeasonalDecorationLayer(theme:theme.presentation(includesChrome:false),anchors:[:],embedsHeaderPumpkin:true).ignoresSafeArea(.container,edges:[.top,.bottom]) } }
                                    }
                                    Toggle(SeasonalText.preference, isOn: $effects).accessibilityIdentifier("seasonal.fixture.effects")
                                }.padding(.horizontal, AppTheme.pageHorizontal)
                            }
                            .background { AppBackgroundView() }
                            .environment(\.seasonalHeaderActive,effects && selected == index && theme.usesHeaderDock)
                            .environment(\.seasonalHeaderTheme,effects && selected == index ? theme:nil)
                            .overlayPreferenceValue(SeasonalHeaderAnchors.self) { anchors in
                                if effects && selected == index { SeasonalDecorationLayer(theme:theme,anchors:anchors,embedsHeaderPumpkin:true).ignoresSafeArea(.container,edges:.top) }
                            }
                        }.tabItem { Label(SeasonalText.section(SeasonalSection.allCases[index]), systemImage: "square.grid.2x2") }.tag(index)
                    }
                }
            }
        }
        .environment(\.locale, LocalizationStore.locale)
        .preferredColorScheme(AppAppearance.stored.colorScheme)
        .dynamicTypeSize(ProcessInfo.processInfo.environment["UITestSeasonalMaximum"] == "1" ? .accessibility5 : .large)
    }
}
#endif
