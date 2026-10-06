import SwiftUI

/// Концы полосы размытия в терминах самой прокрутки: `leading` — там, где
/// список начинается, `trailing` — где заканчивается. Тип лежит рядом с
/// прокруткой, а не внутри неё: вложенный в обобщённый тип, он требовал бы
/// у места вызова сперва вывести содержимое, и короткое `always: .trailing`
/// перестало бы собираться.
struct BlurredEdgeEnds: OptionSet {
    let rawValue: Int
    static let leading = BlurredEdgeEnds(rawValue: 1 << 0)
    static let trailing = BlurredEdgeEnds(rawValue: 1 << 1)
    static let both: BlurredEdgeEnds = [.leading, .trailing]
}

/// Прокрутка с прогрессивным размытием у краёв.
///
/// Маска-градиент делает у края «дырку»: строка гаснет резко и читается как
/// обрезанная. Плашка фона — то же самое, только непрозрачное. Здесь вместо
/// них лестница размытия: у внутренней границы полосы содержимое ещё резкое,
/// к кромке проходит несколько ступеней всё большего радиуса и только у самого
/// края уходит в фон.
///
/// Приём тот же, что в `react-progressive-blur`: несколько слоёв с разным
/// радиусом, у каждого своя маска — чем больше радиус, тем короче полоса, на
/// которой слой виден. Сильнее размытый слой лежит выше и у кромки полностью
/// перекрывает более резкие, поэтому содержимое не двоится.
///
/// Слои — копии того же содержимого внутри той же прокрутки, поэтому едут
/// вместе с оригиналом сами. Метал-шейдер дал бы плавный радиус вместо
/// ступеней, но тулчейн Metal стоит не у всех, кто собирает проект, а
/// `NSVisualEffectView` своего радиуса не даёт вовсе.
struct BlurredEdgeScrollView<Content: View>: View {
    let axis: Axis
    /// Длина полосы у начала прокрутки: верх списка, левый край строки вкладок.
    let leadingLength: CGFloat
    /// Длина полосы у конца прокрутки.
    let trailingLength: CGFloat
    /// С каких концов полоса стоит всегда, а не только пока есть куда
    /// прокручивать.
    ///
    /// По умолчанию полоса растёт с прокруткой: нетронутый список показывает
    /// первую строку целиком. Но там, где список едет под чужой строкой —
    /// под вкладками, под подвалом, — прокрутка ни при чём: подложка нужна
    /// им всегда. Долистав до низа, иначе получаешь подвал прямо на резком
    /// тексте.
    ///
    /// Концы разведены, потому что у одного списка они бывают разными: встречи
    /// дня уезжают под ряд кнопок снизу — там подложка нужна постоянно, — а
    /// сверху над ними ничего не лежит, и постоянная полоса там просто гасила
    /// бы первую встречу на нетронутом списке.
    let always: BlurredEdgeEnds
    /// Метит резкую копию как цель прокрутки — для `scrollPosition(id:)` и
    /// `onScrollTargetVisibilityChange`. По умолчанию выключено: большинству
    /// вызывающих адресация по `id` не нужна.
    ///
    /// Ставить `.scrollTargetLayout()` внутри самого `content` нельзя: его
    /// вызывают пять раз — резкая копия и четыре размытых, — и модификатор
    /// на внешней обёртке не снимает уже выставленный такой же модификатор
    /// глубже внутри: это разные узлы дерева, а не один дважды изменённый.
    /// Тогда лента регистрировала пять кандидатов на одну неделю: прыжок по
    /// `id` уезжал к случайному из них, а видимость сообщала неделю не
    /// с той копии. Раз он ставится здесь и только на резкую копию — второй
    /// раз ставить его в `content` нельзя.
    let scrollTarget: Bool
    @ViewBuilder var content: () -> Content

    init(
        _ axis: Axis,
        leading: CGFloat = 28,
        trailing: CGFloat? = nil,
        always: BlurredEdgeEnds = [],
        scrollTarget: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axis = axis
        self.leadingLength = leading
        self.trailingLength = trailing ?? leading
        self.always = always
        self.scrollTarget = scrollTarget
        self.content = content
    }

    /// Ступень: радиус и докуда она достаёт от кромки в долях полосы.
    /// `solid` — до этой доли ступень непрозрачна и перекрывает всё под собой,
    /// дальше до `reach` она сходит на нет.
    private struct Step {
        let radius: CGFloat
        let solid: CGFloat
        let reach: CGFloat
    }

    /// Радиус растёт втрое-вчетверо от ступени к ступени: реже — и ступени
    /// видно границами, чаще — неразличимы и зря стоят кадров. Последняя
    /// ступень берёт только кромку, но берёт её сильно, иначе у края размытие
    /// упирается в потолок и полоса читается как одна мутная плашка.
    ///
    /// Главное здесь не радиусы, а `solid` — доля полосы, на которой ступень
    /// стоит непрозрачной. Пока первая ступень держала непрозрачными три
    /// четверти полосы, содержимое входило в неё резким и мутнело почти
    /// разом: полоса читалась наплывом. Теперь каждая ступень непрозрачна
    /// на трети своего пути и остальные две трети растворяется, а соседние
    /// ступени внахлёст перекрывают друг друга — размытие набирается
    /// постепенно, той же полосой и на той же высоте.
    ///
    /// Сила при этом задаётся радиусами и от плавности не зависит: доли
    /// оставлены как есть, а вся лестница поднята — у кромки содержимое
    /// уходит в фон вдвое глубже прежнего.
    private var steps: [Step] { [
        Step(radius: 4, solid: 0.42, reach: 1),
        Step(radius: 13, solid: 0.26, reach: 0.88),
        Step(radius: 34, solid: 0.14, reach: 0.68),
        Step(radius: 76, solid: 0.05, reach: 0.44)
    ] }

    /// Насколько прокручено от начала и сколько осталось до конца — в долях
    /// длины полосы, 0…1. Полоса появляется только с той стороны, куда ещё
    /// можно прокрутить: пока список не тронут, первая строка резкая целиком.
    private struct Edges: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    @State private var edges = Edges()

    /// Отмеченный в `always` конец стоит на полную с первого кадра, ещё до
    /// того, как прокрутка сообщит свою геометрию; остальные растут с ней.
    private var shown: Edges {
        Edges(
            leading: always.contains(.leading) ? 1 : edges.leading,
            trailing: always.contains(.trailing) ? 1 : edges.trailing
        )
    }

    /// Сколько у самой кромки содержимое ещё и гаснет. Без этого верхняя
    /// ступень стоит у края непрозрачной: пиксели размытые, но обрезаны
    /// окном прокрутки ровно по кромке — и край снова читается как обрез.
    /// Размывать дальше некуда, поэтому последние точки берёт прозрачность.
    /// У строки вкладок гашение берёт долю полосы: там оно съедает поля
    /// подписей, и чем шире — тем мягче уезжает вбок. В списке так нельзя:
    /// полоса длинная, и доля от неё накрыла бы целые строки. Там гашение
    /// стоит узкой каймой у самой кромки, а за плавность отвечают ступени.
    private func fadeLength(over band: CGFloat) -> CGFloat {
        axis == .horizontal ? min(52, band * 0.45) : min(16, band)
    }

    var body: some View {
        ScrollView(axis == .vertical ? .vertical : .horizontal) {
            ZStack(alignment: .topLeading) {
                // Резкая копия у краёв убирается.
                //
                // Раньше она оставалась лежать под размытыми во всю длину
                // полосы, и это было главной причиной, по которой «сильнее
                // размыть» ничего не меняло: карточки в панели стоят на
                // прозрачном, размытая копия прозрачности не теряет — и
                // сквозь неё читался резкий текст оригинала. Радиус тут
                // бессилен: сколько ни размывай верхний слой, нижний
                // остаётся резким.
                //
                // Гаснет она ровно по профилю первой ступени: там, где
                // оригинал уже ушёл, стоит копия с радиусом в четыре точки —
                // от него она неотличима, и подмены не видно.
                content()
                    .scrollTargetLayout(isEnabled: scrollTarget)
                    .mask { baseMask }

                // Размытые копии только рисуются: наведение и клики остаются
                // у нижней, резкой.
                //
                // `.id` и цели прокрутки у копий снимаются. Внутри одной
                // прокрутки лежит пять копий содержимого, и без этого каждая
                // метка встречалась пять раз: `scrollTo` уезжал к любой из
                // них, а `onScrollTargetVisibilityChange` присылал каждую
                // неделю по числу копий. Снимает их `scrollTargetLayout(
                // isEnabled: false)` вместе с `.id(nil)`-эквивалентом —
                // обёрткой в контейнер без идентичности.
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    content()
                        .scrollTargetLayout(isEnabled: false)
                        .blur(radius: step.radius)
                        .mask { mask(for: step) }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .onScrollGeometryChange(for: Edges.self) { geometry in
            let offset: CGFloat
            let visible: CGFloat
            let total: CGFloat

            switch axis {
            case .vertical:
                offset = geometry.contentOffset.y + geometry.contentInsets.top
                visible = geometry.containerSize.height
                total = geometry.contentSize.height
                    + geometry.contentInsets.top + geometry.contentInsets.bottom
            case .horizontal:
                offset = geometry.contentOffset.x + geometry.contentInsets.leading
                visible = geometry.containerSize.width
                total = geometry.contentSize.width
                    + geometry.contentInsets.leading + geometry.contentInsets.trailing
            }

            // Положение считается не по одному смещению, а по тому, сколько
            // вообще есть куда листать. Смещению верить нельзя: прокрутка
            // отдаёт его и отрицательным на оттяжке, и в тысячах точек посреди
            // прыжка к неделе. Одного такого кадра хватало, чтобы полоса
            // встала на полную и там осталась: список короче окна больше не
            // меняет геометрию — сообщать о возврате к началу нечему, — и
            // первая встреча дня так и стояла приглушённой.
            //
            // Заодно отсюда само собой выходит правило для короткого списка:
            // листать некуда — полос нет вовсе, ни с одного конца.
            let scrollable = max(0, total - visible)
            let position = min(max(0, offset), scrollable)

            return Edges(
                leading: fraction(position, over: leadingLength),
                trailing: fraction(scrollable - position, over: trailingLength)
            )
        } action: { _, new in
            edges = new
        }
        .overlay { edgeShade }
        .mask { edgeFade }
    }

    /// Лёгкое затемнение поверх тех же полос. Размытие само по себе разницу
    /// в яркости не снимает: под кромкой остаётся цветная карточка, и подпись
    /// на ней читается через раз. Тень идёт от нуля у внутренней границы к
    /// `shadeDepth` у кромки — не заливка, а уклон, поэтому карточка под ней
    /// узнаётся цветом, а не превращается в чёрную плашку.
    private var shadeDepth: CGFloat { 0.8 }

    /// Профиль уклона от внутренней границы полосы к кромке: доля пути и
    /// доля `shadeDepth` на ней.
    ///
    /// Прямая от нуля до `shadeDepth` давала угол ровно там, где тень
    /// начиналась: яркость шла ровно, а вот её скорость менялась разом —
    /// и глаз ловил границу полосы как черту поперёк карточек. Здесь
    /// начало почти плоское: первую пятую пути тень едва набирает десятую
    /// часть глубины и из карточки выходит незаметно.
    ///
    /// Дальше она наверстывает: к середине полосы стоит уже больше
    /// половины глубины — под подписью, которая там и лежит, — а последнюю
    /// треть идёт почти плато, так что у самой кромки прибавка не читается.
    private var shadeProfile: [(t: CGFloat, alpha: CGFloat)] { [
        (0, 0),
        (0.2, 0.09),
        (0.35, 0.28),
        (0.5, 0.56),
        (0.68, 0.82),
        (0.85, 0.96),
        (1, 1)
    ] }

    private var edgeShade: some View {
        GeometryReader { proxy in
            Rectangle().fill(shade(across: proxy.size))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shade(across size: CGSize) -> LinearGradient {
        let span = axis == .vertical ? size.height : size.width
        let head = span > 0 ? leadingLength * shown.leading / span : 0
        let tail = span > 0 ? trailingLength * shown.trailing / span : 0
        var stops: [Gradient.Stop] = []

        if head > 0 {
            for point in shadeProfile {
                stops.append(.init(
                    color: .black.opacity(shadeDepth * shown.leading * point.alpha),
                    location: head * (1 - point.t)
                ))
            }
        }
        if tail > 0 {
            for point in shadeProfile {
                stops.append(.init(
                    color: .black.opacity(shadeDepth * shown.trailing * point.alpha),
                    location: 1 - tail * (1 - point.t)
                ))
            }
        }
        if stops.isEmpty {
            stops = [.init(color: .clear, location: 0), .init(color: .clear, location: 1)]
        }

        return LinearGradient(
            stops: stops.sorted { $0.location < $1.location },
            startPoint: axis == .vertical ? .top : .leading,
            endPoint: axis == .vertical ? .bottom : .trailing
        )
    }

    /// Гашение у самой кромки поверх ступеней размытия. Полоса растёт вместе
    /// с прокруткой — пока список не тронут, первая строка видна целиком.
    @ViewBuilder
    private var edgeFade: some View {
        let head = fadeLength(over: leadingLength) * shown.leading
        let tail = fadeLength(over: trailingLength) * shown.trailing
        let solid = Rectangle().fill(Color.black)

        switch axis {
        case .vertical:
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: head)
                solid
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: tail)
            }
        case .horizontal:
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: head)
                solid
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: tail)
            }
        }
    }

    /// Доля округляется до восьмых: иначе маски пересобирались бы на каждый
    /// пиксель прокрутки, а пересборка — это перерисовка всех копий.
    private func fraction(_ distance: CGFloat, over length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        let raw = min(1, max(0, distance / length))
        return (raw * 8).rounded() / 8
    }

    /// Маска одной ступени. Строится не по содержимому, а по видимой части
    /// прокрутки: полосы стоят у краёв окна, а не у краёв списка, который
    /// под ними едет.
    private func mask(for step: Step) -> some View {
        GeometryReader { proxy in
            let visible = proxy.bounds(of: .scrollView)
                ?? CGRect(origin: .zero, size: proxy.size)

            Rectangle()
                .fill(bands(across: visible) { length in
                    [
                        (0, 1),
                        (step.solid * length, 1),
                        (step.reach * length, 0)
                    ]
                })
                .frame(width: visible.width, height: visible.height)
                .offset(x: visible.minX, y: visible.minY)
        }
    }

    /// Маска резкой копии — обратная первой ступени: у кромки её нет, к
    /// внутренней границе полосы она набирается целиком. В середине списка
    /// маска сплошная, иначе резкой копии не осталось бы вовсе.
    private var baseMask: some View {
        GeometryReader { proxy in
            let visible = proxy.bounds(of: .scrollView)
                ?? CGRect(origin: .zero, size: proxy.size)
            let step = steps[0]

            Rectangle()
                .fill(bands(across: visible, middle: .black) { length in
                    [
                        (0, 0),
                        (step.solid * length, 0),
                        (step.reach * length, 1)
                    ]
                })
                .frame(width: visible.width, height: visible.height)
                .offset(x: visible.minX, y: visible.minY)
        }
    }

    /// Собирает градиент на всю видимую часть: одинаковый профиль у начала и
    /// у конца, между ними — `middle`. `profile` получает длину своей полосы
    /// в долях видимой части и возвращает точки от кромки внутрь.
    private func bands(
        across visible: CGRect,
        middle: Color = .clear,
        profile: (CGFloat) -> [(t: CGFloat, alpha: CGFloat)]
    ) -> LinearGradient {
        let span = axis == .vertical ? visible.height : visible.width
        guard span > 0 else {
            return LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
        }

        let head = leadingLength * shown.leading / span
        let tail = trailingLength * shown.trailing / span
        var stops: [Gradient.Stop] = []

        if head > 0 {
            for point in profile(head) {
                stops.append(.init(color: Color.black.opacity(point.alpha), location: point.t))
            }
        }
        stops.append(.init(color: middle, location: max(head, 1 - tail) / 2 + 0.0001))
        if tail > 0 {
            for point in profile(tail).reversed() {
                stops.append(.init(color: Color.black.opacity(point.alpha), location: 1 - point.t))
            }
        }

        return LinearGradient(
            stops: stops.sorted { $0.location < $1.location },
            startPoint: axis == .vertical ? .top : .leading,
            endPoint: axis == .vertical ? .bottom : .trailing
        )
    }
}

/// Прокрутка модуля во всю панель.
///
/// Список идёт до самых кромок корпуса и уходит под них тем же
/// прогрессивным размытием, что и в настройках: у внутренней границы
/// полосы содержимое ещё резкое, к кромке проходит лестницу радиусов и
/// только у края уходит в фон. До этого модули гасили края простым
/// градиентом-маской — той самой «дыркой», про которую написано в начале
/// файла: строка не таяла, а обрывалась на полупрозрачной середине.
///
/// Полосы стоят всегда, а не только пока есть куда прокручивать. Список
/// здесь уезжает не в пустоту, а под чужие строки — под вырез и заголовок
/// сверху, под ряд вкладок снизу, — и подложка им нужна и на нетронутом
/// списке: долистав до низа, иначе получаешь кнопки прямо на резком тексте.
///
/// Куда именно тянуться, модуль не решает: размеры приходят из окружения,
/// которым панель описала свои поля. Поэтому один и тот же список одинаково
/// правильно лежит и при колонке слева, и при ряде снизу — меняются числа,
/// а не вёрстка.
struct NotchScroll<Content: View>: View {
    @Environment(\.notchContentTopInset) private var topInset
    @Environment(\.notchContentBottomInset) private var bottomInset
    @Environment(\.notchContentLeadingInset) private var leadingInset
    @Environment(\.notchContentTrailingInset) private var trailingInset

    @ViewBuilder var content: () -> Content

    var body: some View {
        BlurredEdgeScrollView(
            .vertical,
            leading: topInset,
            trailing: bottomInset,
            always: .both
        ) {
            content()
                // Поля, которые отняло растягивание, содержимое получает
                // обратно внутри прокрутки: строки стоят там же, где
                // стояли, — за кромку уходит только сама полоса.
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
        }
        .scrollIndicators(.never)
        .padding(.top, -topInset)
        .padding(.bottom, -bottomInset)
        .padding(.leading, -leadingInset)
        .padding(.trailing, -trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
