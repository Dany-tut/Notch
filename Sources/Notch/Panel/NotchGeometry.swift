import AppKit

/// Описание "выреза" на конкретном экране.
///
/// На Маках с нотчем берём настоящую геометрию из `NSScreen`.
/// На остальных экранах (и на внешних мониторах) рисуем виртуальный нотч
/// по центру верхнего края — визуально это тот же элемент.
struct NotchGeometry {
    /// Прямоугольник самого выреза в координатах экрана (origin снизу-слева, как у AppKit).
    let notchRect: CGRect
    /// Полный прямоугольник экрана.
    let screenFrame: CGRect
    /// Настоящий нотч, а не нарисованный нами.
    let isPhysical: Bool

    /// Виртуальный нотч по умолчанию — примерно как на 14"/16" MacBook Pro.
    static let fallbackSize = CGSize(width: 190, height: 32)

    static func current(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            let width = right.minX - left.maxX
            let height = screen.safeAreaInsets.top
            if width > 0 {
                let rect = CGRect(
                    x: frame.minX + left.maxX,
                    y: frame.maxY - height,
                    width: width,
                    height: height
                )
                return NotchGeometry(notchRect: rect, screenFrame: frame, isPhysical: true)
            }
        }

        let size = fallbackSize
        let rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return NotchGeometry(notchRect: rect, screenFrame: frame, isPhysical: false)
    }

    /// Экран, на котором живёт панель: тот, где физически есть нотч,
    /// иначе — основной.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }
}

// MARK: - Настройки поведения

@MainActor
extension NotchGeometry {
    /// Экран по настройке «показывать на».
    static func screen(for behaviour: BehaviourSettings) -> NSScreen? {
        switch behaviour.displayTarget {
        case .builtIn:
            return preferredScreen()
        case .main:
            return NSScreen.main
        case .active:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        }
    }

    /// Геометрия с учётом пользовательских поправок: принудительный
    /// виртуальный вырез и подгонка его размера.
    static func current(for screen: NSScreen, behaviour: BehaviourSettings) -> NotchGeometry {
        let base = behaviour.forceSimulatedNotch
            ? simulated(for: screen)
            : current(for: screen)

        let dw = behaviour.clampedWidthAdjust
        let dh = behaviour.clampedHeightAdjust
        guard dw != 0 || dh != 0 else { return base }

        let width = max(60, base.notchRect.width + dw)
        let height = max(12, base.notchRect.height + dh)
        let rect = CGRect(
            x: base.notchRect.midX - width / 2,
            y: base.screenFrame.maxY - height,
            width: width,
            height: height
        )
        return NotchGeometry(notchRect: rect, screenFrame: base.screenFrame, isPhysical: base.isPhysical)
    }

    /// Нарисованный вырез по центру верхнего края — в обход настоящего.
    static func simulated(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let size = fallbackSize
        let rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return NotchGeometry(notchRect: rect, screenFrame: frame, isPhysical: false)
    }
}
