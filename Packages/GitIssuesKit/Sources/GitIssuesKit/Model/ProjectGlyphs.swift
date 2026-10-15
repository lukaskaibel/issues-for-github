import Foundation

/// A glyph a project can have as its icon: an SF Symbol in outline, with a name to read out and to find it by, in one
/// of the picker's groups. It is saved by its key, which stays the same should the symbol behind it change.
public struct ProjectGlyph: Hashable, Sendable, Codable, Identifiable {
    public let key: String
    let systemName: String
    let name: LocalizedStringResource
    let group: ProjectGlyphGroup

    public var id: String { key }

    private init(_ group: ProjectGlyphGroup, _ key: String, _ systemName: String, _ name: LocalizedStringResource) {
        self.key = key
        self.systemName = systemName
        self.name = name
        self.group = group
    }

    public init?(key: String) {
        guard let glyph = Self.byKey[key] else { return nil }
        self = glyph
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    /// A glyph from a newer version of the app, chosen on another device, shows as the table here.
    public init(from decoder: Decoder) throws {
        self = Self.byKey[try decoder.singleValueContainer().decode(String.self)] ?? .table
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }

    /// GitHub's own icon for a project, which every project has until another is picked.
    public static let table = all[0]

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// Every glyph, group by group, in the picker's order. Left out are the symbols that stand for something else in
    /// the sidebar and headers (the board's columns, a list, a repository's book, the Inbox's tray, My Issues' scope,
    /// syncing's arrows), and those that draw a filled shape where the others are outlines, such as a monitor's screen.
    public static let all: [ProjectGlyph] = [
        // Work
        .init(.work, "table", "tablecells", .projectGlyphTable),
        .init(.work, "checklist", "checklist", .projectGlyphChecklist),
        .init(.work, "calendar", "calendar", .projectGlyphCalendar),
        .init(.work, "clock", "clock", .projectGlyphClock),
        .init(.work, "hourglass", "hourglass", .projectGlyphHourglass),
        .init(.work, "briefcase", "briefcase", .projectGlyphBriefcase),
        .init(.work, "folder", "folder", .projectGlyphFolder),
        .init(.work, "archive", "archivebox", .projectGlyphArchive),
        .init(.work, "document", "doc.text", .projectGlyphDocument),
        .init(.work, "documents", "doc.on.doc", .projectGlyphDocuments),
        .init(.work, "note", "note.text", .projectGlyphNote),
        .init(.work, "books", "books.vertical", .projectGlyphBooks),
        .init(.work, "openBook", "book", .projectGlyphOpenBook),
        .init(.work, "bookmark", "bookmark", .projectGlyphBookmark),
        .init(.work, "paperclip", "paperclip", .projectGlyphPaperclip),
        .init(.work, "pencil", "pencil", .projectGlyphPencil),
        .init(.work, "ruler", "pencil.and.ruler", .projectGlyphRuler),
        .init(.work, "scissors", "scissors", .projectGlyphScissors),
        .init(.work, "brush", "paintbrush.pointed", .projectGlyphBrush),
        .init(.work, "palette", "paintpalette", .projectGlyphPalette),
        .init(.work, "chart", "chart.line.uptrend.xyaxis", .projectGlyphChart),
        .init(.work, "barChart", "chart.bar", .projectGlyphBarChart),
        .init(.work, "pieChart", "chart.pie", .projectGlyphPieChart),
        .init(.work, "target", "target", .projectGlyphTarget),
        .init(.work, "pin", "pin", .projectGlyphPin),
        .init(.work, "tag", "tag", .projectGlyphTag),
        .init(.work, "link", "link", .projectGlyphLink),
        .init(.work, "lightbulb", "lightbulb", .projectGlyphLightbulb),
        .init(.work, "graduationCap", "graduationcap", .projectGlyphGraduationCap),
        .init(.work, "institution", "building.columns", .projectGlyphInstitution),
        .init(.work, "banknote", "banknote", .projectGlyphBanknote),
        .init(.work, "creditCard", "creditcard", .projectGlyphCreditCard),
        .init(.work, "cart", "cart", .projectGlyphCart),
        .init(.work, "bag", "bag", .projectGlyphBag),
        .init(.work, "gift", "gift", .projectGlyphGift),
        .init(.work, "box", "shippingbox", .projectGlyphBox),
        .init(.work, "shop", "storefront", .projectGlyphShop),
        .init(.work, "signature", "signature", .projectGlyphSignature),
        // Code
        .init(.code, "code", "chevron.left.forwardslash.chevron.right", .projectGlyphCode),
        .init(.code, "braces", "curlybraces", .projectGlyphBraces),
        .init(.code, "terminal", "terminal", .projectGlyphTerminal),
        .init(.code, "bug", "ladybug", .projectGlyphBug),
        .init(.code, "ant", "ant", .projectGlyphAnt),
        .init(.code, "hammer", "hammer", .projectGlyphHammer),
        .init(.code, "tools", "wrench.and.screwdriver", .projectGlyphTools),
        .init(.code, "wrench", "wrench.adjustable", .projectGlyphWrench),
        .init(.code, "screwdriver", "screwdriver", .projectGlyphScrewdriver),
        .init(.code, "gear", "gearshape", .projectGlyphGear),
        .init(.code, "gears", "gearshape.2", .projectGlyphGears),
        .init(.code, "chip", "cpu", .projectGlyphChip),
        .init(.code, "memory", "memorychip", .projectGlyphMemory),
        .init(.code, "server", "server.rack", .projectGlyphServer),
        .init(.code, "drive", "externaldrive", .projectGlyphDrive),
        .init(.code, "database", "cylinder", .projectGlyphDatabase),
        .init(.code, "network", "network", .projectGlyphNetwork),
        .init(.code, "antenna", "antenna.radiowaves.left.and.right", .projectGlyphAntenna),
        .init(.code, "wifi", "wifi", .projectGlyphWifi),
        .init(.code, "branch", "arrow.triangle.branch", .projectGlyphBranch),
        .init(.code, "merge", "arrow.triangle.merge", .projectGlyphMerge),
        .init(.code, "graph", "point.3.connected.trianglepath.dotted", .projectGlyphGraph),
        .init(.code, "cube", "cube", .projectGlyphCube),
        .init(.code, "layers", "square.3.layers.3d", .projectGlyphLayers),
        .init(.code, "stack", "square.stack.3d.up", .projectGlyphStack),
        .init(.code, "puzzle", "puzzlepiece", .projectGlyphPuzzle),
        .init(.code, "function", "function", .projectGlyphFunction),
        .init(.code, "command", "command", .projectGlyphCommand),
        .init(.code, "flowchart", "flowchart", .projectGlyphFlowchart),
        .init(.code, "atom", "atom", .projectGlyphAtom),
        .init(.code, "flask", "flask", .projectGlyphFlask),
        .init(.code, "testTubes", "testtube.2", .projectGlyphTestTubes),
        .init(.code, "lock", "lock", .projectGlyphLock),
        .init(.code, "key", "key", .projectGlyphKey),
        .init(.code, "shield", "shield", .projectGlyphShield),
        .init(.code, "checkShield", "checkmark.shield", .projectGlyphCheckShield),
        .init(.code, "brain", "brain", .projectGlyphBrain),
        .init(.code, "sparkles", "sparkles", .projectGlyphSparkles),
        .init(.code, "wand", "wand.and.stars", .projectGlyphWand),
        .init(.code, "cloud", "cloud", .projectGlyphCloud),
        // Devices
        .init(.devices, "phone", "iphone", .projectGlyphPhone),
        .init(.devices, "tablet", "ipad", .projectGlyphTablet),
        .init(.devices, "laptop", "laptopcomputer", .projectGlyphLaptop),
        .init(.devices, "watch", "applewatch", .projectGlyphWatch),
        .init(.devices, "headphones", "headphones", .projectGlyphHeadphones),
        .init(.devices, "printer", "printer", .projectGlyphPrinter),
        .init(.devices, "camera", "camera", .projectGlyphCamera),
        .init(.devices, "videoCamera", "video", .projectGlyphVideoCamera),
        .init(.devices, "microphone", "mic", .projectGlyphMicrophone),
        .init(.devices, "speaker", "speaker.wave.2", .projectGlyphSpeaker),
        .init(.devices, "gameController", "gamecontroller", .projectGlyphGameController),
        .init(.devices, "keyboard", "keyboard", .projectGlyphKeyboard),
        .init(.devices, "mouse", "computermouse", .projectGlyphMouse),
        .init(.devices, "plug", "powerplug", .projectGlyphPlug),
        .init(.devices, "battery", "battery.75percent", .projectGlyphBattery),
        .init(.devices, "lamp", "lamp.desk", .projectGlyphLamp),
        .init(.devices, "radio", "radio", .projectGlyphRadio),
        // People and Messages
        .init(.communication, "speechBubble", "bubble.left", .projectGlyphSpeechBubble),
        .init(.communication, "conversation", "bubble.left.and.bubble.right", .projectGlyphConversation),
        .init(.communication, "quote", "quote.bubble", .projectGlyphQuote),
        .init(.communication, "envelope", "envelope", .projectGlyphEnvelope),
        .init(.communication, "paperPlane", "paperplane", .projectGlyphPaperPlane),
        .init(.communication, "telephone", "phone", .projectGlyphTelephone),
        .init(.communication, "megaphone", "megaphone", .projectGlyphMegaphone),
        .init(.communication, "bell", "bell", .projectGlyphBell),
        .init(.communication, "at", "at", .projectGlyphAt),
        .init(.communication, "newspaper", "newspaper", .projectGlyphNewspaper),
        .init(.communication, "waveHand", "hand.wave", .projectGlyphWaveHand),
        .init(.communication, "thumbsUp", "hand.thumbsup", .projectGlyphThumbsUp),
        .init(.communication, "clap", "hands.clap", .projectGlyphClap),
        .init(.communication, "raisedHand", "hand.raised", .projectGlyphRaisedHand),
        .init(.communication, "eye", "eye", .projectGlyphEye),
        .init(.communication, "person", "person", .projectGlyphPerson),
        .init(.communication, "people", "person.2", .projectGlyphPeople),
        .init(.communication, "group", "person.3", .projectGlyphTeam),
        .init(.communication, "walking", "figure.walk", .projectGlyphWalking),
        // Places
        .init(.places, "house", "house", .projectGlyphHouse),
        .init(.places, "building", "building.2", .projectGlyphBuilding),
        .init(.places, "tent", "tent", .projectGlyphTent),
        .init(.places, "mountain", "mountain.2", .projectGlyphMountain),
        .init(.places, "map", "map", .projectGlyphMap),
        .init(.places, "globe", "globe", .projectGlyphGlobe),
        .init(.places, "mapPin", "mappin.and.ellipse", .projectGlyphMapPin),
        .init(.places, "signpost", "signpost.right", .projectGlyphSignpost),
        .init(.places, "location", "location", .projectGlyphLocation),
        .init(.places, "bed", "bed.double", .projectGlyphBed),
        .init(.places, "sofa", "sofa", .projectGlyphSofa),
        .init(.places, "door", "door.left.hand.open", .projectGlyphDoor),
        .init(.places, "stairs", "stairs", .projectGlyphStairs),
        // Travel
        .init(.travel, "airplane", "airplane", .projectGlyphAirplane),
        .init(.travel, "car", "car", .projectGlyphCar),
        .init(.travel, "bus", "bus", .projectGlyphBus),
        .init(.travel, "tram", "tram", .projectGlyphTram),
        .init(.travel, "train", "lightrail", .projectGlyphTrain),
        .init(.travel, "bicycle", "bicycle", .projectGlyphBicycle),
        .init(.travel, "scooter", "scooter", .projectGlyphScooter),
        .init(.travel, "sailboat", "sailboat", .projectGlyphSailboat),
        .init(.travel, "ferry", "ferry", .projectGlyphFerry),
        .init(.travel, "fuel", "fuelpump", .projectGlyphFuel),
        .init(.travel, "suitcase", "suitcase", .projectGlyphSuitcase),
        .init(.travel, "ticket", "ticket", .projectGlyphTicket),
        .init(.travel, "binoculars", "binoculars", .projectGlyphBinoculars),
        .init(.travel, "road", "road.lanes", .projectGlyphRoad),
        .init(.travel, "truck", "truck.box", .projectGlyphTruck),
        .init(.travel, "motorcycle", "motorcycle", .projectGlyphMotorcycle),
        .init(.travel, "backpack", "backpack", .projectGlyphBackpack),
        .init(.travel, "beachUmbrella", "beach.umbrella", .projectGlyphBeachUmbrella),
        // Nature
        .init(.nature, "leaf", "leaf", .projectGlyphLeaf),
        .init(.nature, "tree", "tree", .projectGlyphTree),
        .init(.nature, "sun", "sun.max", .projectGlyphSun),
        .init(.nature, "sunrise", "sun.horizon", .projectGlyphSunrise),
        .init(.nature, "moon", "moon", .projectGlyphMoon),
        .init(.nature, "moonStars", "moon.stars", .projectGlyphMoonStars),
        .init(.nature, "rain", "cloud.rain", .projectGlyphRain),
        .init(.nature, "storm", "cloud.bolt", .projectGlyphStorm),
        .init(.nature, "snowflake", "snowflake", .projectGlyphSnowflake),
        .init(.nature, "wind", "wind", .projectGlyphWind),
        .init(.nature, "drop", "drop", .projectGlyphDrop),
        .init(.nature, "flame", "flame", .projectGlyphFlame),
        .init(.nature, "rainbow", "rainbow", .projectGlyphRainbow),
        .init(.nature, "tornado", "tornado", .projectGlyphTornado),
        .init(.nature, "thermometer", "thermometer.medium", .projectGlyphThermometer),
        .init(.nature, "waves", "water.waves", .projectGlyphWaves),
        .init(.nature, "umbrella", "umbrella", .projectGlyphUmbrella),
        .init(.nature, "recycling", "leaf.arrow.triangle.circlepath", .projectGlyphRecycling),
        // Animals
        .init(.animals, "paw", "pawprint", .projectGlyphPaw),
        .init(.animals, "hare", "hare", .projectGlyphHare),
        .init(.animals, "tortoise", "tortoise", .projectGlyphTortoise),
        .init(.animals, "bird", "bird", .projectGlyphBird),
        .init(.animals, "fish", "fish", .projectGlyphFish),
        .init(.animals, "cat", "cat", .projectGlyphCat),
        .init(.animals, "dog", "dog", .projectGlyphDog),
        .init(.animals, "lizard", "lizard", .projectGlyphLizard),
        .init(.animals, "teddyBear", "teddybear", .projectGlyphTeddyBear),
        // Food and Drink
        .init(.food, "forkKnife", "fork.knife", .projectGlyphForkKnife),
        .init(.food, "cup", "cup.and.saucer", .projectGlyphCup),
        .init(.food, "mug", "mug", .projectGlyphMug),
        .init(.food, "wineGlass", "wineglass", .projectGlyphWineGlass),
        .init(.food, "cake", "birthday.cake", .projectGlyphCake),
        .init(.food, "carrot", "carrot", .projectGlyphCarrot),
        .init(.food, "takeaway", "takeoutbag.and.cup.and.straw", .projectGlyphTakeaway),
        .init(.food, "popcorn", "popcorn", .projectGlyphPopcorn),
        .init(.food, "fryingPan", "frying.pan", .projectGlyphFryingPan),
        .init(.food, "fridge", "refrigerator", .projectGlyphFridge),
        .init(.food, "basket", "basket", .projectGlyphBasket),
        // Sports and Leisure
        .init(.leisure, "dice", "dice", .projectGlyphDice),
        .init(.leisure, "music", "music.note", .projectGlyphMusic),
        .init(.leisure, "guitars", "guitars", .projectGlyphGuitars),
        .init(.leisure, "piano", "pianokeys", .projectGlyphPiano),
        .init(.leisure, "film", "film", .projectGlyphFilm),
        .init(.leisure, "theater", "theatermasks", .projectGlyphTheater),
        .init(.leisure, "photo", "photo", .projectGlyphPhoto),
        .init(.leisure, "clapperboard", "movieclapper", .projectGlyphClapperboard),
        .init(.leisure, "tshirt", "tshirt", .projectGlyphTshirt),
        .init(.leisure, "trophy", "trophy", .projectGlyphTrophy),
        .init(.leisure, "medal", "medal", .projectGlyphMedal),
        .init(.leisure, "rosette", "rosette", .projectGlyphRosette),
        .init(.leisure, "crown", "crown", .projectGlyphCrown),
        .init(.leisure, "balloon", "balloon", .projectGlyphBalloon),
        .init(.leisure, "partyPopper", "party.popper", .projectGlyphPartyPopper),
        .init(.leisure, "football", "soccerball", .projectGlyphFootball),
        .init(.leisure, "basketball", "basketball", .projectGlyphBasketball),
        .init(.leisure, "tennis", "tennisball", .projectGlyphTennis),
        .init(.leisure, "americanFootball", "football", .projectGlyphAmericanFootball),
        .init(.leisure, "baseball", "baseball", .projectGlyphBaseball),
        .init(.leisure, "volleyball", "volleyball", .projectGlyphVolleyball),
        .init(.leisure, "dumbbell", "dumbbell", .projectGlyphDumbbell),
        .init(.leisure, "skateboard", "skateboard", .projectGlyphSkateboard),
        .init(.leisure, "runner", "figure.run", .projectGlyphRunner),
        .init(.leisure, "hiker", "figure.hiking", .projectGlyphHiker),
        .init(.leisure, "swimmer", "figure.pool.swim", .projectGlyphSwimmer),
        .init(.leisure, "cyclist", "figure.outdoor.cycle", .projectGlyphCyclist),
        .init(.leisure, "yoga", "figure.yoga", .projectGlyphYoga),
        .init(.leisure, "dancers", "figure.socialdance", .projectGlyphDancers),
        .init(.leisure, "skier", "figure.skiing.downhill", .projectGlyphSkier),
        .init(.leisure, "checkeredFlag", "flag.checkered", .projectGlyphCheckeredFlag),
        .init(.leisure, "stopwatch", "stopwatch", .projectGlyphStopwatch),
        .init(.leisure, "club", "suit.club", .projectGlyphClub),
        .init(.leisure, "spade", "suit.spade", .projectGlyphSpade),
        // Health
        .init(.health, "heart", "heart", .projectGlyphHeart),
        .init(.health, "heartbeat", "waveform.path.ecg", .projectGlyphHeartbeat),
        .init(.health, "firstAid", "cross.case", .projectGlyphFirstAid),
        .init(.health, "stethoscope", "stethoscope", .projectGlyphStethoscope),
        .init(.health, "pills", "pills", .projectGlyphPills),
        .init(.health, "syringe", "syringe", .projectGlyphSyringe),
        .init(.health, "bandage", "bandage", .projectGlyphBandage),
        .init(.health, "lungs", "lungs", .projectGlyphLungs),
        .init(.health, "starOfLife", "staroflife", .projectGlyphStarOfLife),
        // Shapes and Symbols
        .init(.symbols, "star", "star", .projectGlyphStar),
        .init(.symbols, "flag", "flag", .projectGlyphFlag),
        .init(.symbols, "bolt", "bolt", .projectGlyphBolt),
        .init(.symbols, "circle", "circle", .projectGlyphCircle),
        .init(.symbols, "square", "square", .projectGlyphSquare),
        .init(.symbols, "triangle", "triangle", .projectGlyphTriangle),
        .init(.symbols, "diamond", "diamond", .projectGlyphDiamond),
        .init(.symbols, "hexagon", "hexagon", .projectGlyphHexagon),
        .init(.symbols, "octagon", "octagon", .projectGlyphOctagon),
        .init(.symbols, "pentagon", "pentagon", .projectGlyphPentagon),
        .init(.symbols, "seal", "seal", .projectGlyphSeal),
        .init(.symbols, "capsule", "capsule", .projectGlyphCapsule),
        .init(.symbols, "burst", "burst", .projectGlyphBurst),
        .init(.symbols, "infinity", "infinity", .projectGlyphInfinity),
        .init(.symbols, "questionMark", "questionmark.circle", .projectGlyphQuestionMark),
        .init(.symbols, "warning", "exclamationmark.triangle", .projectGlyphWarning),
        .init(.symbols, "check", "checkmark.circle", .projectGlyphCheck),
        .init(.symbols, "plus", "plus.circle", .projectGlyphPlus),
        .init(.symbols, "smiley", "face.smiling", .projectGlyphSmiley),
        .init(.symbols, "peace", "peacesign", .projectGlyphPeace),
        .init(.symbols, "grid", "square.grid.2x2", .projectGlyphGrid),
        .init(.symbols, "dotGrid", "circle.grid.3x3", .projectGlyphDotGrid),
        .init(.symbols, "hexGrid", "circle.hexagongrid", .projectGlyphHexGrid),
        .init(.symbols, "arrow", "arrow.up.right", .projectGlyphArrow),
        .init(.symbols, "repeat", "repeat", .projectGlyphRepeat),
        .init(.symbols, "shuffle", "shuffle", .projectGlyphShuffle),
        .init(.symbols, "percent", "percent", .projectGlyphPercent),
        .init(.symbols, "number", "number", .projectGlyphNumber),
        .init(.symbols, "dollar", "dollarsign", .projectGlyphDollar),
        .init(.symbols, "euro", "eurosign", .projectGlyphEuro),
        .init(.symbols, "asterisk", "asterisk", .projectGlyphAsterisk),
    ]
}

/// The groups the picker shows the glyphs in, in its order.
enum ProjectGlyphGroup: CaseIterable, Sendable {
    case work, code, devices, communication, places, travel, nature, animals, food, leisure, health, symbols

    var title: LocalizedStringResource {
        switch self {
        case .work: .projectGlyphGroupWork
        case .code: .projectGlyphGroupCode
        case .devices: .projectGlyphGroupDevices
        case .communication: .projectGlyphGroupCommunication
        case .places: .projectGlyphGroupPlaces
        case .travel: .projectGlyphGroupTravel
        case .nature: .projectGlyphGroupNature
        case .animals: .projectGlyphGroupAnimals
        case .food: .projectGlyphGroupFood
        case .leisure: .projectGlyphGroupLeisure
        case .health: .projectGlyphGroupHealth
        case .symbols: .projectGlyphGroupSymbols
        }
    }

    var glyphs: [ProjectGlyph] {
        ProjectGlyph.all.filter { $0.group == self }
    }
}

extension ProjectGlyph {
    /// The glyphs whose name, or whose group's name, has the text in it, in the app's language or in English, so
    /// "sport" finds every ball and "Pfote" the paw print.
    static func matching(_ query: String) -> [ProjectGlyph] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return all }
        return all.filter { glyph in
            searchTerms[glyph.key, default: []].contains { $0.localizedStandardContains(text) }
        }
    }

    /// Each glyph's words to find it by, worked out once: its name and its group's, in both languages.
    private static let searchTerms: [String: [String]] = Dictionary(uniqueKeysWithValues: all.map { glyph in
        (glyph.key, [glyph.name, glyph.group.title].flatMap { resource in
            var english = resource
            english.locale = Locale(identifier: "en")
            return [String(localized: resource), String(localized: english)]
        })
    })
}
