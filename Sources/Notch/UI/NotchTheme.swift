import SwiftUI

enum NotchTheme {
    static let background = Color.black

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.34)

    static let accentSelection = Color.white.opacity(0.12)

    /// Обводка значков у схлопнутого выреза. Одна на всех: полка, музыка
    /// и таймер стоят в одном ряду, и разная кромка там видна сразу.
    static let islandBorder = Color.white.opacity(0.18)

    /// Единственный цвет на всю панель — и достаётся он единственному, что
    /// требует действия: вышедшему обновлению. Пока он один, его не надо
    /// искать: глаз находит его сам на белом по чёрному.
    static let accentUpdate = Color(red: 0.42, green: 0.76, blue: 1.0)

    static let panelWidth: CGFloat = 640
    /// На столько корпус расширяется, когда справа выезжает полка.
    /// Обложка при этом не ужимается — панель отдаёт полке новое место,
    /// а не отнимает у плеера.
    static let shelfPanelWidth: CGFloat = 232
    static let defaultPanelHeight: CGFloat = 220
    /// Настройкам нужно больше места, чем любому модулю.
    static let settingsPanelHeight: CGFloat = 296

    static let topCornerRadius: CGFloat = 12
    static let bottomCornerRadius: CGFloat = 22

    /// Отступ содержимого от верхнего края панели. Маленький: панель сама
    /// перекрывает меню-бар, поэтому прятаться от него не нужно — надо лишь
    /// не попасть под скругление верхнего угла.
    static let topInset: CGFloat = 8

    /// Отступ рейла от края панели. Единственное, что в рейле постоянно:
    /// всё остальное задаёт `RailMetrics` по выбранному размеру.
    static let railLeading: CGFloat = 8

    /// Заголовок содержимого отбивается от рейла на столько же, на сколько
    /// рейл отбит от левого края — чтобы отступы читались как один ритм.
    static let contentLeading: CGFloat = 12
    static let contentPadding: CGFloat = 16

    /// Отбивка названия раздела от левой кромки, когда ряд стоит внизу и
    /// название — у самого края корпуса. Ровно такая же, как поле
    /// содержимого в этой раскладке: название и то, что оно называет,
    /// стоят одной левой линией — иначе подпись ряда выпирает вправо
    /// относительно первой строки под ней.
    static let railTitleLeading: CGFloat = contentPadding

    /// Зазор между горизонтальным рейлом и содержимым под ним. Меньше
    /// обычного отступа: у колонки содержимое начинается сразу под строкой
    /// заголовка, и ряд не должен отодвигать его ниже, чем она.
    static let railRowGap: CGFloat = 4

    /// Высота строки в списках. Фиксирована, чтобы список не дёргался,
    /// когда при наведении появляются кнопки действий.
    static let rowHeight: CGFloat = 28

    /// Раскрытие — стоковая пружина системы, живая и короткая.
    ///
    /// `spring(duration:bounce:)` — нынешний способ Apple задавать пружину:
    /// `duration` — сколько длится движение, `bounce` — насколько сильно оно
    /// перелетает цель и возвращается. По такой же ездят системные плашки.
    ///
    /// Короче и звонче прежней (0.42 и почти без перелёта): та начинала
    /// слишком мягко, и первые полсотни миллисекунд ничего не происходило —
    /// панель читалась как «подумала и открылась».
    ///
    /// Одна на всех: корпус, начинка и кружки у выреза едут по ней же.
    /// Раньше у каждого была своя — корпус 0.34, начинка 0.42 с задержкой,
    /// кружки 0.5 на выезде и 0.22 на уезде. Кривые расходились, и глаз
    /// честно видел три движения вместо одного: панель «рассыпалась».
    static let expandAnimation = Animation.spring(duration: 0.36, bounce: 0.24)

    /// Схлопывание — без перелёта и чуть быстрее.
    ///
    /// Перелёт хорош на выезде: панель будто выскакивает из выреза. На
    /// возврате он читается как отскок закрывающейся крышки — панель
    /// «не хочет» закрываться. `.smooth` — тот же стоковый набор, только
    /// с нулевым `bounce`: движение приходит в ноль и останавливается.
    static let collapseAnimation = Animation.spring(duration: 0.26, bounce: 0)

    /// Какой пружиной ехать: наружу — с перелётом, обратно — без.
    static func presentation(expanding: Bool) -> Animation {
        expanding ? expandAnimation : collapseAnimation
    }

    /// Сколько длится раскрытие вместе с хвостом пружины. По этому числу
    /// панель понимает, что движение кончилось, и снова включает то, что
    /// рисуется каждый кадр.
    static let expandSettleDuration: Double = 0.55
}

/// Движение панели кончилось. Пока оно идёт, всё, что перерисовывается
/// каждый кадр (свечение, волна по басу), замирает: кадры нужнее самому
/// раскрытию, а дыхание света за эти полсекунды всё равно никто не
/// разглядит.
private struct NotchSettledKey: EnvironmentKey {
    static let defaultValue = true
}

/// Сколько точек содержимого справа ещё закрыто шторкой корпуса.
///
/// Нужно тому, что должно держаться по центру видимой части, а не по
/// центру раскладки: подсказки под плеером. Сам фон — свет и волна — им
/// не пользуется: фон стоит на месте, а движется корпус.
private struct NotchCurtainInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

/// Сколько места отдано полке прямо сейчас.
///
/// Нужно, чтобы полка не исчезала из вёрстки раньше, чем схлопнется
/// отданное ей место: пропав первой, она оставляла колонку плеера одну в
/// широкой области, та переезжала в её середину — и на закрытии обложка
/// уезжала вправо, чтобы через полсекунды прыгнуть обратно.
private struct NotchShelfSpaceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var notchIsSettled: Bool {
        get { self[NotchSettledKey.self] }
        set { self[NotchSettledKey.self] = newValue }
    }

    var notchCurtainInset: CGFloat {
        get { self[NotchCurtainInsetKey.self] }
        set { self[NotchCurtainInsetKey.self] = newValue }
    }

    var notchShelfSpace: CGFloat {
        get { self[NotchShelfSpaceKey.self] }
        set { self[NotchShelfSpaceKey.self] = newValue }
    }
}

/// Скругление с разными радиусами сверху и снизу: панель прижата к верхнему
/// краю экрана, поэтому сверху углы почти прямые.
/// Корпус, у которого ширина живёт в пути, а не в раскладке.
///
/// Рамка `.frame(width:)` — часть раскладки: пока она едет, SwiftUI
/// пересчитывает положение всего, что внутри, и начинка шире корпуса
/// центрируется по нему на каждом кадре. Отсюда и брались отъезды и
/// прыжки при открытии полки: компенсировать это сдвигами не выходит —
/// рамка интерполируется в раскладке, а сдвиг в модификаторе, и совпасть
/// кадр в кадр они не обязаны.
///
/// Здесь ширина — обычное анимируемое число внутри `Shape`. Раскладка от
/// неё не зависит вовсе: начинка стоит по полной ширине, а корпус
/// открывает её слева направо, как штора.
struct CurtainShape: Shape {
    /// Ширина открытой части.
    var width: CGFloat

    /// Середина выреза в координатах рамки. Пока корпус у́же рамки, он
    /// стоит серединой по вырезу и растёт от него в обе стороны: панель
    /// выходит из выреза, а не выезжает от левого края вбок.
    ///
    /// Как только ширины хватает, чтобы дойти до края, корпус в край и
    /// упирается — `clamp` ниже. Полке это и нужно: её прирост отдан
    /// правой стороне, и левый край при её выезде обязан стоять.
    var center: CGFloat

    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(width, center), AnimatablePair(topRadius, bottomRadius)) }
        set {
            width = newValue.first.first
            center = newValue.first.second
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let open = max(width, 0)
        let x = min(max(center - open / 2, rect.minX), max(rect.maxX - open, rect.minX))
        return NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(
            in: CGRect(x: x, y: rect.minY, width: open, height: rect.height)
        )
    }
}

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.height / 2, rect.width / 2)
        let bottom = min(bottomRadius, rect.height / 2, rect.width / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + top, y: rect.minY),
            radius: top
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top),
            radius: top
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            radius: bottom
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom),
            radius: bottom
        )
        path.closeSubpath()
        return path
    }
}
