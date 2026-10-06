import SwiftUI

/// Музыка: обложка, трек, прогресс и транспорт.
struct MusicModule: NotchModule {
    static let moduleID = "music"

    let id = MusicModule.moduleID
    let titleKey: L10n.Key = .moduleMusic
    let symbol = "music.note"

    let coordinator: NowPlayingCoordinator

    func makeContent() -> some View {
        MusicContent(coordinator: coordinator)
    }
}

private struct MusicContent: View {
    @ObservedObject var coordinator: NowPlayingCoordinator
    @EnvironmentObject private var settings: AppSettings

    /// Панель ещё едет — раскрывается или схлопывается. Пока едет, свет и
    /// волна замирают: они перерисовываются каждый кадр, и эти кадры
    /// нужнее самому раскрытию.
    @Environment(\.notchIsSettled) private var isSettled
    @Environment(\.notchContentTopInset) private var contentTopInset
    @Environment(\.notchContentBottomInset) private var contentBottomInset
    /// Ширина, отданная полке. Ноль — места нет, полке в вёрстке делать
    /// тоже нечего.
    @Environment(\.notchShelfSpace) private var shelfSpace

    /// Сторона обложки. По ней же меряется колонка плеера справа —
    /// обложка и плеер стоят одной карточкой.
    private static let artworkSide: CGFloat = 190

    /// Насколько колонка плеера опущена относительно обложки.
    private static let playerDrop: CGFloat = 12

    /// Раскладка одна на все состояния: обложка, две строки, прогресс,
    /// транспорт. Раньше «играет» и «ничего не играет» были разными
    /// вёрстками — при переключении плеера панель подменялась целиком,
    /// вместо того чтобы переехать. Теперь меняется только содержимое
    /// слотов, а сами элементы остаются на месте и двигаются плавно.
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Artwork(
                    data: coordinator.info?.artwork,
                    bundleID: artworkBundleID,
                    side: Self.artworkSide
                )
                .padding(.trailing, 20)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        // Название и переключатель плеера — одной строкой.
                        // Строка у названия всё равно одна, а справа от
                        // неё пустота во всю колонку: переключатель, стоя
                        // отдельной строкой ниже, забирал высоту у полосы
                        // прогресса и транспорта — и те уезжали ниже
                        // обложки. Теперь он живёт в чужом пустом месте.
                        HStack(alignment: .center, spacing: 12) {
                            Text(title)
                                .font(.system(size: 23, weight: .bold))
                                .foregroundStyle(NotchTheme.textPrimary)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                                .animation(.easeInOut(duration: 0.22), value: title)

                            Spacer(minLength: 12)

                            SourceStrip(coordinator: coordinator)
                        }
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(NotchTheme.textSecondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.22), value: subtitle)
                    }

                    Spacer(minLength: 10)

                    // Полоса и кнопки — одним блоком, а не двумя частями
                    // по разным углам. Раньше между ними стоял такой же
                    // растяжной зазор, как и до заголовка: три пружины
                    // делили высоту поровну, и проигрывание растекалось по
                    // всей колонке — полоса липла к названию, кнопки к
                    // нижней кромке. Теперь зазор между ними свой,
                    // постоянный, а тянутся только поля сверху и снизу.
                    //
                    // Середина блока при этом ниже середины обложки, и это
                    // нарочно: ровно по центру карточки полоса села бы
                    // вплотную к подзаголовку, а нижняя треть обложки
                    // осталась бы пустой. Блок стоит по центру того, что
                    // осталось от заголовка, — так поля над ним и под ним
                    // одинаковые.
                    VStack(alignment: .leading, spacing: 18) {
                        Progress(info: coordinator.info) { seconds in
                            coordinator.seek(to: seconds)
                        }

                        Transport(
                            isPlaying: coordinator.info?.isPlaying ?? false,
                            favorite: coordinator.info?.isFavorite,
                            toggleFavorite: { coordinator.toggleFavorite() },
                            disliked: coordinator.canDislike ? coordinator.isDisliked : nil,
                            toggleDislike: { coordinator.toggleDislike() },
                            isShelfOpen: coordinator.isShelfOpen,
                            hasShelf: coordinator.hasShelfContent,
                            send: { coordinator.send($0) },
                            // Оборачиваем здесь, а не внутри: в этой же
                            // транзакции контроллер меняет ширину корпуса.
                            // Тогда полка, окно и содержимое едут по одной
                            // кривой, а не по трём своим — от этого и была рябь.
                            toggleShelf: {
                                withAnimation(NotchTheme.expandAnimation) {
                                    coordinator.toggleShelf()
                                }
                            }
                        )
                    }

                    Spacer(minLength: 10)
                }
                // Ширина колонки постоянна. Отдай её растущему корпусу — и
                // название с полосой прогресса тянулись бы вместе с ним,
                // то есть плеер перекладывался бы каждый кадр. Весь прирост
                // достаётся полке, ради которой он и случился.
                // Высота — ровно в обложку: плеер стоит с ней одной
                // карточкой, от верхней кромки до нижней. Без этого
                // колонка тянулась во всё содержимое, и транспорт висел
                // заметно ниже обложки — плеер читался съехавшим вниз.
                .frame(width: 348, height: Self.artworkSide, alignment: .leading)
                // Колонка опущена относительно обложки: вровень с её
                // верхней кромкой название читалось задранным — у
                // обложки там пустое поле, а у колонки сразу крупная
                // строка, и та казалась выше карточки, хотя стояла
                // ровно. Вместе с названием вниз уходит и проигрывание.
                .offset(y: Self.playerDrop)

                // Полка держится в вёрстке, пока за ней держится место:
                // уйди она первой, колонка плеера переехала бы в середину
                // освободившейся ширины и вернулась бы обратно только через
                // полсекунды, когда схлопнется раскладка. Гаснет она при
                // этом сразу — корпусу положено доезжать до пустого.
                if coordinator.isShelfOpen || shelfSpace > 0 {
                    Shelf(coordinator: coordinator)
                        .opacity(coordinator.isShelfOpen ? 1 : 0)
                        .animation(.easeIn(duration: 0.12), value: coordinator.isShelfOpen)
                        // Тридцать две точки, а не шестнадцать: разделитель
                        // стоит посередине зазора, и от колонки плеера он
                        // отбит так же, как от списка. С прежним отступом
                        // линия липла к кнопкам транспорта.
                        .padding(.leading, Shelf.gap)
                        // Полка встаёт на своё место сразу и целиком: её
                        // открывает растущий корпус, как штору, — своего
                        // движения ей не нужно. А уходит она раньше, чем
                        // корпус успевает до неё дойти: схлопываться должна
                        // пустая коробка.
                        .transition(
                            .asymmetric(
                                insertion: .identity,
                                removal: .opacity.animation(.easeIn(duration: 0.12))
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CurtainCentered {
                if coordinator.needsAutomation {
                    automationHint
                        .transition(.opacity)
                } else if coordinator.needsAccessibility {
                    accessibilityHint
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Свечение выходит за поля содержимого до самых краёв корпуса:
        // иначе цветное пятно обрывается по невидимой рамке и читается
        // как прямоугольник, а не как свет из-под обложки.
        .background(
            ZStack(alignment: .bottom) {
                // И свет, и волна разложены сразу по полной ширине —
                // корпус их только открывает, как и всю остальную начинку.
                //
                // Свет одно время ехал вместе со шторкой: его пятно у
                // правого края растекалось с той же скоростью, с какой
                // открывался корпус. Выглядело это как съезжающий вбок фон
                // — и на раскрытии, и на схлопывании. Фон должен стоять:
                // движется корпус, а не то, что под ним.
                glow
                    .padding(glowBleed)
                    .allowsHitTesting(false)

                // Волну по той же причине держим отдельно: живи она в
                // едущем слое, её растягивало бы из узкой в широкую, и
                // гребни разъезжались бы вслед за шторкой. Поверх
                // содержимого её класть всё так же нельзя — буквы на
                // бегущей линии не читаются.
                if settings.musicVisualizer {
                    BassWave(
                        tint: tint,
                        active: coordinator.info?.isPlaying == true,
                        paused: !isSettled,
                        shelfReserve: shelfSpace
                    )
                    .frame(height: 300)
                    .transition(.opacity)
                    .padding(glowBleed)
                    .allowsHitTesting(false)
                }
            }
        )
        // Двигается только то, что меняет раскладку: очередь и строки
        // доступа. Пружина, чтобы стрелки долетали, а не прыгали.
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: coordinator.needsAccessibility)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: coordinator.needsAutomation)
    }

    /// Цвет обложки, разлитый вправо. Слева остаётся чистый чёрный —
    /// там панель срастается с вырезом, и любой цвет выдал бы стык.
    private var glow: some View {
        // Место под полку из ширины вычитаем: свет считается по панели без
        // неё и потому не переезжает, когда полка выезжает.
        Glow(tint: tint, paused: !isSettled, shelfReserve: shelfSpace)
    }

    /// Цвет обложки считаем один раз на перерисовку и отдаём обоим слоям:
    /// разбор кэширован, но сам ключ — хэш байтов картинки, и лишний
    /// вызов не бесплатен.
    private var tint: Color? {
        ArtworkColor.dominant(coordinator.info?.artwork)
    }

    /// Насколько свечение вылезает за поля содержимого — ровно на те
    /// отступы, которыми панель отбивает модуль от своих краёв.
    private var glowBleed: EdgeInsets {
        EdgeInsets(
            top: -contentTopInset,
            leading: -NotchTheme.contentLeading,
            bottom: -contentBottomInset,
            trailing: -NotchTheme.contentPadding
        )
    }

    /// Первая строка: трек, имя источника или выбранный, но закрытый плеер.
    private var title: String {
        if let info = coordinator.info {
            return info.isSourceOnly ? info.source : info.title
        }
        if let player = coordinator.selectedPlayer, !coordinator.selectedIsRunning {
            return "\(player.displayName) — \(settings.t(.musicSourceNotRunning))"
        }
        return settings.t(.musicIdleTitle)
    }

    private var subtitle: String {
        if let info = coordinator.info {
            guard info.isSourceOnly else { return info.artist }
            // «Играет» под молчащим плеером читалось как враньё: приложение
            // открыто, звука нет — так и говорим.
            return settings.t(info.isPlaying ? .musicSourceOnly : .musicSourceSilent)
        }
        if coordinator.selectedPlayer != nil, !coordinator.selectedIsRunning {
            return settings.t(.musicSourceOpen)
        }
        return ""
    }

    /// Обложки нет — показываем иконку источника, а если он выбран руками,
    /// то и когда он закрыт: понятно, чем сейчас управляют кнопки.
    private var artworkBundleID: String? {
        coordinator.info?.sourceBundleID ?? coordinator.selectedPlayer?.bundleID
    }

    private var automationHint: some View {
        HintButton(text: settings.t(.musicNeedsAutomation)) {
            coordinator.openAutomationSettings()
        }
    }

    private var accessibilityHint: some View {
        HintButton(text: settings.t(.musicNeedsAccessibility)) {
            coordinator.requestAccessibility()
        }
    }
}

/// Правая полка: куда сходить за новым.
///
/// Выезжает справа вместо того, чтобы накрыть плеер: управление остаётся
/// на месте, и видно, что это одна панель, а не две.
///
/// Плейлисты — единственное, что плеер отдаёт дёшево. Вкладку «Дальше»
/// отсюда убрали: настоящей очереди AppleScript не отдаёт ни один плеер,
/// а порядок в плейлисте у потока Apple Music не читается вовсе — полка
/// стояла пустой. Альбомов тут нет намеренно: отдельным списком их не
/// отдаёт никто, и собирать их пришлось бы перебором всей медиатеки.
private struct Shelf: View {
    /// Зазор между колонкой плеера и полкой. Разделитель делит его не
    /// пополам, а с оглядкой на поле текста внутри строк.
    static let gap: CGFloat = 32

    @ObservedObject var coordinator: NowPlayingCoordinator
    @EnvironmentObject private var settings: AppSettings

    /// Строки проявляются по очереди, вслед за уезжающим краем корпуса.
    /// Пока его нет, они уже разложены — иначе полка перевёрстывалась бы
    /// на каждом кадре, — но невидимы: появляются там, где шторка их уже
    /// открыла, а не все разом на готовом месте.
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Станции наверху и без прокрутки: их единицы, и это то, за
            // чем полку открывают чаще всего. Плейлисты — длинный список,
            // ему и достаётся весь остаток высоты.
            if !stations.isEmpty || coordinator.canStartStation {
                header(settings.t(.musicShelfStations))
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    if coordinator.canStartStation {
                        PlaylistRow(
                            name: settings.t(.musicStationFromTrack),
                            subtitle: settings.t(.musicStationFromTrackHint)
                        ) {
                            coordinator.startStationFromCurrentTrack()
                        }
                        .modifier(ShelfReveal(revealed: revealed, index: 0))
                    }

                    ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                        PlaylistRow(name: station.name, subtitle: stationHost(station)) {
                            coordinator.play(station)
                        }
                        .modifier(
                            ShelfReveal(
                                revealed: revealed,
                                index: index + (coordinator.canStartStation ? 1 : 0)
                            )
                        )
                    }
                }
                .padding(.bottom, 12)
            }

            header(settings.t(.musicShelfPlaylists))
                .padding(.bottom, 10)

            playlists

            Spacer(minLength: 0)
        }
        .frame(width: 200, alignment: .leading)
        .onAppear { revealed = true }
        // Разделитель стоит посередине воздуха, а не посередине зазора
        // между колонками: справа от него сначала идёт поле подсветки и
        // только потом буквы, и по кромке колонки линия оказывалась к
        // тексту дальше, чем к плееру. Считаем от текста — тогда слева и
        // справа от линии пусто одинаково.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .padding(.leading, (PlaylistRow.textInset - Self.gap) / 2)
        }
    }

    /// Станции показываем только целые: ссылку пользователь вставляет
    /// руками, и опечатку лучше не отдавать плееру вовсе.
    private var stations: [MusicStation] {
        settings.musicStations.filter(\.isPlayable)
    }

    /// Под именем станции — её адрес без «https://», чтобы отличить две
    /// одноимённые и увидеть, что ссылка вообще ведёт в Apple Music.
    private func stationHost(_ station: MusicStation) -> String {
        guard let url = URL(string: station.url), let host = url.host else { return station.url }
        return host + url.path
    }

    /// Заголовок раздела. Переключателя тут больше нет: вкладку «Дальше»
    /// убрали — настоящей очереди AppleScript не отдаёт ни один плеер, и
    /// у потока Apple Music она всегда оставалась пустой.
    private func header(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(NotchTheme.textPrimary)
            Spacer(minLength: 0)
        }
        // Заголовок отбит так же, как текст внутри строки: подсветка под
        // курсором выходит на шесть точек по обе стороны от него, а слова
        // стоят на одной линии — и заголовки, и названия.
        .padding(.horizontal, PlaylistRow.textInset)
        .modifier(ShelfReveal(revealed: revealed, index: 0))
    }

    @ViewBuilder
    private var playlists: some View {
        if coordinator.playlists.isEmpty {
            ShelfNote(text: settings.t(.musicPlaylistsEmpty))
        }

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(coordinator.playlists.enumerated()), id: \.element.id) { index, playlist in
                    PlaylistRow(
                        name: playlist.name,
                        subtitle: "\(playlist.count) \(settings.t(.musicPlaylistTracks))"
                    ) {
                        coordinator.play(playlist)
                    }
                    .modifier(ShelfReveal(revealed: revealed, index: index))
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// Проявление строки полки: чуть снизу и с задержкой по номеру.
///
/// Сдвиг маленький нарочно — строка не приезжает откуда-то, а собирается
/// на своём месте; на глаз это читается как продолжение движения корпуса,
/// а не как вторая, отдельная анимация. Дальше третьей строки задержка не
/// растёт: длинный список иначе досыпа́лся бы уже после того, как панель
/// встала.
///
/// Первая задержка — не украшение, а необходимость. Полка занимает
/// последние две сотни точек, и шторка корпуса доходит до неё примерно за
/// эти самые 0.2 секунды. Пока задержка была короче, строки проявлялись
/// за ещё не уехавшим краем — то есть не были видны вовсе, и анимация
/// выглядела как её отсутствие.
private struct ShelfReveal: ViewModifier {
    let revealed: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 6)
            .animation(
                .easeOut(duration: 0.24).delay(0.2 + Double(min(index, 3)) * 0.06),
                value: revealed
            )
    }
}

/// Строка полки, по которой можно ударить: плейлист запускается сразу,
/// без второго шага «открыть, потом play».
private struct PlaylistRow: View {
    /// Поле текста внутри подсветки. Тем же полем отбиты заголовки
    /// разделов и подпись пустой полки — тогда всё в колонке стоит по
    /// одной линии, а подсветка одинаково выходит за неё слева и справа.
    ///
    /// Шести точек не хватало: название начиналось почти от самой кромки
    /// плашки, а треугольник упирался в противоположную — подсветка
    /// читалась не полем вокруг строки, а обводкой по тексту. Четырнадцать
    /// оставляют по бокам столько же воздуха, сколько строка держит сверху
    /// и снизу вместе со своим зазором.
    static let textInset: CGFloat = 14

    let name: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Значок появляется только под курсором: иначе полка
                // превращается в столбик одинаковых треугольников.
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, Self.textInset)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? NotchTheme.accentSelection : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Подпись вместо пустого места: видно, что дело в источнике, а не в
/// панели.
private struct ShelfNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(NotchTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PlaylistRow.textInset)
            .padding(.bottom, 6)
    }
}

/// Разобранная обложка и иконки приложений.
///
/// Разбор идёт в `body`, а `body` пересчитывается от любой мелочи — от
/// тика опроса до наведения мыши. Пересобирать `NSImage` из байтов и
/// спрашивать систему об иконке приложения на каждой такой перерисовке
/// значит платить за одно и то же много раз, и заметнее всего это ровно
/// в момент раскрытия, когда плеер строится с нуля.
///
/// Картинку распаковываем сразу, один раз. `NSImage(data:)` держит JPEG
/// как есть, и Core Animation распаковывал его заново на каждую новую
/// подложку слоя — у свёрнутого выреза это случалось на каждом опросе
/// плеера, раз в полторы секунды.
@MainActor
enum ArtworkImage {
    private static var pictures: [Int: NSImage] = [:]
    private static var icons: [String: NSImage] = [:]

    static func image(_ data: Data) -> NSImage? {
        let key = fingerprint(data)
        if let cached = pictures[key] { return cached }
        guard let image = decoded(data) else { return nil }
        // Обложек за сессию много, а нужна только свежая.
        if pictures.count > 8 { pictures.removeAll() }
        pictures[key] = image
        return image
    }

    private static func decoded(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              )
        else { return NSImage(data: data) }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Ключ по размеру и краям картинки. Хэш всех байтов честнее, но это
    /// полмегабайта на каждую перерисовку — ровно та работа, от которой
    /// мы тут и уходим.
    private static func fingerprint(_ data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(64))
        hasher.combine(data.suffix(64))
        return hasher.finalize()
    }

    static func icon(bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}

private struct Artwork: View {
    let data: Data?
    var bundleID: String?
    var side: CGFloat

    /// Что именно нарисовано. Меняется — картинка растворяется в новой,
    /// а не подменяется рывком.
    private var key: String {
        "\(data?.count ?? 0)|\(bundleID ?? "")"
    }

    private var appIcon: NSImage? {
        guard let bundleID else { return nil }
        return ArtworkImage.icon(bundleID: bundleID)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(NotchTheme.accentSelection)
            picture
                .id(key)
                .transition(.opacity)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
        .animation(.easeInOut(duration: 0.25), value: key)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: side)
    }

    @ViewBuilder
    private var picture: some View {
        if let data, let image = ArtworkImage.image(data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: side * 0.45, height: side * 0.45)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 22))
                .foregroundStyle(NotchTheme.textTertiary)
        }
    }
}

/// Полоса прогресса. Место под неё занято всегда, даже когда длительность
/// неизвестна: иначе появление трека двигает транспорт, и кнопка уезжает
/// из-под пальца ровно в момент, когда по ней целятся.
///
/// По наведению полоса вырастает вдвое и обзаводится кружком: тонкая
/// линия в пять точек — мишень, в которую не попасть, а толстая всё
/// время выглядит как чужой элемент управления. Растёт только под
/// курсором — ровно тогда, когда в неё целятся.
private struct Progress: View {
    let info: NowPlayingInfo?
    /// Куда перемотать, в секундах. nil — источник перемотку не умеет.
    var onSeek: ((TimeInterval) -> Void)?

    @State private var isHovered = false
    /// Доля, за которую держится палец. Пока она есть, полоса и время
    /// показывают её, а не то, что ответил плеер: иначе цифры под
    /// курсором живут своей жизнью.
    @State private var scrub: Double?

    private var duration: TimeInterval { info?.duration ?? 0 }
    private var hasTimes: Bool { duration > 0 }
    private var canSeek: Bool { onSeek != nil && (info?.canSeek ?? false) && hasTimes }

    private var progress: Double { scrub ?? info?.progress ?? 0 }
    private var elapsed: TimeInterval {
        scrub.map { $0 * duration } ?? info?.elapsed ?? 0
    }

    /// Насколько полоса толще обычного. Ведут — держим толщину, даже
    /// если курсор ушёл за края: полоса не должна худеть под пальцем.
    private var isTall: Bool { canSeek && (isHovered || scrub != nil) }
    private var barHeight: CGFloat { isTall ? 10 : 5 }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let width = geometry.size.width

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(NotchTheme.textPrimary)
                        .frame(width: max(width * progress, 0))
                        // Опрос идёт раз в полторы секунды: без сглаживания
                        // полоса дёргается шагами. За пальцем же она обязана
                        // идти мгновенно — там сглаживание только мешает.
                        .animation(scrub == nil ? .linear(duration: 0.4) : nil, value: progress)
                }
                .frame(height: barHeight)
                // Толщину меняем в кадре, высота строки при этом постоянна:
                // полоса растёт в обе стороны от своей оси, и транспорт под
                // ней не шевелится.
                .frame(height: 12, alignment: .center)
                // Целиться курсором в пять точек нечестно — ловим на всей
                // полосе строки.
                .contentShape(Rectangle())
                .gesture(canSeek ? drag(width: width) : nil)
                .onHover { hovering in
                    guard canSeek else { return }
                    isHovered = hovering
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .frame(height: 12)
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: isTall)

            HStack {
                Text(hasTimes ? Self.time(elapsed) : "")
                Spacer(minLength: 0)
                Text(hasTimes ? "−" + Self.time(max(duration - elapsed, 0)) : "")
            }
            .font(.system(size: 11))
            // Пока ведут — время это ответ на «куда я попаду», и читать
            // его должно легче, чем обычно.
            .foregroundStyle(scrub == nil ? NotchTheme.textTertiary : NotchTheme.textSecondary)
            .monospacedDigit()
        }
    }

    /// Одним жестом и клик, и ведение: `minimumDistance: 0` превращает
    /// обычное нажатие в перемотку по месту, а протяжку — в ведение.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                scrub = fraction(value.location.x, width: width)
            }
            .onEnded { value in
                let target = fraction(value.location.x, width: width) * duration
                scrub = nil
                onSeek?(target)
            }
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    private static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct Transport: View {
    @EnvironmentObject private var settings: AppSettings

    let isPlaying: Bool
    /// Трек в избранном. nil — плеер про избранное не знает, и звёздочки
    /// у него нет вовсе.
    let favorite: Bool?
    let toggleFavorite: () -> Void
    /// Трек в дизлайке. nil — плеер про дизлайк не знает: так живут все,
    /// кроме тех, чью панель мы читаем деревом доступа.
    let disliked: Bool?
    let toggleDislike: () -> Void
    let isShelfOpen: Bool
    /// Полке есть что показать. Нет — кнопки нет вовсе: открывать
    /// нечего, а пустая полка хуже отсутствующей.
    let hasShelf: Bool
    let send: (TransportCommand) -> Void
    let toggleShelf: () -> Void

    var body: some View {
        // Тройка стоит по центру полосы прогресса, а очередь — поверх, у
        // правого края. Если положить их в один ряд, появление кнопки
        // очереди сдвигает play, и целиться приходится заново.
        HStack(spacing: 0) {
            // Слева — оценка трека, справа — очередь; тройка ровно между
            // ними. Место под обе занято всегда: появись кнопка на пустом
            // месте, она сдвинула бы play, и целиться пришлось бы заново.
            // По той же причине обе стороны одной ширины — на две кнопки,
            // даже когда слева стоит одна звёздочка.
            ZStack {
                // Пустой Group стек выбрасывает целиком, вместе с рамкой,
                // и тройка уезжает влево. Прозрачная подложка держит
                // место честно — с ней ширина не зависит от содержимого.
                Color.clear
                HStack(spacing: 0) {
                    if let disliked {
                        TransportButton(
                            symbol: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                            size: 15,
                            isActive: disliked,
                            help: settings.t(disliked ? .musicDislikeRemove : .musicDislikeAdd),
                            action: toggleDislike
                        )
                        .frame(width: 40, height: 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    if let favorite {
                        TransportButton(
                            symbol: favorite ? "star.fill" : "star",
                            size: 15,
                            isActive: favorite,
                            help: settings.t(favorite ? .musicFavoriteRemove : .musicFavoriteAdd),
                            action: toggleFavorite
                        )
                        .frame(width: 40, height: 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
            }
            .frame(width: 80, height: 40)

            Spacer(minLength: 8)

            HStack(spacing: 20) {
                TransportButton(symbol: "backward.fill", size: 20) { send(.previous) }

            Button {
                send(.playPause)
            } label: {
                ZStack {
                    Squircle().fill(Color.white.opacity(0.18))
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 54, height: 54)
                .contentShape(Squircle())
            }
            .buttonStyle(.plain)

                TransportButton(symbol: "forward.fill", size: 20) { send(.next) }
            }

            Spacer(minLength: 8)

            // Место под кнопку занято всегда — как и под звёздочку
            // слева: появись она на пустом месте, тройка сдвинулась бы,
            // и целиться в play пришлось бы заново.
            ZStack {
                Color.clear
                if hasShelf {
                    TransportButton(
                        symbol: "music.note.list",
                        size: 15,
                        isActive: isShelfOpen,
                        help: settings.t(isShelfOpen ? .musicShelfHide : .musicShelfShow),
                        action: toggleShelf
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: 80, height: 40)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Бегущая волна.
///
/// Слева направо — то есть туда же, куда идёт полоса прогресса: движение
/// панели должно быть одно, иначе глаз ловит два разных ритма.
///
/// Уровень волна придумывает сама. Раньше он брался из системного звука
/// через ScreenCaptureKit, и это стоило дороже, чем давало: каждый старт
/// и остановка потока пересобирали аудиотракт, а панель открывается и
/// закрывается постоянно — музыка спотыкалась на каждое движение челки.
/// Заодно ушли разрешение на запись экрана и его индикатор.
private struct BassWave: View {
    let tint: Color?
    /// Музыка играет. На паузе волна не исчезает мгновенно, а оседает и
    /// расплывается — это тот же свет, просто он замолчал.
    var active: Bool = true
    /// Панель едет — волна стоит. Кадры сейчас нужнее раскрытию.
    var paused: Bool = false
    /// Сколько точек справа отдано полке. Волна её не считает своей:
    /// иначе выезд полки растягивал бы рисунок.
    var shelfReserve: CGFloat = 0

    /// Сколько точек волна проходит за секунду.
    ///
    /// Всё, что касается формы, меряем в точках, а не в долях ширины.
    /// Доли выглядели проще, но привязывали рисунок к размеру панели: она
    /// шире на ширину полки, и стоило той выехать, как гребни разъезжались
    /// — волна будто сдвигалась вбок, хотя её никто не двигал.
    private let speed: Double = 110

    /// Длина самой длинной из трёх волн. Остальные короче во столько раз,
    /// во сколько чаще их гребни.
    private let wavelength: Double = 600

    /// На каком отрезке слева волна поднимается от нуля до полной высоты.
    /// Там панель срастается с вырезом, и любое движение выдаёт стык.
    private let liftIn: Double = 270

    /// Появление и уход. Долго нарочно: короткий фейд читается как
    /// включение лампочки, а не как расплывающийся свет.
    private let fade: Double = 0.7

    @State private var visible = false
    /// Волна ещё растворяется, хотя музыка уже остановлена: пока идёт
    /// этот хвост, кадры нужны — иначе картинка замрёт на полпути.
    @State private var isFading = false
    /// Собственные часы волны и сглаживание уровня. Ссылочный тип
    /// нарочно: оба значения меняются на каждой перерисовке, и `@State`
    /// гонял бы тело зря.
    @State private var clock = WaveClock()

    /// Пока панель едет, волна замерла: её часы стоят.
    private var isRunning: Bool { !paused && (active || isFading) }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isRunning)) { timeline in
            // Часы свои, а не системные. Считай мы фазу от абсолютного
            // времени, волна ехала бы и на паузе: раскрытие перевёрстывает
            // панель каждый кадр, и каждая такая перерисовка приносила бы
            // новую дату — то есть новый сдвиг.
            let phase = clock.phase(at: timeline.date, running: isRunning, speed: speed)
            // Уровень догоняем плавно: вверх быстро, вниз медленно. Плеер
            // на паузе обнуляет его разом, и без этого волна не оседала бы,
            // а пропадала рывком.
            let level = clock.swell(
                at: timeline.date,
                running: isRunning,
                settling: !active
            )

            Canvas { context, size in
                let color = tint ?? .white
                let anchor = max(size.width - shelfReserve, 1)

                // Три слоя с разной длиной волны: одна синусоида читается
                // как заставка медиаплеера, а несколько внахлёст дают
                // неповторяющееся движение.
                //
                // Нижнему, самому длинному, добавлено своё размытие: он
                // работает подложкой — мягким светом, по которому ходят два
                // других. Размажь их заодно с ним, и от волны останется
                // ровное пятно.
                let layers: [(waves: Double, amplitude: Double, opacity: Double, blur: Double)] = [
                    (1.2, 1.0, 1.0, 26),
                    (2.1, 0.62, 0.66, 0),
                    (3.4, 0.36, 0.42, 0)
                ]

                for layer in layers {
                    let amplitude = size.height * 0.28 * layer.amplitude * (0.12 + level * 0.88)
                    let span = wavelength / layer.waves
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))

                    var x: CGFloat = 0
                    while x <= size.width {
                        let angle = (Double(x) - phase) / span * 2 * .pi
                        let fade = min(Double(x) / liftIn, 1)
                        let y = size.height * 0.78 - sin(angle) * amplitude * fade
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 3
                    }

                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()

                    let paint = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [
                            color.opacity(layer.opacity * (0.3 + level * 0.7)),
                            color.opacity(0)
                        ]),
                        // Тоже от панели без полки: поедь эта точка вместе
                        // с полкой, и свет под волной пополз бы вбок ровно
                        // так же, как раньше ползли гребни.
                        startPoint: CGPoint(x: anchor, y: size.height),
                        endPoint: CGPoint(x: anchor * 0.1, y: 0)
                    )

                    guard layer.blur > 0 else {
                        context.fill(path, with: paint)
                        continue
                    }
                    // Размытие внутри холста, а не поверх всего: снаружи
                    // модификатор накрыл бы три слоя разом.
                    context.drawLayer { soft in
                        soft.addFilter(.blur(radius: layer.blur))
                        soft.fill(path, with: paint)
                    }
                }
            }
        }
        // Уходя, волна не только гаснет, но и размывается: свет растекается,
        // а не выключается.
        .blur(radius: visible ? 16 : 30)
        .opacity(visible ? 1 : 0)
        .blendMode(.plusLighter)
        .onAppear { setVisible(active) }
        .onChange(of: active) { _, isActive in setVisible(isActive) }
    }

    private func setVisible(_ isActive: Bool) {
        if isActive { isFading = false }
        withAnimation(.easeInOut(duration: fade)) { visible = isActive }
        guard !isActive else { return }
        isFading = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(fade * 1.2 * 1_000_000_000))
            isFading = false
        }
    }
}

/// Часы волны: фаза бега и уровень баса, догоняющий музыку.
///
/// Считаем по времени кадра, а не по их числу: `TimelineView` не обещает
/// ровной частоты, и на просадке волна иначе оседала бы рывками. А пока
/// часы остановлены, оба значения не меняются вовсе — сколько бы раз
/// SwiftUI ни перерисовал волну, картинка будет та же.
@MainActor
private final class WaveClock {
    private var travelled: Double = 0
    /// Сколько секунд волна живёт. По ним считается её высота.
    private var elapsed: Double = 0
    private var smoothed: Double = 0
    private var last: Date?

    /// Сколько ширины волна уже пробежала.
    func phase(at date: Date, running: Bool, speed: Double) -> Double {
        travelled += delta(to: date, running: running) * speed
        return travelled
    }

    /// Насколько волна сейчас высокая, 0…1.
    ///
    /// Три синуса с несоизмеримыми периодами: по отдельности каждый —
    /// заставка медиаплеера, а вместе они не повторяются и читаются как
    /// живое дыхание. Самый медленный задаёт настроение куплета, самый
    /// быстрый — отдельные всплески.
    ///
    /// - Parameter settling: музыка остановлена, волна оседает. Только
    ///   здесь спад медленный: волна не выключается, а растекается.
    func swell(at date: Date, running: Bool, settling: Bool) -> Double {
        elapsed += delta(to: date, running: running)

        let target: Double
        if settling {
            target = 0
        } else {
            let slow = sin(elapsed * 0.31 + 2.6)
            let mid = sin(elapsed * 0.9)
            let fast = sin(elapsed * 1.37 + 1.3)
            let mixed = (slow * 0.18 + mid * 0.5 + fast * 0.32 + 1) / 2
            // Нижнюю треть отрезаем: волна не должна проваливаться в
            // ноль на ровном месте — в ноль её опускает только пауза.
            target = 0.3 + mixed * 0.7
        }

        // Само по себе значение уже плавное, сглаживание тут только
        // затем, чтобы волна не дёргалась на старте и на паузе.
        smoothed += (target - smoothed) * min(delta(to: date, running: running) * (settling ? 1.6 : 6), 1)
        return smoothed
    }

    /// Шаг времени. Оба значения просят его в одном и том же кадре, а
    /// двигаться он должен один раз — второму отдаём уже посчитанный.
    private var step: (date: Date, value: Double)?

    private func delta(to date: Date, running: Bool) -> Double {
        if let step, step.date == date { return step.value }
        // Первый кадр и долгая пауза между ними — не повод дёргать волну.
        let value = running ? (last.map { min(date.timeIntervalSince($0), 0.1) } ?? 0) : 0
        last = running ? date : nil
        step = (date, value)
        return value
    }
}

/// Свет из-под обложки. Не картинка, а состояние: два пятна медленно
/// расходятся и сходятся в противофазе, поэтому панель кажется живой,
/// а не залитой градиентом. Дышит медленно — быстрее начинает отвлекать
/// от того, ради чего панель открыли.
/// Держит содержимое по центру открытой части корпуса, а не по центру
/// раскладки.
///
/// Начинка разложена по полной ширине сразу, поэтому всё, что стоит по
/// центру, во время движения шторки оказывается правее видимой области.
/// Строке подсказки это заметно: она одна тут стоит серединой. Отнимаем
/// справа ещё закрытую полосу — и подсказка едет вместе с корпусом.
private struct CurtainCentered<Content: View>: View {
    @Environment(\.notchCurtainInset) private var curtainInset

    @ViewBuilder var content: Content

    var body: some View {
        content.padding(.trailing, curtainInset)
    }
}

private struct Glow: View {
    let tint: Color?
    /// Панель едет — свет не дышит: пересборка градиентов на каждом кадре
    /// как раз и отбирала кадры у раскрытия.
    var paused: Bool = false

    /// Ширина, от которой считаются пятна: без места, отданного полке.
    ///
    /// Иначе свет привязан к правому краю панели, а край с открытой
    /// полкой на две сотни точек дальше — и пятно переезжает туда, стоит
    /// полке выехать. Со стороны это читается как съезжающий вбок фон,
    /// хотя на деле он просто пересчитан по новой ширине. Считаем от
    /// постоянной ширины, а рисуем по всей: свет стоит на месте, а в
    /// полку затекает его хвост.

    /// Два хода вместо одного: вдох-выдох и снос пятна вбок. Периоды
    /// нарочно не кратные — иначе оба движения сходятся в одно пульсирующее
    /// и свет читается как мигание. Разойдясь, они дают медленный
    /// неповторяющийся снос: глазу видно, что свет живой, а считать его
    /// ритм не получается.
    private let breathPeriod: Double = 11
    private let driftPeriod: Double = 17

    /// Сколько точек справа отдано полке — их из ширины и вычитаем.
    var shelfReserve: CGFloat = 0

    var body: some View {
        // Фазу берём из времени и пересобираем градиент каждый кадр.
        // Через `@State` + `withAnimation` не работает вовсе: параметры
        // градиента SwiftUI не интерполирует — состояние перескакивало
        // сразу к конечному значению, и «дыхание» было видно только как
        // редкий рывок раз в несколько секунд. Тот же приём, что у волны
        // по басу.
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
            GeometryReader { geometry in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((sin(time / breathPeriod * 2 * .pi) + 1) / 2)
                let drift = CGFloat((sin(time / driftPeriod * 2 * .pi) + 1) / 2)
                let full = max(geometry.size.width, 1)
                let anchor = max(full - shelfReserve, 1)
                // Доля постоянной ширины в нынешней: по ней переводим
                // точки в доли, которых просит градиент.
                let k = anchor / full

                ZStack {
                    if let tint {
                        // Оба пятна сдвинуты вправо и вниз: наверху слева
                        // проходит вырез, и свет, заехавший под него,
                        // обрывался жёсткой кромкой вместо того, чтобы
                        // растекаться из-под обложки.
                        // Правое пятно ходит и по вертикали, и поперёк —
                        // оно у самого края, и именно его движение видно
                        // на открытой полке.
                        RadialGradient(
                            colors: [tint.opacity(0.9), tint.opacity(0)],
                            center: UnitPoint(
                                x: (1.12 - drift * 0.14) * k,
                                y: 0.56 + phase * 0.3
                            ),
                            startRadius: 0,
                            endRadius: anchor * (0.68 + phase * 0.26)
                        )
                        RadialGradient(
                            colors: [tint.opacity(0.55), tint.opacity(0)],
                            center: UnitPoint(
                                x: (0.94 - drift * 0.16) * k,
                                y: 1.02 - phase * 0.42
                            ),
                            startRadius: 0,
                            endRadius: anchor * (0.52 - drift * 0.16)
                        )
                        // Чёрным гасим левый край — там панель срастается с
                        // вырезом.
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.92), location: 0.2 * k),
                                .init(color: .black.opacity(0.45), location: 0.46 * k),
                                .init(color: .black.opacity(0.1), location: 0.74 * k),
                                .init(color: .black.opacity(0), location: 1 * k)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        // И верхнюю полосу: она приходится ровно на вырез и
                        // на строку значков над содержимым.
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.75), location: 0.16),
                                .init(color: .black.opacity(0.2), location: 0.36),
                                .init(color: .black.opacity(0), location: 0.58)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                // Цвет нового трека не подменяется рывком, а перетекает.
                .animation(.easeInOut(duration: 0.6), value: tint)
            }
        }
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    var isActive: Bool = false
    var help: String?
    let action: () -> Void

    @State private var isHovered = false

    /// Кружок под значком — по значку, а не один на всех.
    ///
    /// Сорока точек хватало звёздочке и списку, но стрелки перемотки
    /// крупнее и вдобавок широкие: в том же круге они упирались в его
    /// край, и подсветка читалась как обрезанная. Поля держим примерно в
    /// половину кегля с каждой стороны.
    private var diameter: CGFloat { max(40, (size * 2.4).rounded()) }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(
                    isActive || isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary
                )
                .frame(width: diameter, height: diameter)
                .background {
                    if isActive {
                        Squircle().fill(Color.white.opacity(0.16))
                    } else if isHovered {
                        Squircle().fill(Color.white.opacity(0.07))
                    }
                }
                .contentShape(Squircle())
        }
        .buttonStyle(.plain)
        .notchHelp(help)
        .animation(.easeOut(duration: 0.18), value: isActive)
        .onHover { isHovered = $0 }
    }
}


/// Выбор плеера: «Авто» или конкретное приложение.
///
/// Нужен там, где источников несколько: автоматика берёт того, кто
/// первым ответил, а это не всегда тот, кем хочется управлять.
/// Показываем иконками самих приложений — их узнают быстрее, чем
/// названия в выпадающем списке, и в строку это влезает целиком.
private struct SourceStrip: View {
    @ObservedObject var coordinator: NowPlayingCoordinator
    @EnvironmentObject private var settings: AppSettings

    /// Общее пространство для подсветки: одна капсула переезжает между
    /// кнопками, а не гаснет в одной и вспыхивает в другой.
    @Namespace private var highlight

    /// Пружина без раскачки: переключение должно казаться быстрым.
    private static let slide = Animation.spring(response: 0.3, dampingFraction: 0.8)

    var body: some View {
        HStack(spacing: 2) {
            SourceChip(
                isSelected: coordinator.source == .auto,
                help: settings.t(.musicSourceAuto),
                highlight: highlight
            ) {
                select(.auto)
            } content: {
                Text(settings.t(.musicSourceAuto))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.textPrimary)
            }

            ForEach(MusicPlayer.installed) { player in
                SourceChip(
                    isSelected: coordinator.source == .player(player.bundleID),
                    help: player.displayName,
                    highlight: highlight
                ) {
                    select(.player(player.bundleID))
                } content: {
                    AppIcon(bundleID: player.bundleID, size: 16)
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func select(_ source: MusicSource) {
        withAnimation(Self.slide) { coordinator.source = source }
    }
}

/// Кнопка в полоске выбора: невыбранная притушена и чуть меньше,
/// выбранная — под общей переезжающей капсулой.
private struct SourceChip<Content: View>: View {
    let isSelected: Bool
    let help: String
    let highlight: Namespace.ID
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    init(
        isSelected: Bool,
        help: String,
        highlight: Namespace.ID,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.help = help
        self.highlight = highlight
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(height: 18)
                .padding(.horizontal, 6)
                .opacity(isSelected ? 1 : (isHovered ? 0.85 : 0.45))
                .scaleEffect(isSelected ? 1 : 0.94)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(NotchTheme.accentSelection)
                            .matchedGeometryEffect(id: "sourceHighlight", in: highlight)
                    } else if isHovered {
                        Capsule().fill(Color.white.opacity(0.05))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .notchHelp(help)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// Иконка приложения по bundle id.
private struct AppIcon: View {
    let bundleID: String
    var size: CGFloat

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(NotchTheme.textTertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Кликабельная строка-предупреждение.
///
/// Выглядела как обычный текст, поэтому нажать на неё никто не догадывался:
/// добавлены подсветка, курсор-палец и выравнивание значка по базовой
/// линии текста — иначе значок висит выше строки.
private struct MiniButton: View {
    let text: String
    let symbol: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
                Text(text)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
            }
            .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(isHovered ? NotchTheme.accentSelection : .clear)
            }
            .overlay {
                Capsule().strokeBorder(NotchTheme.textTertiary.opacity(0.35), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct HintButton: View {
    let text: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(text)
                    .font(.system(size: 10))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(isHovered ? NotchTheme.textSecondary : NotchTheme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(isHovered ? NotchTheme.accentSelection : .clear)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
