import Foundation

/// What a status column means, inferred from its name, since GitHub only stores a free-form label.
public enum StatusCategory: Int, Sendable, Comparable {
    case backlog
    case unstarted
    case started
    case completed
    case canceled

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Reads English and the languages the app is translated into, so a German board's "Erledigt" closes issues
    /// as "Done" does.
    public static func infer(from name: String) -> StatusCategory {
        cache.value(for: name) {
            let n = name.lowercased()
            func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
            let words = NameWords(name)
            if let category = StatusWords.exceptions.first(where: { words.has([$0.words]) })?.category { return category }
            if has("cancel", "won't", "wont", "not planned", "duplicate", "rejected", "dropped", "abandon")
                || words.has(StatusWords.canceled) { return .canceled }
            if has("done", "complete", "closed", "shipped", "released", "merged", "finished", "resolved", "live")
                || words.has(StatusWords.completed) { return .completed }
            if has("progress", "review", "doing", "wip", "testing", "blocked", "active")
                || words.has(StatusWords.started) { return .started }
            if has("backlog", "icebox", "later", "someday", "triage", "inbox", "ideas", "no status")
                || words.has(StatusWords.backlog) { return .backlog }
            if has("todo", "to do", "to-do", "open", "up next", "next", "ready", "planned", "new", "not started", "queued")
                || words.has(StatusWords.unstarted) { return .unstarted }
            return .started
        }
    }

    private static let cache = InferenceCache<StatusCategory>()

    public var isClosed: Bool { self == .completed || self == .canceled }

    /// The close reason GitHub should record when a card lands in a column of this kind.
    public var closeReason: String? {
        switch self {
        case .completed: "COMPLETED"
        case .canceled: "NOT_PLANNED"
        default: nil
        }
    }
}

public enum PriorityLevel: Int, Sendable, Comparable, CaseIterable {
    case none = 0
    case low
    case medium
    case high
    case urgent

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func infer(from name: String) -> PriorityLevel {
        cache.value(for: name) {
            let n = name.lowercased()
            func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
            let words = NameWords(name)
            if has("urgent", "critical", "blocker", "highest", "p0", "🔥") || words.has(PriorityWords.urgent) { return .urgent }
            if has("high", "p1", "major") || words.has(PriorityWords.high) { return .high }
            if has("medium", "normal", "p2", "mid") || words.has(PriorityWords.medium) { return .medium }
            if has("low", "p3", "p4", "minor", "trivial") || words.has(PriorityWords.low) { return .low }
            return .medium
        }
    }

    private static let cache = InferenceCache<PriorityLevel>()
}

// MARK: - Names in other languages

/// The words teams use for columns in the languages the app is translated into. Each is matched at the start of a
/// word ("erledigt" in "Erledigt ✅", "закрыт" in "Закрыто"), so "Zu erledigen" stays a to-do; one ending in a space
/// must be the whole word. Chinese and Japanese ones may stand anywhere, as those names run words together.
private enum StatusWords {
    /// Names that contain a word of another kind: "準備完了" (ready) holds "完了" (done), "К выполнению" (to do)
    /// starts like "Выполнено" (done).
    static let exceptions: [(words: String, category: StatusCategory)] = ([
        ("未完了", .unstarted), ("準備完了", .unstarted), ("未完成", .unstarted), ("待完成", .unstarted), ("待解决", .unstarted),
        ("미완료", .unstarted), ("준비 완료", .unstarted), ("준비완료", .unstarted),
        ("не готов", .unstarted), ("готово к", .unstarted), ("готов к", .unstarted), ("к выполнению", .unstarted),
        ("listo para revis", .started), ("listo para review", .started), ("listo para", .unstarted),
        ("pronto para revis", .started), ("pronto para review", .started), ("pronto para", .unstarted),
    ] as [(String, StatusCategory)]).map { (NameWords.fold($0.0), $0.1) }

    static let canceled = NameWords.fold([
        "abgebrochen", "abgelehnt", "verworfen", "storniert", "nicht geplant", "wird nicht", "duplikat", "obsolet", "hinfällig",
        "annul", "abandonn", "rejet", "refus", "doublon", "ne sera pas", "non prévu", "non planifi",
        "cancelad", "descartad", "rechazad", "duplicad", "no se hará", "no planificad", "abandonad",
        "rejeitad", "não será", "não planejad",
        "отмен", "отклон", "дубл", "не будем", "не планир", "заброшен",
        "キャンセル", "中止", "却下", "見送", "重複", "対応しない", "やらない", "不要",
        "取消", "放弃", "拒绝", "重复", "不做", "不处理", "废弃", "不修复",
        "취소", "반려", "거절", "중복", "안 함", "하지 않음", "폐기",
    ])

    static let completed = NameWords.fold([
        "erledigt", "fertig", "abgeschlossen", "geschlossen", "veröffentlicht", "ausgeliefert", "gelöst", "umgesetzt",
        "terminé", "fait ", "fini", "fermé", "livré", "publié", "résolu", "déployé", "clos ", "achevé",
        "hecho", "terminad", "completad", "cerrad", "finalizad", "resuelt", "publicad", "entregad", "desplegad", "listo",
        "feito", "concluíd", "fechad", "pronto", "entregue", "resolvid", "lançad",
        "готов", "сделан", "выполнен", "завершен", "закрыт", "решен", "выпущен",
        "完了", "済", "終了", "クローズ", "解決",
        "完成", "关闭", "已解决", "已发布", "上线", "已合并",
        "완료", "종료", "닫힘", "해결", "배포됨", "출시",
    ])

    static let started = NameWords.fold([
        "in arbeit", "in bearbeitung", "prüfung", "in umsetzung", "in entwicklung", "läuft", "aktiv", "blockiert", "wartet",
        "test",
        "en cours", "revue", "relecture", "bloqu", "à valider", "en validation", "en attente",
        "en curso", "en progreso", "en proceso", "revisión", "en prueba", "haciendo", "en desarrollo", "trabajando",
        "em andamento", "em progresso", "fazendo", "revisão", "em teste", "testando", "em desenvolvimento", "validação",
        "в работе", "в процессе", "ревью", "на проверке", "проверк", "тестир", "заблокир", "в разработке",
        "進行中", "対応中", "作業中", "レビュー", "確認中", "テスト", "ブロック", "保留", "実装中", "開発中",
        "进行中", "处理中", "开发中", "评审", "审核", "审查", "测试", "阻塞", "受阻", "验证",
        "진행", "작업 중", "작업중", "검토", "리뷰", "테스트", "차단", "보류", "개발 중", "개발중",
    ])

    static let backlog = NameWords.fold([
        "später", "irgendwann", "ideen", "eingang", "sammlung", "zu klären",
        "plus tard", "un jour", "idées", "à trier", "tri ", "boîte de réception",
        "más adelante", "algún día", "por clasificar", "bandeja",
        "depois", "algum dia", "ideias", "triagem", "caixa de entrada",
        "бэклог", "беклог", "потом", "когда-нибудь", "идеи", "входящ", "разобрать",
        "バックログ", "いつか", "後で", "あとで", "アイデア", "未整理", "トリアージ", "受信",
        "需求池", "待规划", "以后", "想法", "收件箱", "待分类", "积压", "待定",
        "백로그", "나중", "언젠가", "아이디어", "분류", "받은",
    ])

    static let unstarted = NameWords.fold([
        "offen", "zu erledigen", "zu tun", "geplant", "bereit", "als nächstes", "nächste", "neu ", "nicht begonnen",
        "anstehend", "warteschlange",
        "à faire", "ouvert", "prêt", "prochain", "à venir", "planifi", "nouveau", "nouvelle", "non commencé", "en file",
        "por hacer", "pendiente", "abiert", "siguiente", "próxim", "nuevo", "nueva", "sin empezar", "sin iniciar",
        "a fazer", "para fazer", "abert", "planejad", "novo", "nova", "não iniciad", "pendente", "fila",
        "к выполнению", "сделать", "открыт", "нов", "запланир", "далее", "следующ", "не начат", "очеред",
        "未着手", "やること", "予定", "次", "新規", "オープン", "未対応", "準備",
        "待办", "待处理", "未开始", "计划", "下一步", "新建", "打开", "就绪", "待开始",
        "할 일", "할일", "예정", "대기", "다음", "준비", "신규", "열림", "시작 전",
    ])
}

/// The words for priority options, in the same way as `StatusWords`.
private enum PriorityWords {
    static let urgent = NameWords.fold([
        "dringend", "kritisch", "sofort", "höchst", "critique", "bloquant", "urgente", "crític", "bloqueante", "bloqueador",
        "срочн", "критич", "блокер", "наивысш", "緊急", "至急", "最優先", "最高", "紧急", "严重", "致命",
        "긴급", "치명", "최우선", "최상", "심각",
    ])
    static let high = NameWords.fold([
        "hoch", "wichtig", "haut", "élevé", "important", "alta", "alto", "importante", "высок", "важн",
        "高", "높", "중요", "상 ",
    ])
    static let medium = NameWords.fold([
        "mittel", "moyen", "media", "medio", "média", "médio", "средн", "обычн", "нормал",
        "中", "普通", "通常", "一般", "보통", "중간", "중 ",
    ])
    static let low = NameWords.fold([
        "niedrig", "gering", "unwichtig", "bas ", "basse", "faible", "mineur", "baja", "bajo", "menor", "baixa", "baixo",
        "низк", "незначит", "минимал", "低", "낮", "하 ",
    ])
}

/// A column or option name, ready to look for words in: lower case, without accents, every run of punctuation
/// and symbols turned into one space, padded with spaces (" in arbeit ").
struct NameWords {
    let spaced: String

    init(_ name: String) {
        let words = Self.fold(name).unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map { String(String.UnicodeScalarView($0)) }
        spaced = " " + words.joined(separator: " ") + " "
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func fold(_ list: [String]) -> [String] { list.map(fold) }

    func has(_ patterns: [String]) -> Bool {
        patterns.contains { pattern in
            let runsTogether = pattern.unicodeScalars.contains { Self.runsTogether($0) } && !pattern.hasSuffix(" ")
            return spaced.contains(runsTogether ? pattern : " " + pattern)
        }
    }

    /// Japanese and Chinese characters, whose words aren't separated by spaces (Korean is, but its syllables
    /// match inside a word too: "완료됨" is "완료").
    private static func runsTogether(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF: true
        default: false
        }
    }
}

/// Names repeat (a board has a handful of columns) and cards ask what theirs means while they're drawn.
private final class InferenceCache<Value>: @unchecked Sendable {
    private var values: [String: Value] = [:]
    private let lock = NSLock()

    func value(for name: String, _ make: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let value = values[name] { return value }
        let value = make()
        values[name] = value
        return value
    }
}

extension FieldOption {
    public var statusCategory: StatusCategory { StatusCategory.infer(from: name) }
    public var priorityLevel: PriorityLevel { PriorityLevel.infer(from: name) }
}

/// The opinionated defaults offered for new projects and for projects without a Priority field.
public enum Defaults {
    public static let priorityOptions: [RemoteOption] = [
        RemoteOption(id: nil, name: "Urgent", color: "ORANGE"),
        RemoteOption(id: nil, name: "High", color: "RED"),
        RemoteOption(id: nil, name: "Medium", color: "YELLOW"),
        RemoteOption(id: nil, name: "Low", color: "GRAY"),
    ]

    public static let optionColors = ["GRAY", "BLUE", "GREEN", "YELLOW", "ORANGE", "RED", "PINK", "PURPLE"]

    /// One of GitHub's option colours as it is called in a menu: "GRAY" is "Gray".
    static func colourName(_ color: String) -> String {
        switch color {
        case "GRAY": String(localized: .colourGray)
        case "BLUE": String(localized: .colourBlue)
        case "GREEN": String(localized: .colourGreen)
        case "YELLOW": String(localized: .colourYellow)
        case "ORANGE": String(localized: .colourOrange)
        case "RED": String(localized: .colourRed)
        case "PINK": String(localized: .colourPink)
        case "PURPLE": String(localized: .colourPurple)
        default: color.capitalized
        }
    }
}
