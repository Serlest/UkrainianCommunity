import Foundation

/// Exact historical template names only. Owner-created names and stored documents are preserved.
enum SeasonalPresetKind:String,CaseIterable {
    case halloween,gta,christmas,newyear
    var controlID:String { "uac.preset."+rawValue }
    var title:String {
        SeasonalText.value([Self.halloween:"presetHalloween",.gta:"presetGTA",.christmas:"presetChristmas",.newyear:"presetNewYear"][self]!,rawValue)
    }
    var historicalNames:Set<String> {
        switch self {
        case .halloween:["Halloween","Хелловін","Хеловін","Геловін"]
        case .gta:["GTA VI · Vice Nights"]
        case .christmas:["Christmas","Weihnachten","Різдво","Christmas · Warm Evergreen"]
        case .newyear:["New Year","Neujahr","Новий рік","New Year · Golden Midnight"]
        }
    }
    static func kind(of theme:SeasonalTheme)->Self? {
        if let canonical=allCases.first(where:{$0.controlID==theme.id}) { return canonical }
        return allCases.first { $0.historicalNames.contains(theme.name.trimmingCharacters(in:.whitespacesAndNewlines)) }
    }
    static func quickScenes(defaults:[SeasonalTheme],saved:[SeasonalTheme],published:SeasonalLibrary)->[SeasonalTheme] {
        let activeID=published.manualThemeID ?? SeasonalSection.allCases.lazy.compactMap { published.active(at:.now,section:$0)?.id }.first
        let primary=zip(allCases,defaults).map { kind,fallback in
            let matches=saved.filter { $0.id==kind.controlID || Self.kind(of:$0)==kind }
            return matches.first{$0.id==activeID} ?? matches.first{$0.id==kind.controlID} ?? matches.first ?? fallback
        }
        // Historical preset copies remain in the private library, never duplicated as quick cards.
        let custom=saved.filter { theme in kind(of:theme)==nil && !primary.contains(where:{$0.id==theme.id}) }
        return (primary+custom).map(\.preparedForCurrentRenderer)
    }
}

extension SeasonalTheme {
    /// Upgrade bundled legacy templates in memory; never writes a public document implicitly.
    /// Edition 2 keeps an explicitly disabled flight disabled on subsequent loads.
    var preparedForCurrentRenderer:Self {
        if (sceneEdition ?? 0)<3,SeasonalPresetKind.kind(of:self) == .gta {
            var result=self
            for i in result.elements.indices where result.elements[i].zone == .brand && result.elements[i].artwork == .viceHeader {
                // Keep owner opt-outs and custom imagery; upgrade only the old native default.
                if result.elements[i].effectiveMotion == .glow { result.elements[i].motionStyle = .rotate }
            }
            result.sceneEdition=3
            return result
        }
        guard (sceneEdition ?? 0)<2,let kind=SeasonalPresetKind.kind(of:self),kind == .christmas || kind == .newyear else { return self }
        var result=isComposedScene ? self:arrangedInZones()
        let storedIDs=Set(elements.map(\.id))
        for i in result.elements.indices where !storedIDs.contains(result.elements[i].id) {
            result.elements[i].id=String(id.prefix(48))+".render."+(result.elements[i].zone?.rawValue ?? String(i))
        }
        if kind == .christmas {
            for i in result.elements.indices where result.elements[i].zone == .brand && result.elements[i].artwork == .christmasGlobe {
                result.elements[i].artwork = .christmasTree;result.elements[i].size=44
                result.elements[i].glow=true;result.elements[i].motionStyle = .twinkle
            }
        }
        result.celebration=kind == .christmas ? .santaFlight:.fireworks
        result.sceneEdition=2
        return result
    }

    var localizedSceneName:String {
        guard let kind=SeasonalPresetKind.kind(of:self),kind.historicalNames.contains(name.trimmingCharacters(in:.whitespacesAndNewlines)) else { return name }
        return kind.title
    }
    var quickControlID:String { SeasonalPresetKind.kind(of:self)?.controlID ?? id }
}
