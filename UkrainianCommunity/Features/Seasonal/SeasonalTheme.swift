import Foundation
import ImageIO

/// Data, never downloaded executable code. Unknown versions/effects fail closed.
struct SeasonalLibrary: Codable, Equatable {
    var schemaVersion = 1
    var manualThemeID:String? = nil { didSet { if manualThemeID != nil { schemaVersion=3 } } }
    var themes: [SeasonalTheme] = [] {
        didSet { if schemaVersion == 1 && themes.contains(where: \.isComposedScene) { schemaVersion=2 } }
    }
    init(schemaVersion:Int=1,themes:[SeasonalTheme]=[],manualThemeID:String?=nil) {
        self.schemaVersion=schemaVersion == 1 && themes.contains(where: \.isComposedScene) ? 2:schemaVersion
        self.themes=themes;self.manualThemeID=manualThemeID
        if manualThemeID != nil { self.schemaVersion=3 }
    }
    private enum CodingKeys:String,CodingKey { case schemaVersion,themes,manualThemeID }
    init(from decoder:Decoder) throws {
        let container=try decoder.container(keyedBy:CodingKeys.self)
        let version=try container.decode(Int.self,forKey:.schemaVersion)
        guard (1...3).contains(version) else { throw SeasonalError.invalidPackage }
        let scenes=try container.decode([SeasonalTheme].self,forKey:.themes)
        guard version >= 2 || !scenes.contains(where: \.isComposedScene) else { throw SeasonalError.invalidPackage }
        let manual=try container.decodeIfPresent(String.self,forKey:.manualThemeID)
        guard manual == nil || version == 3 else { throw SeasonalError.invalidPackage }
        schemaVersion=version;themes=scenes;manualThemeID=manual
    }

    func validated() throws -> Self {
        guard (1...3).contains(schemaVersion), themes.count <= 12,
              (schemaVersion >= 2 || !themes.contains(where: \.isComposedScene)),
              Set(themes.map(\.id)).count == themes.count else { throw SeasonalError.invalidPackage }
        if let manualThemeID { guard schemaVersion == 3, themes.contains(where:{$0.id == manualThemeID && $0.isEnabled}), themes.filter(\.isEnabled).count == 1 else { throw SeasonalError.invalidPackage } }
        for theme in themes { try theme.validate() }
        return self
    }

    func active(at date: Date, section: SeasonalSection) -> SeasonalTheme? {
        let candidate:SeasonalTheme?
        if let manualThemeID { candidate=themes.first{$0.id == manualThemeID && $0.isEnabled} }
        else { candidate=themes.filter{$0.isEnabled && $0.contains(date)}
            .sorted{$0.priority == $1.priority ? $0.id<$1.id:$0.priority>$1.priority}.first }
        return candidate?.sections.contains(section) == true ? candidate:nil
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 240_000 else { throw SeasonalError.invalidPackage }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data).validated()
    }

    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= 240_000 else { throw SeasonalError.invalidPackage }
        return data
    }
}

enum SeasonalSection: String, Codable, CaseIterable, Identifiable {
    case news, events, organizations, directory, profile
    var id: String { rawValue }
}

enum SeasonalArtwork: String, Codable, CaseIterable, Identifiable {
    case pumpkin, web, bat, snowflake, star, pine, palm, image
    case christmasTree, viceHeader, christmasGlobe, newYearHeader, keychain, glassBauble, snowLedge, leaves, spider, sparkle
    var id: String { rawValue }
}

enum SeasonalAnchor: String, Codable, CaseIterable, Identifiable {
    case leading, trailing
    var id: String { rawValue }
}

struct SeasonalElement: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var artwork: SeasonalArtwork
    var anchor: SeasonalAnchor
    var size: Double = 30
    var sway: Double = 0.5
    var glow = false
    /// Independent from legacy web sway: the web is static; only its spiders move.
    var spiderMotion: Double? = nil
    var zone: SeasonalSceneZone? = nil
    var motionStyle: SeasonalMotionStyle? = nil
    var isEnabled: Bool? = nil
    var accentHex: String? = nil
    var accumulatesSnow:Bool? = nil

    var motionStrength: Double { motionStyle == .still ? 0 : (artwork == .web || artwork == .spider ? (spiderMotion ?? max(0.25, sway)) : sway) }
    /// Optional PNG artwork, embedded so a downloaded package works fully offline.
    /// Up to 8 small frames allow new animated artwork without an application build.
    var pngFrames: [String] = []
    var frameDuration: Double = 0.2

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 80, size.isFinite, (16...44).contains(size),
              sway.isFinite, (0...1).contains(sway), frameDuration.isFinite,
              (0.1...2).contains(frameDuration), pngFrames.count <= 8,
              (artwork == .image ? !pngFrames.isEmpty : pngFrames.isEmpty) else { throw SeasonalError.invalidPackage }
        guard !artwork.requiresSceneZone || zone != nil else { throw SeasonalError.invalidPackage }
        if let zone {
            guard zone.artworks.contains(artwork), motionStyle.map({ motionChoices.contains($0) }) ?? true else { throw SeasonalError.invalidPackage }
        } else if motionStyle != nil || isEnabled != nil || accentHex != nil { throw SeasonalError.invalidPackage }
        if accumulatesSnow != nil && artwork != .snowLedge { throw SeasonalError.invalidPackage }
        if let accentHex {
            guard accentHex.count == 6, accentHex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw SeasonalError.invalidPackage }
        }
        if let spiderMotion {
            guard (artwork == .web || artwork == .spider), spiderMotion.isFinite, (0...1).contains(spiderMotion) else { throw SeasonalError.invalidPackage }
        }
        for frame in pngFrames {
            guard let data = Data(base64Encoded: frame), data.count <= 48_000,
                  data.starts(with: [137,80,78,71,13,10,26,10]),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...256).contains(width), (1...256).contains(height) else { throw SeasonalError.invalidPackage }
        }
    }
}

struct SeasonalTheme: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var isEnabled = false
    var startsAt: Date
    var endsAt: Date
    var timeZoneID = "Europe/Vienna"
    var repeatsYearly = false
    var priority = 0
    var intensity: Double = 0.6
    var reactsToTilt = true
    var sections = SeasonalSection.allCases
    var elements: [SeasonalElement]

    var usesHeaderDock: Bool { !headerElements.isEmpty }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || name.utf8.count > 320 {
            return SeasonalText.value("nameError", "Geben Sie einen Namen mit höchstens 80 Zeichen ein.")
        }
        if endsAt <= startsAt { return SeasonalText.value("dateError", "Das Ende muss nach dem Beginn liegen.") }
        if endsAt.timeIntervalSince(startsAt) > 370 * 86_400 {
            return SeasonalText.value("durationError", "Wählen Sie einen Zeitraum von höchstens einem Jahr.")
        }
        if sections.isEmpty { return SeasonalText.value("sectionError", "Wählen Sie mindestens eine Hauptseite.") }
        if elements.filter({ $0.anchor == .leading }).count > 3 || elements.filter({ $0.anchor == .trailing }).count > 3 {
            return SeasonalText.value("positionError", "Pro Seite sind höchstens drei Dekorationen möglich.")
        }
        if elements.contains(where:{$0.artwork == .image && $0.pngFrames.isEmpty}) { return SeasonalText.value("missingImage","Wählen Sie eine PNG-Grafik für den gewählten Bereich.") }
        return (try? validate()) == nil ? SeasonalText.invalid : nil
    }

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 80, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, name.utf8.count <= 320, startsAt.timeIntervalSince1970.isFinite, endsAt.timeIntervalSince1970.isFinite,
              startsAt.timeIntervalSince1970 >= 946_684_800, endsAt.timeIntervalSince1970 <= 4_102_444_800,
              endsAt > startsAt, endsAt.timeIntervalSince(startsAt) <= 370 * 86_400,
              TimeZone(identifier: timeZoneID) != nil, (0...100).contains(priority),
              intensity.isFinite, (0.2...1).contains(intensity), !sections.isEmpty,
              Set(sections).count == sections.count, (1...6).contains(elements.count),
              Set(elements.map(\.id)).count == elements.count else { throw SeasonalError.invalidPackage }
        // Annual windows must be shorter than a local year; end is exclusive.
        if repeatsYearly {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZoneID)!
            guard let anniversary = calendar.date(byAdding: .year, value: 1, to: startsAt),
                  endsAt <= anniversary else { throw SeasonalError.invalidPackage }
        }
        guard elements.filter({ $0.anchor == .leading }).count <= 3,
              elements.filter({ $0.anchor == .trailing }).count <= 3 else { throw SeasonalError.invalidPackage }
        let slots=elements.compactMap(\.zone)
        guard slots.isEmpty || (slots.count == elements.count && Set(slots).count == slots.count) else { throw SeasonalError.invalidPackage }
        for element in elements { try element.validate() }
    }

    func contains(_ date: Date) -> Bool {
        guard endsAt > startsAt else { return false }
        if !repeatsYearly { return startsAt <= date && date < endsAt }
        guard let zone = TimeZone(identifier: timeZoneID) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let baseYear = calendar.component(.year, from: startsAt)
        let currentYear = calendar.component(.year, from: date)
        // Include previous local year for a Christmas → January window.
        for year in [currentYear - 1, currentYear] where year >= baseYear {
            let delta = year - baseYear
            guard let start = calendar.date(byAdding: .year, value: delta, to: startsAt),
                  let end = calendar.date(byAdding: .year, value: delta, to: endsAt) else { continue }
            if start <= date && date < end { return true }
        }
        return false
    }

    /// Prepared drafts only: neither enabling nor publication is implicit.
    static func gtaVI(now: Date = Date()) -> Self {
        let start=Date(timeIntervalSince1970:floor(now.timeIntervalSince1970))
        return Self(name:"GTA VI · Vice Nights",startsAt:start,endsAt:start.addingTimeInterval(14*86400),reactsToTilt:true,
             elements:[.scene(.viceHeader,.brand,size:40,motion:.glow,glow:true,accent:"FF5AB5"),
                       .scene(.palm,.corner,size:36),.scene(.keychain,.hanging,size:34,motion:.swing),
                       .scene(.palm,.edges,size:36,motion:.glow,glow:true,accent:"45E9DF"),
                       .scene(.sparkle,.atmosphere,size:18,motion:.glow,glow:true,accent:"F8AE78"),
                       .scene(.palm,.navigation,size:20)])
    }
    static func christmas(now: Date = Date()) -> Self { winter(now:now,newYear:false) }
    static func newYear(now: Date = Date()) -> Self { winter(now:now,newYear:true) }
    private static func winter(now: Date,newYear: Bool) -> Self {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Europe/Vienna")!
        var year=calendar.component(.year,from:now)
        // Opening a reusable winter draft in early January should show this winter.
        if calendar.component(.month,from:now)==1 { year -= 1 }
        let start=calendar.date(from:DateComponents(year:year,month:12,day:newYear ? 28:15))!
        let end=calendar.date(from:DateComponents(year:newYear ? year+1:year,month:newYear ? 1:12,day:newYear ? 8:28))!
        let ornaments:[SeasonalElement]=[
            .scene(newYear ? .newYearHeader:.christmasTree,.brand,size:44,motion:newYear ? .glow:.twinkle,glow:true),
            .scene(newYear ? .star:.pine,.corner,size:38,motion:.glow,glow:true),
            .scene(.glassBauble,.hanging,size:32,motion:.swing,glow:true,accent:newYear ? "FFD580":"F4C56A"),
            .scene(newYear ? .star:.pine,.edges,size:32,motion:.glow,glow:true),
            .scene(.snowflake,.atmosphere,size:18,motion:.snow,sway:0.45),
            .scene(.snowLedge,.navigation,size:28)]
        return Self(name:newYear ? "New Year · Golden Midnight":"Christmas · Warm Evergreen",startsAt:start,endsAt:end,
                    repeatsYearly:true,reactsToTilt:true,elements:ornaments)
    }

    static func halloween(now: Date = Date()) -> Self {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let year = calendar.component(.year, from: now)
        let start = calendar.date(from: DateComponents(year: year, month: 10, day: 24, hour: 0))!
        let end = calendar.date(from: DateComponents(year: year, month: 11, day: 2, hour: 0))!
        return Self(name: "Halloween", startsAt: start, endsAt: end, elements: [
            SeasonalElement(artwork: .pumpkin, anchor: .leading, size: 40, sway: 0.6, glow: true),
            SeasonalElement(artwork: .web, anchor: .trailing, size: 44, sway: 0.25),
            SeasonalElement(artwork: .bat, anchor: .trailing, size: 20, sway: 0.8)
        ])
    }
}

enum SeasonalError: Error, LocalizedError {
    case invalidPackage, conflict, ownerOnly, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidPackage: SeasonalText.invalid
        case .conflict: SeasonalText.conflict
        case .ownerOnly: SeasonalText.ownerOnly
        case .unavailable: SeasonalText.unavailable
        }
    }
}
