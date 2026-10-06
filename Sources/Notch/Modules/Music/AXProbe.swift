import ApplicationServices
import AppKit

/// Обход дерева «Универсального доступа» чужого приложения — печатью в stderr.
///
/// Нужен для плееров, которые не отдают ничего, кроме play/pause: лайк у них
/// живёт только внутри окна, и единственный способ до него дотянуться —
/// найти кнопку в этом дереве. Есть ли она там вообще, заранее не известно,
/// поэтому сначала смотрим глазами, а потом уже пишем код.
///
/// Запускается из терминала переменной `NOTCH_AXDUMP` и только из бандла:
/// доверие «Универсального доступа» система выдаёт подписи, а не исходнику,
/// и отдельный скрипт чужое дерево не увидит.
@MainActor
enum AXProbe {
    /// Печатает дерево приложения, чьё имя или bundle id содержит `needle`.
    static func dump(matching needle: String) {
        guard let root = connect(to: needle) else { return }
        visited = 0
        deadline = Date().addingTimeInterval(20)
        walk(root, depth: 0)
        log("узлов пройдено: \(visited)")
        if visited < 50 {
            log("дерево пустое: похоже, содержимое окна так и не открылось")
        }
    }

    /// Нажимает кнопку плеера с описанием `label` и печатает панель до и после.
    ///
    /// Два вопроса сразу: слушается ли кнопка чужого окна вообще и по чему
    /// видно, что лайк теперь стоит. Второе из одной кнопки не выясняется —
    /// состояние может уехать и в соседний элемент, и в её описание, поэтому
    /// снимаем весь плеер целиком: сравнение двух снимков покажет всё.
    ///
    /// Ищем только внутри плеера: те же «Нравится» есть у каждой карточки в
    /// списке, и первым по дереву попадается как раз не тот.
    static func press(matching needle: String, label: String) {
        guard let root = connect(to: needle) else { return }
        visited = 0
        deadline = Date().addingTimeInterval(20)
        guard let bar = playerBar(root) else {
            log("не найден плеер: региона с заголовком «Плеер» в дереве нет")
            return
        }
        visited = 0
        guard let target = first(in: bar, depth: 0, where: {
            string($0, kAXDescriptionAttribute) == label
        }) else {
            log("в плеере нет кнопки «\(label)»")
            return
        }

        log("кнопка до нажатия:")
        dumpAttributes(target)
        log("плеер до нажатия:")
        snapshot(bar)

        let status = AXUIElementPerformAction(target, kAXPressAction as CFString)
        log("нажатие: \(status == .success ? "принято" : "отказ \(status.rawValue)")")
        // Страница перерисовывает кнопку не мгновенно, а ответ от чужого
        // процесса всё равно придёт через рунлуп.
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        log("кнопка после нажатия:")
        dumpAttributes(target)
        log("плеер после нажатия:")
        snapshot(bar)

        // Тот же элемент, но найденный заново. Страница может подменить узел
        // целиком, и тогда старая ссылка так и будет отдавать старые значения:
        // одинаковые снимки «до» и «после» этим и объясняются.
        visited = 0
        deadline = Date().addingTimeInterval(10)
        if let fresh = first(in: bar, depth: 0, where: {
            string($0, kAXDescriptionAttribute) == label
        }) {
            log("кнопка найдена заново:")
            dumpAttributes(fresh)
        } else {
            log("после нажатия кнопки «\(label)» в плеере нет — описание сменилось")
            visited = 0
            snapshot(bar)
        }
    }

    /// Регион плеера — по подписи, а не по месту в дереве.
    ///
    /// Разметку страницы Яндекс меняет с каждым обновлением, а «Плеер» —
    /// это его же подпись для screen reader'ов, и держится она куда дольше
    /// классов вида `PlayerBar_root__cXUnU`. Старая панель кладёт её в
    /// `AXTitle`, панель «Моей волны» (5.104) — в `AXDescription`.
    private static func playerBar(_ root: AXUIElement) -> AXUIElement? {
        first(in: root, depth: 0) { element in
            string(element, kAXRoleAttribute) == kAXGroupRole
                && (string(element, kAXTitleAttribute) == "Плеер"
                    || string(element, kAXDescriptionAttribute) == "Плеер")
        }
    }

    /// Пишет секунды в ползунок таймкода и печатает, что он показал после.
    ///
    /// Перемотка у Electron-плеера — это либо системная сессия, либо этот
    /// ползунок; какой путь живой в текущей версии, видно только так.
    static func seek(matching needle: String, to seconds: Double) {
        guard let root = connect(to: needle) else { return }
        visited = 0
        deadline = Date().addingTimeInterval(20)
        guard let bar = playerBar(root),
              let slider = first(in: bar, depth: 0, where: {
                  string($0, kAXRoleAttribute) == kAXSliderRole
                      && string($0, kAXDescriptionAttribute) == "Управление таймкодом"
              })
        else {
            log("не найден ползунок таймкода")
            return
        }
        log("до:")
        dumpAttributes(slider)
        let status: AXError
        if let action = ProcessInfo.processInfo.environment["NOTCH_AXACTION"] {
            status = AXUIElementPerformAction(slider, action as CFString)
        } else {
            status = AXUIElementSetAttributeValue(
                slider, kAXValueAttribute as CFString, NSNumber(value: seconds) as CFTypeRef
            )
        }
        log("запись: \(status == .success ? "принята" : "отказ \(status.rawValue)")")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        log("после:")
        dumpAttributes(slider)
    }

    /// Печать поддерева без отступов и без предела глубины — для сравнения.
    private static func snapshot(_ element: AXUIElement) {
        visited = 0
        deadline = Date().addingTimeInterval(10)
        walk(element, depth: 0)
    }

    /// Находит приложение по имени и открывает его дерево.
    private static func connect(to needle: String) -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            log("нет доверия «Универсального доступа» — дерево не прочитать")
            return nil
        }
        let app = NSWorkspace.shared.runningApplications.first { app in
            let name = app.localizedName ?? ""
            let id = app.bundleIdentifier ?? ""
            return name.localizedCaseInsensitiveContains(needle)
                || id.localizedCaseInsensitiveContains(needle)
        }
        guard let app else {
            log("не найдено приложение по «\(needle)»")
            return nil
        }
        log("\(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] pid=\(app.processIdentifier)")
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron отвечает на запросы к дереву не всегда: без своего срока
        // ожидания обход встаёт на первом же неудачном узле насмерть.
        AXUIElementSetMessagingTimeout(root, 0.5)
        awakenWebContent(root)
        return root
    }

    /// Просит Chromium показать содержимое окна.
    ///
    /// Electron держит DOM вне дерева «Универсального доступа», пока об этом
    /// никто не спросил: иначе каждая страница стоила бы ему лишней работы.
    /// Спрашивают атрибутом `AXManualAccessibility` — без него в дереве
    /// видны только кнопки заголовка окна, и найти в нём нечего.
    ///
    /// Дерево строится не мгновенно, поэтому следом ждём — но крутя рунлуп,
    /// а не блокируя поток: ответы от чужого процесса приходят через него.
    private static func awakenWebContent(_ root: AXUIElement) {
        for key in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            let status = AXUIElementSetAttributeValue(root, key as CFString, kCFBooleanTrue)
            log("\(key): \(status == .success ? "принято" : "отказ \(status.rawValue)")")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
    }

    /// Сколько уровней вглубь. У Electron-плеера дерево — это весь DOM, и
    /// без предела печать уходит в десятки тысяч строк.
    private static let maxDepth = 24

    /// Предел на всякий случай: DOM большой страницы обходится минутами, а
    /// нужное видно в первых тысячах узлов.
    private static let maxNodes = 20_000

    private static var visited = 0

    /// Когда бросить обход. Не всякий узел отвечает даже за свой срок, и без
    /// общего предела печать может не кончиться никогда.
    private static var deadline = Date.distantFuture

    private static func walk(_ element: AXUIElement, depth: Int) {
        guard depth <= maxDepth, visited < maxNodes, Date() < deadline else { return }
        visited += 1
        let line = describe(element, depth: depth)
        if let line { log(line) }
        for child in children(of: element) {
            walk(child, depth: depth + 1)
        }
    }

    /// Первый элемент дерева, который подошёл. Ограничения обхода те же:
    /// без них поиск в неотвечающем окне не кончается.
    private static func first(
        in element: AXUIElement,
        depth: Int,
        where match: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard depth <= maxDepth, visited < maxNodes, Date() < deadline else { return nil }
        visited += 1
        if match(element) { return element }
        for child in children(of: element) {
            if let found = first(in: child, depth: depth + 1, where: match) { return found }
        }
        return nil
    }

    /// Все атрибуты элемента со значениями — чтобы увидеть, где живёт состояние.
    private static func dumpAttributes(_ element: AXUIElement) {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let keys = names as? [String] else {
            log("  атрибуты не прочитать")
            return
        }
        for key in keys {
            guard let value = string(element, key) else { continue }
            log("  \(shortKey(key))=\(value)")
        }
        var actions: CFArray?
        if AXUIElementCopyActionNames(element, &actions) == .success,
           let list = actions as? [String] {
            log("  действия: \(list.joined(separator: ","))")
        }
    }

    /// Строка про один элемент — или nil, если про него сказать нечего.
    ///
    /// Молчим о безымянных группах и контейнерах: в дереве страницы их
    /// девять из десяти, и они прячут то, что искали.
    private static func describe(_ element: AXUIElement, depth: Int) -> String? {
        let role = string(element, kAXRoleAttribute) ?? "?"
        var parts: [String] = []
        for key in [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXValueAttribute,
            kAXIdentifierAttribute,
            "AXDOMIdentifier",
            "AXDOMClassList",
            "AXRoleDescription",
        ] {
            guard let value = string(element, key), !value.isEmpty else { continue }
            parts.append("\(shortKey(key))=\(value)")
        }
        guard !parts.isEmpty || role.hasSuffix("Button") else { return nil }
        let pad = String(repeating: "  ", count: depth)
        return "\(pad)\(role) \(parts.joined(separator: " "))"
    }

    /// `AXTitle` → `title`: полные имена атрибутов делают строку нечитаемой.
    private static func shortKey(_ key: String) -> String {
        key.hasPrefix("AX") ? String(key.dropFirst(2)).lowercased() : key.lowercased()
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &raw
        )
        guard status == .success, let array = raw as? [AXUIElement] else { return [] }
        return array
    }

    /// Значение атрибута строкой. Числа и массивы тоже приводим: у элемента
    /// страницы в `AXValue` может лежать что угодно, и нам важен сам факт.
    private static func string(_ element: AXUIElement, _ key: String) -> String? {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &raw)
        guard status == .success, let raw else { return nil }
        switch raw {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        case let list as [String]: return list.joined(separator: ",")
        default: return nil
        }
    }

    private static func log(_ text: String) {
        FileHandle.standardError.write(Data("ax: \(text)\n".utf8))
    }
}
