# Words in every language

The app is written in English and translated into German, French, Spanish, Portuguese (Brazil), Russian, Japanese,
Chinese (Simplified) and Korean. The texts are in
[Localizable.xcstrings](../Packages/GitIssuesKit/Sources/GitIssuesKit/Resources/Localizable.xcstrings); this page fixes
the words for the things that come up again and again, so that every screen calls them the same.

## How the words were chosen

- **As people who use GitHub say them.** GitHub's own translated documentation is largely machine-made ("problème"
  for issue, "demande de tirage" for pull request, "끌어오기 요청"), so it is no model. Where developers keep the English
  word (German "Issue", Japanese "Issue", Korean "이슈"), so does the app. Where a native word is established in
  tools people know (GitLab, Jira: "ticket", "incidencia", "задача", "议题"), the app uses that.
- **As Apple says them** for everything the system has a word for: settings, sign in, cancel, done, delete, undo,
  search, the Inbox (Apple Mail's word where it fits). The app then reads like the system around it.
- **The Inbox actions** (archive, snooze, mark as read) follow Gmail and Apple Mail in each language.
- **What is never translated:** the app's name "Issues", "GitHub", and everything that comes from GitHub (titles,
  column and option names, labels, people).

## Tone

| | Address | Notes |
|---|---|---|
| German | du | As Apple. Nouns capitalised, no title case otherwise. A space before "…" in menus ("Zuweisen an …"). Quotes „…“. |
| French | vous | As Apple. A non-breaking space before : ; ? ! and inside « ». No space before "…". |
| Spanish | tú | As Apple. ¿…? and ¡…!. Quotes «…» or “…”. |
| Portuguese (Brazil) | você | As Apple. |
| Russian | вы (lower case) | As Apple. Quotes «…». |
| Japanese | です・ます in sentences | Buttons and menu items as nouns or short verbs (「アーカイブ」「既読にする」). Full-width punctuation 「」、。. No spaces around Latin words ("Issueを作成"). |
| Chinese (Simplified) | 你 | Full-width punctuation. A space between Chinese and Latin letters or digits ("3 个议题", "在 GitHub 上打开"), as Apple does. |
| Korean | 합니다 in sentences | Buttons as nouns (「보관」「취소」). |

Only English uses Title Case; every other language writes menus and buttons as it writes them in its own Apple apps.

## Terms

| English | German | French | Spanish | Portuguese (BR) | Russian | Japanese | Chinese | Korean |
|---|---|---|---|---|---|---|---|---|
| issue | Issue (das) | ticket (m.) | incidencia | issue (f.) | задача | Issue | 议题 | 이슈 |
| sub-issue | Sub-Issue | sous-ticket | subincidencia | sub-issue | подзадача | サブIssue | 子议题 | 하위 이슈 |
| parent issue | übergeordnetes Issue | ticket parent | incidencia principal | issue principal | родительская задача | 親Issue | 父议题 | 상위 이슈 |
| pull request | Pull Request (der) | pull request (f.) | pull request (f.) | pull request (m.) | пул-реквест | プルリクエスト | 拉取请求 | 풀 리퀘스트 |
| draft (on a board) | Entwurf | brouillon | borrador | rascunho | черновик | 下書き | 草稿 | 초안 |
| project | Projekt | projet | proyecto | projeto | проект | プロジェクト | 项目 | 프로젝트 |
| board | Board | tableau | tablero | quadro | доска | ボード | 看板 | 보드 |
| list (view) | Liste | liste | lista | lista | список | リスト | 列表 | 목록 |
| column | Spalte | colonne | columna | coluna | колонка | 列 | 列 | 열 |
| status | Status | statut | estado | status | статус | ステータス | 状态 | 상태 |
| priority | Priorität | priorité | prioridad | prioridade | приоритет | 優先度 | 优先级 | 우선순위 |
| label | Label (das) | étiquette | etiqueta | etiqueta | метка | ラベル | 标签 | 레이블 |
| assignee | zuständig (Zuständig, as a field) | responsable | responsable | responsável | исполнитель | 担当者 | 负责人 | 담당자 |
| assign to | zuweisen an | assigner à | asignar a | atribuir a | назначить | 割り当てる | 分配给 | 할당 |
| due date | Fälligkeitsdatum (fällig am …) | échéance | fecha de vencimiento | prazo | срок | 期日 | 截止日期 | 마감일 |
| repository | Repository (Pl. Repositories) | dépôt | repositorio | repositório | репозиторий | リポジトリ | 仓库 | 저장소 |
| milestone | Meilenstein | jalon | hito | marco | веха | マイルストーン | 里程碑 | 마일스톤 |
| comment | Kommentar | commentaire | comentario | comentário | комментарий | コメント | 评论 | 댓글 |
| description | Beschreibung | description | descripción | descrição | описание | 説明 | 描述 | 설명 |
| closed / reopen | geschlossen / wieder öffnen | fermé / rouvrir | cerrada / reabrir | fechada / reabrir | закрыта / открыть снова | クローズ / 再オープン | 已关闭 / 重新打开 | 닫힘 / 다시 열기 |
| closed as not planned | als „nicht geplant“ geschlossen | fermé comme non prévu | cerrada como no planificada | fechada como não planejada | закрыта как незапланированная | 対応予定なしでクローズ | 以“不计划”关闭 | 계획 없음으로 닫힘 |
| blocked by / blocking | blockiert durch / blockiert | bloqué par / bloque | bloqueada por / bloquea | bloqueada por / bloqueia | заблокирована / блокирует | ブロック元 / ブロック先 | 被阻塞 / 阻塞 | 차단됨 / 차단 중 |
| Inbox | Eingang | Réception | Entrada | Entrada | Входящие | 受信トレイ | 收件箱 | 수신함 |
| notification | Mitteilung | notification | notificación | notificação | уведомление | 通知 | 通知 | 알림 |
| archive | archivieren | archiver | archivar | arquivar | архивировать | アーカイブ | 归档 | 보관 |
| snooze | zurückstellen | mettre en attente | posponer | adiar | отложить | スヌーズ | 稍后提醒 | 다시 알림 |
| mark as read / unread | als gelesen / ungelesen markieren | marquer comme lu / non lu | marcar como leído / no leído | marcar como lida / não lida | отметить как прочитанное / непрочитанное | 既読にする / 未読にする | 标记为已读 / 未读 | 읽음으로 표시 / 읽지 않음으로 표시 |
| unsubscribe | abbestellen | se désabonner | cancelar suscripción | cancelar inscrição | отписаться | 購読解除 | 取消订阅 | 구독 취소 |
| sync | synchronisieren | synchroniser | sincronizar | sincronizar | синхронизировать | 同期 | 同步 | 동기화 |
| sign in / sign out | anmelden / abmelden | se connecter / se déconnecter | iniciar sesión / cerrar sesión | iniciar sessão / encerrar sessão | войти / выйти | サインイン / サインアウト | 登录 / 退出登录 | 로그인 / 로그아웃 |
| settings | Einstellungen | Réglages | Ajustes | Ajustes | Настройки | 設定 | 设置 | 설정 |
| command palette | Befehlspalette | palette de commandes | paleta de comandos | paleta de comandos | палитра команд | コマンドパレット | 命令面板 | 명령 팔레트 |
| sample data | Beispieldaten | données d'exemple | datos de ejemplo | dados de exemplo | демонстрационные данные | サンプルデータ | 示例数据 | 샘플 데이터 |
| queued (change waiting to be sent) | wartet | en attente | en cola | na fila | в очереди | 送信待ち | 待发送 | 전송 대기 |

## Grammar to watch

- **Gender and case.** Placeholders hold names the translator can't see (a person, a project, a weekday, a status).
  Choose wordings that fit any of them: "Zuständig: Mira" rather than an article that depends on the name; Russian
  "Статус: %@" rather than a sentence that would need the name in another case.
- **Plurals.** Russian needs one, few, many and other ("1 задача", "2 задачи", "5 задач"); Japanese, Chinese and
  Korean have one form. Counts are always plural entries in the catalog, never built in code.
- **Length.** German and French run about a third longer than English, Russian often more. Sidebar rows, toolbar
  segments, iPhone tabs and the sync line have little room; the comment in the catalog says so where it matters.

## Changing a word

Change it here first, then in every text that uses it (`Tools/strings.py list <word>` finds them), so the app keeps
calling one thing by one name.
