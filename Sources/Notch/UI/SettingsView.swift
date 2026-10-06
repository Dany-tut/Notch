import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var snippets: SnippetStore
    @ObservedObject var music: NowPlayingCoordinator
    @ObservedObject var clipboard: ClipboardStore
    let feedback: Feedback

    var body: some View {
        TabView {
            GeneralSettings(settings: settings, feedback: feedback)
                .tabItem { Label(settings.t(.settingsTabGeneral), systemImage: "gearshape") }

            ModulesSettings(settings: settings)
                .tabItem { Label(settings.t(.settingsTabModules), systemImage: "square.grid.2x2") }

            IslandSettings(settings: settings)
                .tabItem { Label(settings.t(.settingsTabIsland), systemImage: "circle.circle") }

            HotkeySettings(settings: settings)
                .tabItem { Label(settings.t(.settingsTabHotkeys), systemImage: "keyboard") }

            PrivacySettings(settings: settings, clipboard: clipboard)
                .tabItem { Label(settings.t(.settingsTabPrivacy), systemImage: "lock") }

            SnippetsSettings(settings: settings, store: snippets)
                .tabItem { Label(settings.t(.settingsTabSnippets), systemImage: "pin") }

            StationsSettings(settings: settings)
                .tabItem {
                    Label(settings.t(.settingsTabStations), systemImage: "dot.radiowaves.left.and.right")
                }

            #if PRO
            LicenseSettings(settings: settings)
                .tabItem { Label(settings.t(.settingsTabLicense), systemImage: "key") }
            #endif

            AboutSettings(settings: settings, music: music)
                .tabItem { Label(settings.t(.settingsTabAbout), systemImage: "info.circle") }
        }
        .frame(width: 640, height: 420)
    }
}

// MARK: - Основные

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    let feedback: Feedback

    var body: some View {
        Form {
            Section {
                Picker(settings.t(.settingsLanguage), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(settings.name(for: option)).tag(option)
                    }
                }
            } footer: {
                Caption(settings.t(.settingsLanguageHint))
            }

            Section {
                Toggle(settings.t(.settingsHaptics), isOn: $settings.hapticsEnabled)
                Toggle(settings.t(.settingsSound), isOn: $settings.soundEnabled)

                Picker(settings.t(.settingsSoundChoice), selection: $settings.sound) {
                    ForEach(NotchSound.allCases) { option in
                        Text(settings.name(for: option)).tag(option)
                    }
                }
                .disabled(!settings.soundEnabled)
                .onChange(of: settings.sound) { _, new in
                    feedback.preview(new)
                }

                HStack {
                    Text(settings.t(.settingsVolume))
                    Slider(value: $settings.feedbackVolume, in: 0...0.4)
                    Button(settings.t(.settingsSoundPreview)) {
                        feedback.preview(settings.sound)
                    }
                }
                .disabled(!settings.soundEnabled || settings.sound == .none)
            } header: {
                Text(settings.t(.settingsTabFeedback))
            } footer: {
                Caption(settings.t(.settingsFeedbackHint))
            }

            Section {
                Toggle(settings.t(.settingsLaunchAtLogin), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
            } footer: {
                if let error = settings.launchAtLoginError {
                    Caption(error).foregroundStyle(.red)
                } else if !LaunchAtLogin.isAvailable {
                    Caption(settings.t(.settingsLaunchUnavailable))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Модули

private struct ModulesSettings: View {
    @ObservedObject var settings: AppSettings

    /// Дескрипторы в текущем пользовательском порядке.
    private var ordered: [ModuleCatalog.Descriptor] {
        let order = settings.moduleOrder
        return ModuleCatalog.descriptors.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.element.id) ?? (order.count + lhs.offset)
            let r = order.firstIndex(of: rhs.element.id) ?? (order.count + rhs.offset)
            return l < r
        }.map(\.element)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(ordered) { descriptor in
                    Toggle(isOn: binding(for: descriptor.id)) {
                        Label(settings.t(descriptor.titleKey), systemImage: descriptor.symbol)
                    }
                }
                .onMove(perform: move)
            }
            Caption(settings.t(.settingsModulesReorderHint))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(id) },
            set: { settings.setEnabled($0, for: id) }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = ordered.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        settings.moduleOrder = ids
    }
}

// MARK: - Остров

private struct IslandSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(IslandIndicator.allCases) { indicator in
                    Toggle(isOn: Binding(
                        get: { settings.isIslandEnabled(indicator) },
                        set: { settings.setIslandEnabled($0, for: indicator) }
                    )) {
                        Label(settings.t(indicator.titleKey), systemImage: indicator.symbol)
                    }

                    Picker(settings.t(.islandSide), selection: Binding(
                        get: { settings.islandSide(for: indicator) },
                        set: { settings.setIslandSide($0, for: indicator) }
                    )) {
                        ForEach(IslandSide.allCases) { side in
                            Text(settings.t(side.titleKey)).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!settings.isIslandEnabled(indicator))
                }
            } footer: {
                Caption(settings.t(.settingsIslandHint))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Заготовки

private struct SnippetsSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: SnippetStore

    @State private var newLabel = ""
    @State private var newValue = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.snippets) { snippet in
                    HStack(spacing: 8) {
                        TextField(
                            settings.t(.settingsSnippetLabel),
                            text: binding(for: snippet, keyPath: \.label)
                        )
                        .frame(width: 140)
                        TextField(
                            settings.t(.settingsSnippetValue),
                            text: binding(for: snippet, keyPath: \.value)
                        )
                    }
                }
                .onDelete { store.remove(at: $0) }
                .onMove { store.move(from: $0, to: $1) }
            }

            Divider()

            HStack(spacing: 8) {
                TextField(settings.t(.settingsNewSnippetLabel), text: $newLabel)
                    .frame(width: 140)
                TextField(settings.t(.settingsNewSnippetValue), text: $newValue)
                Button(settings.t(.settingsAdd), action: add)
                    .disabled(newLabel.isEmpty || newValue.isEmpty)
            }
            .padding(12)

            Caption(settings.t(.settingsSnippetsHint))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private func add() {
        store.add(label: newLabel, value: newValue)
        newLabel = ""
        newValue = ""
    }

    private func binding(
        for snippet: Snippet,
        keyPath: WritableKeyPath<Snippet, String>
    ) -> Binding<String> {
        Binding(
            get: { snippet[keyPath: keyPath] },
            set: { newValue in
                var copy = snippet
                copy[keyPath: keyPath] = newValue
                store.update(copy)
            }
        )
    }
}

// MARK: - Станции

/// Список станций Apple Music.
///
/// Руками, потому что иначе никак: станций нет ни в AppleScript, ни в
/// медиатеке — только ссылкой. Зато принесённая один раз ссылка живёт
/// между запусками и запускается из полки одним кликом.
private struct StationsSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(settings.musicStations) { station in
                    HStack(spacing: 8) {
                        TextField(
                            settings.t(.settingsStationName),
                            text: binding(for: station, keyPath: \.name)
                        )
                        .frame(width: 140)
                        TextField(
                            settings.t(.settingsStationURL),
                            text: binding(for: station, keyPath: \.url)
                        )
                        // Красным — ссылка, которую Music не откроет:
                        // молчаливая кнопка в полке хуже пометки здесь.
                        .foregroundStyle(station.isPlayable ? Color.primary : .red)
                    }
                }
                .onDelete { settings.removeStations(at: $0) }
            }

            Divider()

            HStack(spacing: 8) {
                TextField(settings.t(.settingsNewStationName), text: $newName)
                    .frame(width: 140)
                TextField(settings.t(.settingsNewStationURL), text: $newURL)
                Button(settings.t(.settingsAdd), action: add)
                    .disabled(newName.isEmpty || newURL.isEmpty)
            }
            .padding(12)

            Caption(settings.t(.settingsStationsHint))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    private func add() {
        settings.addStation(name: newName, url: newURL)
        newName = ""
        newURL = ""
    }

    private func binding(
        for station: MusicStation,
        keyPath: WritableKeyPath<MusicStation, String>
    ) -> Binding<String> {
        Binding(
            get: { station[keyPath: keyPath] },
            set: { value in
                var copy = station
                copy[keyPath: keyPath] = value
                settings.updateStation(copy)
            }
        )
    }
}

// MARK: - О программе

private struct AboutSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var music: NowPlayingCoordinator

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Notch").font(.title2.weight(.semibold))
            Text("\(settings.t(.settingsAboutVersion)) \(AppVersion.display)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(AppVersion.build)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.tertiary)
            Caption(settings.t(.settingsAboutHint))

            // Видно, какой провайдер реально отдаёт данные о воспроизведении:
            // «MediaRemote» — виден любой источник, «AppleScript» — только
            // Music и Spotify, «—» — сейчас ничего не играет.
            Text("\(settings.t(.settingsAboutProvider)): \(music.activeProvider)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospaced()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - Горячие клавиши

private struct HotkeySettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(settings.hotkeyActions) { action in
                    HStack {
                        Label(settings.hotkeyTitle(for: action), systemImage: action.symbol)
                        Spacer(minLength: 16)
                        KeyRecorder(
                            combo: Binding(
                                get: { settings.combo(for: action) },
                                set: { settings.setCombo($0, for: action) }
                            ),
                            recordTitle: settings.t(.hotkeyRecord),
                            recordingTitle: settings.t(.hotkeyRecording),
                            emptyTitle: settings.t(.hotkeyNone),
                            clearTitle: settings.t(.hotkeyClear)
                        )
                    }
                }
            } footer: {
                Caption(settings.t(.hotkeysHint))
            }
        }
        .formStyle(.grouped)
    }
}


// MARK: - Приватность

private struct PrivacySettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboard: ClipboardStore

    var body: some View {
        Form {
            Section {
                Toggle(
                    settings.t(.settingsPersistClipboard),
                    isOn: $settings.persistClipboard
                )
                Button(settings.t(.settingsClearClipboard)) {
                    clipboard.clearAll()
                }
            } footer: {
                Caption(settings.t(.settingsPersistClipboardHint))
            }
        }
        .formStyle(.grouped)
    }
}
