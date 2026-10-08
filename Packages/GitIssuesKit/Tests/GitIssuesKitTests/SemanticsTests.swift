import Testing
@testable import GitIssuesKit

@Suite("Meaning inferred from column and option names")
struct SemanticsTests {
    @Test(arguments: [
        ("Backlog", StatusCategory.backlog), ("Icebox", .backlog), ("Triage", .backlog),
        ("Todo", .unstarted), ("To do", .unstarted), ("Up Next", .unstarted), ("Open", .unstarted), ("Ready", .unstarted),
        ("In Progress", .started), ("In Review", .started), ("Ready for review", .started), ("Blocked", .started),
        ("Needs Discussion", .started),
        ("Done", .completed), ("Shipped", .completed), ("Closed", .completed),
        ("Canceled", .canceled), ("Won't do", .canceled), ("Duplicate", .canceled),
    ])
    func statusCategory(name: String, expected: StatusCategory) {
        #expect(StatusCategory.infer(from: name) == expected)
    }

    /// Columns named in the languages the app speaks, including names that hold a word of another kind.
    @Test(arguments: [
        // German
        ("Backlog", StatusCategory.backlog), ("Später", .backlog), ("Ideen", .backlog),
        ("Offen", .unstarted), ("Zu erledigen", .unstarted), ("Zu tun", .unstarted), ("Geplant", .unstarted), ("Neu", .unstarted),
        ("In Arbeit", .started), ("In Bearbeitung", .started), ("In Prüfung", .started), ("Bereit zur Prüfung", .started),
        ("Blockiert", .started), ("Erneut geöffnet", .started),
        ("Erledigt", .completed), ("Erledigt ✅", .completed), ("Fertig", .completed), ("Abgeschlossen", .completed),
        ("Abgebrochen", .canceled), ("Wird nicht gemacht", .canceled), ("Duplikat", .canceled),
        // French
        ("Plus tard", .backlog), ("À faire", .unstarted), ("A faire", .unstarted), ("Prêt", .unstarted),
        ("En cours", .started), ("En revue", .started), ("Bloqué", .started),
        ("Terminé", .completed), ("Fait", .completed), ("Fermé", .completed), ("Annulé", .canceled), ("Doublon", .canceled),
        // Spanish
        ("Por hacer", .unstarted), ("Pendiente", .unstarted), ("En curso", .started), ("En progreso", .started),
        ("En revisión", .started), ("Listo para revisión", .started), ("Listo para desplegar", .unstarted),
        ("Hecho", .completed), ("Terminado", .completed), ("Listo", .completed), ("Cancelado", .canceled), ("Descartado", .canceled),
        // Portuguese
        ("A fazer", .unstarted), ("Em andamento", .started), ("Em revisão", .started), ("Pronto para revisão", .started),
        ("Feito", .completed), ("Concluído", .completed), ("Pronto", .completed), ("Cancelado", .canceled),
        // Russian
        ("Бэклог", .backlog), ("К выполнению", .unstarted), ("Новые", .unstarted), ("Готово к работе", .unstarted),
        ("В работе", .started), ("На проверке", .started), ("Ревью", .started),
        ("Готово", .completed), ("Сделано", .completed), ("Закрыто", .completed), ("Выполнено", .completed),
        ("Отменено", .canceled), ("Дубликат", .canceled),
        // Japanese
        ("バックログ", .backlog), ("未着手", .unstarted), ("準備完了", .unstarted), ("未完了", .unstarted),
        ("進行中", .started), ("対応中", .started), ("レビュー待ち", .started),
        ("完了", .completed), ("対応済み", .completed), ("リリース済み", .completed), ("却下", .canceled), ("中止", .canceled),
        // Chinese
        ("需求池", .backlog), ("待办", .unstarted), ("未开始", .unstarted), ("未完成", .unstarted),
        ("进行中", .started), ("开发中", .started), ("待审核", .started),
        ("已完成", .completed), ("完成", .completed), ("已关闭", .completed), ("已取消", .canceled), ("不做", .canceled),
        // Korean
        ("백로그", .backlog), ("할 일", .unstarted), ("준비 완료", .unstarted), ("미완료", .unstarted),
        ("진행 중", .started), ("진행중", .started), ("검토 중", .started),
        ("완료", .completed), ("완료됨", .completed), ("종료", .completed), ("취소", .canceled), ("중복", .canceled),
    ])
    func statusCategoryInOtherLanguages(name: String, expected: StatusCategory) {
        #expect(StatusCategory.infer(from: name) == expected, "\(name)")
    }

    @Test func onlyClosedCategoriesCloseTheIssue() {
        #expect(StatusCategory.completed.closeReason == "COMPLETED")
        #expect(StatusCategory.canceled.closeReason == "NOT_PLANNED")
        #expect(StatusCategory.started.closeReason == nil)
        #expect(StatusCategory.backlog.closeReason == nil)
    }

    @Test(arguments: [
        ("Urgent", PriorityLevel.urgent), ("P0", .urgent), ("Critical", .urgent),
        ("High", .high), ("P1", .high), ("Medium", .medium), ("P2", .medium), ("Low", .low), ("P3", .low),
    ])
    func priorityLevel(name: String, expected: PriorityLevel) {
        #expect(PriorityLevel.infer(from: name) == expected)
    }

    @Test(arguments: [
        ("Dringend", PriorityLevel.urgent), ("Hoch", .high), ("Mittel", .medium), ("Niedrig", .low), ("Unwichtig", .low),
        ("Critique", .urgent), ("Haute", .high), ("Moyenne", .medium), ("Basse", .low),
        ("Urgente", .urgent), ("Alta", .high), ("Media", .medium), ("Baja", .low), ("Média", .medium), ("Baixa", .low),
        ("Срочно", .urgent), ("Высокий", .high), ("Средний", .medium), ("Низкий", .low),
        ("緊急", .urgent), ("高", .high), ("中", .medium), ("低", .low), ("優先度：高", .high),
        ("紧急", .urgent), ("最高", .urgent), ("一般", .medium),
        ("긴급", .urgent), ("높음", .high), ("보통", .medium), ("낮음", .low), ("상", .high), ("중", .medium), ("하", .low),
    ])
    func priorityLevelInOtherLanguages(name: String, expected: PriorityLevel) {
        #expect(PriorityLevel.infer(from: name) == expected, "\(name)")
    }

    @Test func fuzzyMatchingFindsSubsequencesAndRanksPrefixesFirst() {
        #expect(fuzzyScore("cps", "Change priority and status") != nil)
        #expect(fuzzyScore("xyz", "Change status") == nil)
        let prefix = fuzzyScore("sta", "Status")!
        let scattered = fuzzyScore("sta", "Set a target")!
        #expect(prefix > scattered)
    }
}

@Suite("Branch names copied for an issue")
struct BranchNameTests {
    private func item(_ number: Int?, _ title: String) -> Item {
        Item(id: "PVTI_1", projectId: "PVT_1", kind: .issue, position: 0, number: number, title: title, body: "", state: "OPEN")
    }

    @Test(arguments: [
        ("Sign in with GitHub device flow", "14-sign-in-with-github-device-flow"),
        ("Fix: Zurückziehen von Antworten!", "14-fix-zuruckziehen-von-antworten"),
        ("  --Leading and trailing--  ", "14-leading-and-trailing"),
        ("🚀", "14"),
    ])
    func followsGitHub(title: String, expected: String) {
        #expect(item(14, title).branchName == expected)
    }

    @Test func staysShort() {
        let name = item(7, String(repeating: "word ", count: 40)).branchName ?? ""
        #expect(name.count <= 62)
        #expect(!name.hasSuffix("-"))
    }

    @Test func draftsHaveNone() {
        #expect(item(nil, "A draft").branchName == nil)
    }
}
