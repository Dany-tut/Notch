import SwiftUI
import UniformTypeIdentifiers

/// Программы — вместо Launchpad, которого больше нет в macOS.
///
/// От Launchpad берём то, по чему скучают: крупные значки под мышь, папки
/// и свой порядок. Закреплённые идут первым рядом и переставляются
/// перетаскиванием, папки — плитками следом, дальше всё остальное по
/// алфавиту. Правый клик — закрепить, положить в папку, показать в Finder.
struct AppsModule: NotchModule {
    let id = "apps"
    let titleKey: L10n.Key = .moduleApps
    let symbol = "square.grid.2x2"

    let store: AppsStore

    var preferredHeight: CGFloat { 260 }

    func makeContent() -> some View {
        AppsContent(store: store)
    }

    func makeModes() -> some View {
        AppsModes(store: store)
    }

    var modesWidth: CGFloat { 30 }
}

private struct AppsModes: View {
    @ObservedObject var store: AppsStore
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        SearchField(
            text: $store.query,
            isOpen: $store.isSearching,
            placeholder: settings.t(.searchPlaceholder),
            help: settings.t(.searchPlaceholder),
            isFocused: $isSearchFocused
        )
    }
}

private enum AppsMetrics {
    static let icon: CGFloat = 40
    static let cell: CGFloat = 66
    static let cellHeight: CGFloat = 70
    static let columns = [GridItem(.adaptive(minimum: cell, maximum: cell + 8), spacing: 2)]
}

private struct AppsContent: View {
    @ObservedObject var store: AppsStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if store.apps.isEmpty {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.isSearching {
                search
            } else if let folder = store.openFolder {
                FolderPage(store: store, folder: folder)
            } else {
                home
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.refreshIfNeeded() }
        .animation(.snappy(duration: 0.22), value: store.openFolderID)
    }

    private var search: some View {
        let results = store.searchResults
        return Group {
            if results.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: settings.t(.appsNoResults),
                    hint: store.query
                )
            } else {
                // Края — как у всей панели: сетка уходит под строку
                // заголовка и тает в размытии, а не обрезается по рамке.
                NotchScroll {
                    LazyVGrid(columns: AppsMetrics.columns, spacing: 4) {
                        ForEach(results) { app in AppCell(store: store, app: app) }
                    }
                }
            }
        }
    }

    private var home: some View {
        NotchScroll {
            VStack(alignment: .leading, spacing: 6) {
                PinnedRow(store: store)

                LazyVGrid(columns: AppsMetrics.columns, spacing: 4) {
                    ForEach(store.layout.folders) { folder in
                        FolderCell(store: store, folder: folder)
                    }
                    ForEach(store.loose) { app in
                        AppCell(store: store, app: app)
                    }
                }
            }
        }
    }
}

/// Закреплённые: первый ряд, свой порядок. Пустой ряд показывает, куда
/// тянуть, — иначе про закрепление никто не узнает.
private struct PinnedRow: View {
    @ObservedObject var store: AppsStore
    @EnvironmentObject private var settings: AppSettings
    @State private var isTargeted = false

    var body: some View {
        let pinned = store.pinnedApps
        Group {
            if pinned.isEmpty {
                Text(settings.t(.appsPinHint))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 30)
            } else {
                LazyVGrid(columns: AppsMetrics.columns, spacing: 4) {
                    ForEach(pinned) { app in
                        AppCell(store: store, app: app)
                            // Отпустили на закреплённой — встаёт перед ней.
                            .dropDestination(for: String.self) { paths, _ in
                                guard let path = paths.first, path != app.id else { return false }
                                withAnimation(.snappy(duration: 0.2)) { store.pin(path, before: app.id) }
                                return true
                            }
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NotchTheme.accentSelection.opacity(isTargeted ? 0.8 : 0.35))
        }
        // Отпустили на пустом месте ряда — в конец.
        .dropDestination(for: String.self) { paths, _ in
            guard let path = paths.first else { return false }
            withAnimation(.snappy(duration: 0.2)) { store.pin(path) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct AppCell: View {
    @ObservedObject var store: AppsStore
    let app: AppEntry
    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false

    var body: some View {
        Button { store.launch(app) } label: {
            VStack(spacing: 3) {
                Image(nsImage: store.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: AppsMetrics.icon, height: AppsMetrics.icon)
                    .scaleEffect(isHovered ? 1.06 : 1)
                Text(app.name)
                    .font(.system(size: 10))
                    .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // Запущенная — точка, как в Dock.
                Circle()
                    .fill(NotchTheme.textTertiary)
                    .frame(width: 3, height: 3)
                    .opacity(store.isRunning(app) ? 1 : 0)
            }
            .frame(width: AppsMetrics.cell, height: AppsMetrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) { isHovered = hovering }
        }
        .draggable(app.id) {
            Image(nsImage: store.icon(for: app))
                .resizable()
                .frame(width: AppsMetrics.icon, height: AppsMetrics.icon)
        }
        .contextMenu { menu }
        .notchHelp(app.name)
    }

    @ViewBuilder
    private var menu: some View {
        if store.isPinned(app) {
            Button(settings.t(.appsUnpin)) { store.unpin(app) }
        } else {
            Button(settings.t(.appsPin)) { store.pin(app.id) }
        }

        Menu(settings.t(.appsAddToFolder)) {
            ForEach(store.layout.folders) { folder in
                Button(folder.name) { store.add(app.id, to: folder.id) }
                    .disabled(folder.items.contains(app.id))
            }
            if !store.layout.folders.isEmpty { Divider() }
            Button(settings.t(.appsNewFolder)) {
                store.newFolder(with: app, name: settings.t(.appsNewFolder))
            }
        }

        if store.folder(containing: app) != nil {
            Button(settings.t(.appsRemoveFromFolder)) { store.removeFromFolder(app) }
        }

        Divider()
        Button(settings.t(.appsReveal)) { store.reveal(app) }
    }
}

/// Папка в общей сетке: мозаика из первых четырёх значков, как в
/// Launchpad. На неё можно бросить программу.
private struct FolderCell: View {
    @ObservedObject var store: AppsStore
    let folder: AppFolder
    @EnvironmentObject private var settings: AppSettings
    @State private var isHovered = false
    @State private var isTargeted = false

    var body: some View {
        Button { store.openFolderID = folder.id } label: {
            VStack(spacing: 3) {
                mosaic
                Text(folder.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isHovered ? NotchTheme.textPrimary : NotchTheme.textSecondary)
                    .lineLimit(1)
                Color.clear.frame(width: 3, height: 3)
            }
            .frame(width: AppsMetrics.cell, height: AppsMetrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .dropDestination(for: String.self) { paths, _ in
            guard let path = paths.first else { return false }
            withAnimation(.snappy(duration: 0.2)) { store.add(path, to: folder.id) }
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button(settings.t(.appsDeleteFolder), role: .destructive) { store.deleteFolder(folder.id) }
        }
    }

    private var mosaic: some View {
        let apps = Array(store.items(of: folder).prefix(4))
        let tile: CGFloat = 16
        return LazyVGrid(columns: [GridItem(.fixed(tile), spacing: 3), GridItem(.fixed(tile), spacing: 3)], spacing: 3) {
            ForEach(apps) { app in
                Image(nsImage: store.icon(for: app)).resizable().frame(width: tile, height: tile)
            }
        }
        .frame(width: AppsMetrics.icon, height: AppsMetrics.icon)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isTargeted ? 0.28 : isHovered ? 0.18 : 0.12))
        }
        .scaleEffect(isTargeted ? 1.1 : 1)
    }
}

/// Раскрытая папка: назад, название (правится прямо тут) и её программы.
private struct FolderPage: View {
    @ObservedObject var store: AppsStore
    let folder: AppFolder
    @EnvironmentObject private var settings: AppSettings
    @State private var name = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        NotchScroll {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        store.openFolderID = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NotchTheme.textSecondary)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchTheme.textPrimary)
                        .focused($isEditing)
                        .onTapGesture { NotchPanel.focusForTyping() }
                        .onSubmit { store.rename(folder.id, to: name) }
                        .onChange(of: isEditing) { _, editing in
                            if !editing { store.rename(folder.id, to: name) }
                        }
                }

                LazyVGrid(columns: AppsMetrics.columns, spacing: 4) {
                    ForEach(store.items(of: folder)) { app in
                        AppCell(store: store, app: app)
                    }
                }
            }
        }
        .onAppear { name = folder.name }
        .onChange(of: folder.id) { _, _ in name = folder.name }
    }
}
