import SwiftUI
import UIKit

/// Full-size device preview uses the production header, backdrop, native tab bar and
/// decoration renderer. It never queries content, changes the library or publishes.
struct SeasonalFullScreenPreview:View {
    let theme:SeasonalTheme
    @Environment(\.dismiss) private var dismiss
    @State private var selected=SeasonalSection.news
    @State private var detailSections:Set<SeasonalSection>=[]
    @State private var headerPresent=false
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var textSize
    private var effectsVisible:Bool { theme.sections.contains(selected) && verticalSize != .compact && !textSize.isAccessibilitySize }
    var body:some View {
        TabView(selection:$selected) {
            ForEach(SeasonalSection.allCases) { section in
                SeasonalPreviewPage(theme:theme,section:section,isActive:selected==section,detail:Binding(get:{detailSections.contains(section)},set:{ if $0 { detailSections.insert(section) } else { detailSections.remove(section) } }))
                    .tabItem { Label(SeasonalText.section(section),systemImage:Self.symbol(section)) }.tag(section)
            }
        }
        .overlayPreferenceValue(SeasonalHeaderAnchors.self) { anchors in
            if effectsVisible {
                SeasonalDecorationLayer(theme:theme,anchors:anchors,embedsHeaderPumpkin:true,includesChrome:!detailSections.contains(selected),hangingVisible:headerPresent)
                    .ignoresSafeArea(.container,edges:[.top,.bottom])
            }
        }
        .onPreferenceChange(SeasonalHeaderPresence.self) { headerPresent=$0 }
        .modifier(SeasonalKeepAwake(enabled:true))
        .tint(AppTheme.accentPrimaryForeground)
        .toolbarBackground(.visible,for:.tabBar)
        .overlay(alignment:.bottomTrailing) {
            Button { dismiss() } label: {
                Image(systemName:"xmark").font(.headline).foregroundStyle(.white).frame(width:44,height:44)
                    .background(AppTheme.accentPrimaryForeground,in:Circle())
            }.buttonStyle(.plain)
                .accessibilityLabel(SeasonalText.value("closePreview","Vorschau schließen"))
                .accessibilityIdentifier("seasonal.preview.close")
                .padding(.trailing,22).padding(.bottom,96)
        }
    }
    static func symbol(_ section:SeasonalSection) -> String {
        switch section {
        case .news:"newspaper.fill"
        case .events:"calendar"
        case .organizations:"building.2.fill"
        case .directory:"books.vertical.fill"
        case .profile:"person.circle.fill"
        }
    }
}

private struct SeasonalPreviewPage:View {
    let theme:SeasonalTheme
    let section:SeasonalSection
    let isActive:Bool
    @Binding var detail:Bool
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dynamicTypeSize) private var textSize
    private var enabled:Bool { isActive && theme.sections.contains(section) && verticalSize != .compact && !textSize.isAccessibilitySize }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:AppTheme.sectionSpacing) {
                    AppBrandHeader {
                        HStack(spacing:6) {
                            ForEach(["magnifyingglass","plus","bell"],id:\.self) { symbol in
                                Image(systemName:symbol).frame(width:40,height:44).foregroundStyle(AppTheme.accentPrimaryForeground)
                            }
                        }
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Text(theme.name).font(.title2.bold())
                        Text(SeasonalText.value("fullPreviewHint","Vorschau auf diesem Gerät. Es wird nichts veröffentlicht."))
                            .font(.subheadline)
                    }.foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth:.infinity,minHeight:160,alignment:.leading).padding(18)
                        .background(AppTheme.accentPrimary.opacity(0.10),in:RoundedRectangle(cornerRadius:22))
                    if !enabled { Text(SeasonalText.value("sectionNotIncluded","Für diesen Bereich sind keine Effekte ausgewählt oder die Darstellung ist reduziert."))
                        .font(.footnote).foregroundStyle(.secondary) }
                    ForEach(0..<12,id:\.self) { index in
                        Button { detail=true } label: {
                            HStack(spacing:12) {
                                Image(systemName:SeasonalFullScreenPreview.symbol(section))
                                    .font(.title2).foregroundStyle(AppTheme.accentPrimaryForeground)
                                    .frame(width:56,height:64).background(AppTheme.accentPrimary.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                                VStack(alignment:.leading,spacing:5) {
                                    Text(SeasonalText.section(section)).font(.headline).foregroundStyle(AppTheme.textPrimary)
                                    Text(SeasonalText.value("previewSample","Beispielkarte zum Prüfen von Lesbarkeit, Scrollen und Dekoration."))
                                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength:0)
                            }.padding(14).background(AppTheme.surfaceElevated,in:RoundedRectangle(cornerRadius:18))
                        }.buttonStyle(.plain).accessibilityIdentifier("seasonal.preview.card."+String(index))
                    }
                }.padding(.horizontal,AppTheme.pageHorizontal).padding(.bottom,30)
            }
            .background { AppBackgroundView() }
            .environment(\.seasonalSectionActive,isActive)
            .environment(\.seasonalHeaderActive,enabled && theme.usesHeaderDock)
            .environment(\.seasonalHeaderTheme,enabled ? theme:nil)
            .navigationDestination(isPresented:$detail) {
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        Text(SeasonalText.section(section)).font(.largeTitle.bold())
                        ForEach(0..<8,id:\.self) { _ in Text(SeasonalText.value("previewSample","Beispielkarte zum Prüfen von Lesbarkeit, Scrollen und Dekoration.")).font(.body) }
                    }.padding(AppTheme.pageHorizontal)
                }.background { AppBackgroundView() }.navigationTitle(SeasonalText.section(section))
            }
        }

    }
}
