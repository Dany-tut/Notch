import Foundation

/// Язык интерфейса. База — английский; русский подключается поверх неё.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Как язык называется в списке — всегда на самом себе.
    var nativeName: String {
        switch self {
        case .system: return "" // подставляется локализованно
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    /// Во что разворачивается `.system` на этой машине.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? .russian : .english
    }
}

enum L10n {
    enum Key: String, Sendable {
        // Модули
        case moduleMusic, moduleClipboard, moduleTrash, moduleSnippets
        case moduleShelf, moduleTranslate, moduleCalendar, moduleBattery
        case moduleTimers, moduleNotes, moduleSystem, moduleWeather, moduleApps
        case moduleMirror, moduleAskAI, moduleReminders, moduleShortcuts
        case shortcutsEmptyTitle, shortcutsEmptyHint, shortcutsOpenApp
        case shortcutsFailedTitle, shortcutsFailedHint, shortcutsNoResults
        case shortcutsRun, shortcutsRunning, shortcutsRunFailed
        case shortcutsPin, shortcutsUnpin, shortcutsRefresh
        case moduleConverter
        case converterLength, converterMass, converterTemperature, converterVolume
        case converterSpeed, converterArea, converterData, converterTime
        case converterSwap, converterCopyHint, converterEnterNumber, converterEnterNumberHint
        case moduleEmoji, emojiSearch, emojiRecent, emojiNoResults
        case emojiSmileys, emojiPeople, emojiNature, emojiFood, emojiActivity
        case emojiTravel, emojiObjects, emojiSymbols, emojiFlags
        case moduleTeleprompter, teleprompterPlay, teleprompterPause, teleprompterReset
        case teleprompterSmaller, teleprompterLarger, teleprompterMirror
        case teleprompterEdit, teleprompterDone, teleprompterPlaceholder
        case teleprompterHintPlaying, teleprompterHintPaused
        case appsPinHint, appsNoResults, appsPin, appsUnpin, appsAddToFolder, appsNewFolder
        case appsRemoveFromFolder, appsReveal, appsDeleteFolder
        case batteryNoDevices

        // Заметка на полях
        case notesPlaceholder, notesCopy, notesClear

        // Погода
        case weatherPickPlaceTitle, weatherUseLocation, weatherSearchCity
        case weatherSearchPlaceholder, weatherSearchHint, weatherSearching, weatherNoResults
        case weatherChangePlace, weatherMyLocation, weatherLocationDenied
        case weatherFailed, weatherRetry, weatherNow
        case weatherFeelsLike, weatherWind
        case weatherClear, weatherMostlyClear, weatherPartlyCloudy, weatherOvercast
        case weatherFog, weatherDrizzle, weatherFreezingRain, weatherRain, weatherHeavyRain
        case weatherSnow, weatherShowers, weatherSnowShowers, weatherThunder

        // Система
        case systemCPU, systemMemory, systemNetwork, systemDisk
        case systemLoad, systemFree

        // Таймер, секундомер, будильник
        case timersTimer, timersStopwatch, timersAlarm
        case timersStart, timersPause, timersReset, timersLap
        case timersPresets, timersMinutesShort, timersNoLaps
        case timersAddAlarm, timersNoAlarmsTitle, timersNoAlarmsHint
        case timersDone, timersAlarmRinging, timersStopRinging
        case timersLeft, timersReady, timersLaps, timersPresetsHint, timersActiveAlarms
        case timersAlarmDragHint, timersAlarmSetAt, timersAlarmNotSet
        case timersSound, timersSoundOff, timersSoundRain, timersSoundCafe
        case timersSoundWhite, timersSoundPink, timersSoundBrown, timersSoundVolume

        // Общее
        case comingSoon, copied

        // Заготовки и буфер
        case snippetsEmptyTitle, snippetsEmptyHint
        case clipboardEmptyTitle, clipboardEmptyHint
        case clipboardListMode, clipboardGridMode, clipboardImage, clipboardText
        case previewHint
        case shelfEmptyTitle, shelfEmptyHint, shelfCount
        case shelfClearAll, shelfPaste, shelfAirDrop
        case shelfAirDropAll, shelfAirDropUnavailable, shelfReveal, shelfRemove
        case shelfListMode, shelfGridMode, shelfFile, shelfFolder
        case translatePlaceholder, translateUnavailable
        case calendarAskTitle, calendarAskButton
        case calendarDeniedTitle, calendarDeniedHint, calendarOpenSettings
        case calendarUnbundledTitle, calendarUnbundledHint
        case calendarEmptyTitle, calendarEmptyHint, calendarNoMore
        case calendarToday, calendarDayEmpty, calendarAllDay
        case mirrorAskTitle, mirrorAskButton
        case mirrorDeniedTitle, mirrorDeniedHint, mirrorOpenSettings
        case mirrorNoCameraTitle, mirrorNoCameraHint
        case mirrorUnbundledTitle, mirrorUnbundledHint
        case askAIOffTitle, askAIOffHint, askAIOpenSettings
        case remindersAskTitle, remindersAskButton
        case remindersDeniedTitle, remindersDeniedHint, remindersOpenSettings
        case remindersUnbundledTitle, remindersUnbundledHint
        case remindersEmptyTitle, remindersEmptyHint, remindersAddPlaceholder
        case remindersComplete, remindersUndo
        case remindersToday, remindersTomorrow, remindersYesterday
        case askAINotEligibleTitle, askAINotEligibleHint
        case askAINotReadyTitle, askAINotReadyHint
        case askAIPlaceholder, askAIEmptyHint, askAIClear, askAISend, askAIStop
        case askAICopy, askAICopied, askAIFailed, askAINoClipboardText
        case askAIRewrite, askAIShorten, askAIFix, askAITranslate
        case settingsRailInlineGear
        case musicIdleTitle, musicIdleHint, settingsAboutProvider
        case musicSourceOnly, musicSourceSilent, musicNeedsAccessibility, musicNeedsAutomation
        case musicShelfShow, musicShelfHide
        case musicFavoriteAdd, musicFavoriteRemove
        case musicDislikeAdd, musicDislikeRemove
        case musicVisualizer, musicVisualizerHint
        case musicShelfPlaylists, musicPlaylistsEmpty, musicPlaylistTracks
        case musicShelfStations, musicStationFromTrack, musicStationFromTrackHint
        case musicAccessRow, musicAccessStale, musicAccessReveal, musicAccessReset
        case musicSourceAuto, musicSourceNotRunning, musicSourceOpen

        // Горячие клавиши, автозапуск, поиск
        case settingsTabHotkeys, hotkeyTogglePanel, hotkeyOpenModule
        case hotkeyRecord, hotkeyRecording, hotkeyClear, hotkeyNone, hotkeysHint
        case settingsLaunchUnavailable
        case searchPlaceholder, searchNothingFound

        // Доступ системы
        case accessGroup, accessAccessibility, accessCalendar
        case accessGranted, accessMissing, accessUnavailable
        case accessHint, accessRevealApp, accessGesturesHint, accessHotkeysHint

        // Корзина
        case trashEmptyTitle, trashEmptyHint, trashCount
        case trashReveal, trashEmpty, trashConfirmEmpty, trashCancel

        // Приватность
        case settingsTabPrivacy, settingsPersistClipboard
        case settingsPersistClipboardHint, settingsClearClipboard
        case settingsOpenWindow, settingsPanelTitle
        case panelHoldOpen, panelRelease

        // Настройки: отклик, модули, заготовки
        case settingsTabSnippets, settingsTabFeedback, settingsTabStations
        case settingsSound, settingsHaptics, settingsVolume, settingsFeedbackHint
        case settingsSoundChoice, settingsSoundNone, settingsSoundPreview
        case settingsModulesReorderHint

        // Рейл: размер и положение
        case settingsRailSize, settingsRailPlacement, settingsRailHint
        case settingsRailLabels, settingsRailGap, settingsRailIcons
        case settingsTabView, settingsTabNotch, settingsTabApp
        case settingsGroupRail, settingsGroupNotchTuning
        case settingsGroupIsland, settingsGroupBadges, settingsGroupTiming
        case settingsGroupModuleList, settingsGroupMusic, settingsGroupOrder
        case settingsGroupDisplay, settingsGroupExpand, settingsGroupHide, settingsGroupGestures
        case settingsGroupBasics, settingsGroupFeedback, settingsGroupClipboard
        case railLabelsNone, railLabelsActive
        case railIconsOutline, railIconsSubtones, railIconsColor
        case railGapTight, railGapNormal, railGapLoose
        case railSizeSmall, railSizeMedium, railSizeLarge
        case railPlacementLeading, railPlacementTrailing, railPlacementTop, railPlacementBottom
        case railPlacementBottomCentered
        case settingsSnippetsHint, settingsSnippetLabel, settingsSnippetValue
        case settingsStationsHint, settingsStationName, settingsStationURL
        case settingsNewStationName, settingsNewStationURL
        case settingsAdd, settingsRemove, settingsNewSnippetLabel, settingsNewSnippetValue

        // Остров у выреза
        case settingsTabIsland, settingsIslandHint
        case islandSideLeft, islandSideRight, islandSide

        // Плашка у выреза
        case settingsTabActivities, settingsActivitiesHint
        case activityMusic, activityPower, activityLockScreen
        case activityAudioDevice, activityFocus
        case activityCharging, activityOnBattery, activityLowBattery
        case activityLowPowerOn, activityLowPowerOff
        case activityWelcomeBack, activityConnected
        case activityFocusOn, activityFocusOff
        case activityDuration, activityLowBatteryThreshold
        case activityCalendar, activityTimer
        case activityLevels, levelsVolume, levelsMuted, levelsBrightness, settingsLevelsHint
        case calendarJoin, calendarStartsIn, settingsCalendarLead
        case settingsPinMusicActivity, settingsPinMusicActivityHint

        // Поведение панели
        case settingsTabBehaviour, behaviourHint
        case behaviourDisplay, behaviourDisplayBuiltIn, behaviourDisplayMain, behaviourDisplayActive
        case behaviourExpandOnHover, behaviourHoverDuration
        case behaviourDropToShelf, behaviourDropToShelfHint
        case behaviourHideFullscreen, behaviourHideGaming
        case behaviourHideCapture, behaviourHideMenuBar
        case behaviourSimulatedNotch, behaviourNotchWidth, behaviourNotchHeight
        case behaviourResetTuning, behaviourTuningHint
        case behaviourSwipeToSkip, behaviourSwipeToToggle, behaviourGesturesHint
        case behaviourGesturesBlocked

        // Меню в строке состояния
        case menuSettings, menuQuit

        // Настройки
        case settingsTitle
        case settingsTabGeneral, settingsTabModules, settingsTabAbout
        case settingsLanguage, settingsLanguageHint, settingsLanguageSystem
        case settingsLaunchAtLogin, settingsLaunchAtLoginHint
        case settingsStateOn, settingsStateOff
        case settingsModulesHint
        case settingsAboutVersion, settingsAboutHint
        case settingsTabLicense, proLockedTitle, proLockedHint, proBuy, proHaveKey, licenseStatus, licenseStatusLicensed, licenseStatusExpired, licenseKeyPlaceholder, licenseActivate, licenseInvalid, licenseDeactivate, licenseCoreFree, licenseProIncludes
        case settingsUpdateAvailable
    }

    /// Английский — источник истины. Ключ без перевода падает сюда.
    private static let english: [Key: String] = [
        .moduleMusic: "Music",
        .moduleClipboard: "Clipboard",
        .moduleTrash: "Trash",
        .moduleSnippets: "Snippets",
        .moduleShelf: "Shelf",
        .moduleTranslate: "Translate",
        .moduleCalendar: "Calendar",
        .moduleBattery: "Battery",
        .batteryNoDevices: "No connected devices report their battery",

        .moduleTimers: "Timers",
        .moduleNotes: "Notes",
        .moduleApps: "Apps",
        .appsPinHint: "Drag an app here to keep it in the first row",
        .appsNoResults: "Nothing found",
        .appsPin: "Pin to top",
        .appsUnpin: "Unpin",
        .appsAddToFolder: "Add to folder",
        .appsNewFolder: "New folder",
        .appsRemoveFromFolder: "Remove from folder",
        .appsReveal: "Show in Finder",
        .appsDeleteFolder: "Delete folder",
        .moduleSystem: "System",
        .moduleMirror: "Mirror",
        .moduleAskAI: "Ask AI",
        .moduleReminders: "Reminders",
        .moduleShortcuts: "Shortcuts",
        .shortcutsEmptyTitle: "No shortcuts yet",
        .shortcutsEmptyHint: "Make one in the Shortcuts app — it shows up here",
        .shortcutsOpenApp: "Open Shortcuts",
        .shortcutsFailedTitle: "Couldn't read your shortcuts",
        .shortcutsFailedHint: "The shortcuts command didn't answer — try refreshing",
        .shortcutsNoResults: "Nothing found",
        .shortcutsRun: "Run",
        .shortcutsRunning: "Running…",
        .shortcutsRunFailed: "The shortcut failed",
        .shortcutsPin: "Pin to top",
        .shortcutsUnpin: "Unpin",
        .shortcutsRefresh: "Refresh",
        .moduleConverter: "Converter",
        .converterLength: "Length",
        .converterMass: "Mass",
        .converterTemperature: "Temperature",
        .converterVolume: "Volume",
        .converterSpeed: "Speed",
        .converterArea: "Area",
        .converterData: "Data",
        .converterTime: "Time",
        .converterSwap: "Swap units",
        .converterCopyHint: "Click to copy",
        .converterEnterNumber: "Type a number",
        .converterEnterNumberHint: "Both 1.5 and 1,5 work",
        .moduleEmoji: "Emoji",
        .emojiSearch: "Search emoji",
        .emojiRecent: "Recent",
        .emojiNoResults: "No emoji found",
        .emojiSmileys: "Smileys",
        .emojiPeople: "People",
        .emojiNature: "Animals & Nature",
        .emojiFood: "Food & Drink",
        .emojiActivity: "Activity",
        .emojiTravel: "Travel & Places",
        .emojiObjects: "Objects",
        .emojiSymbols: "Symbols",
        .emojiFlags: "Flags",
        .moduleTeleprompter: "Teleprompter",
        .teleprompterPlay: "Play (Space)",
        .teleprompterPause: "Pause (Space)",
        .teleprompterReset: "Back to start (R)",
        .teleprompterSmaller: "Smaller text",
        .teleprompterLarger: "Larger text",
        .teleprompterMirror: "Mirror for teleprompter glass",
        .teleprompterEdit: "Edit text",
        .teleprompterDone: "Done — to the prompter",
        .teleprompterPlaceholder: "Paste or type your script — it will scroll right under the camera",
        .teleprompterHintPlaying: "wheel or ± — speed",
        .teleprompterHintPaused: "Space — play · wheel — scroll",
        .moduleWeather: "Weather",
        .weatherPickPlaceTitle: "Where should I show the weather for?",
        .weatherUseLocation: "My location",
        .weatherSearchCity: "Find a city",
        .weatherSearchPlaceholder: "City",
        .weatherSearchHint: "Start typing a city name",
        .weatherSearching: "Searching…",
        .weatherNoResults: "Nothing found",
        .weatherChangePlace: "Change place",
        .weatherMyLocation: "My location",
        .weatherLocationDenied: "Location access is off. Allow it in System Settings → Privacy → Location Services, or pick a city.",
        .weatherFailed: "Couldn't load the forecast",
        .weatherRetry: "Try again",
        .weatherNow: "Now",
        .weatherFeelsLike: "Feels %@",
        .weatherWind: "%d m/s",
        .weatherClear: "Clear",
        .weatherMostlyClear: "Mostly clear",
        .weatherPartlyCloudy: "Partly cloudy",
        .weatherOvercast: "Overcast",
        .weatherFog: "Fog",
        .weatherDrizzle: "Drizzle",
        .weatherFreezingRain: "Freezing rain",
        .weatherRain: "Rain",
        .weatherHeavyRain: "Heavy rain",
        .weatherSnow: "Snow",
        .weatherShowers: "Showers",
        .weatherSnowShowers: "Snow showers",
        .weatherThunder: "Thunderstorm",

        .notesPlaceholder: "Jot something down — it stays here",
        .notesCopy: "Copy everything",
        .notesClear: "Clear the note",

        .systemCPU: "CPU",
        .systemMemory: "Memory",
        .systemNetwork: "Network",
        .systemDisk: "Disk",
        .systemLoad: "load",
        .systemFree: "free",

        .timersTimer: "Timer",
        .timersStopwatch: "Stopwatch",
        .timersAlarm: "Alarm",
        .timersStart: "Start",
        .timersPause: "Pause",
        .timersReset: "Reset",
        .timersLap: "Lap",
        .timersPresets: "Presets",
        .timersMinutesShort: "min",
        .timersNoLaps: "No laps yet",
        .timersAddAlarm: "Add alarm",
        .timersNoAlarmsTitle: "No alarms",
        .timersNoAlarmsHint: "Nothing armed yet",
        .timersDone: "Time's up",
        .timersAlarmRinging: "Alarm",
        .timersStopRinging: "Stop",
        .timersLeft: "left",
        .timersReady: "ready",
        .timersLaps: "Laps",
        .timersPresetsHint: "Tap to pick, tap again to start",
        .timersActiveAlarms: "Armed",
        .timersAlarmDragHint: "click, then drag or scroll",
        .timersAlarmSetAt: "Set for %@",
        .timersAlarmNotSet: "not armed",
        .timersSound: "Focus sound",
        .timersSoundOff: "No sound",
        .timersSoundRain: "Rain",
        .timersSoundCafe: "Café",
        .timersSoundWhite: "White noise",
        .timersSoundPink: "Pink noise",
        .timersSoundBrown: "Brown noise",
        .timersSoundVolume: "Volume",
        .activityTimer: "Timer and alarm",
        .activityLevels: "Volume and brightness",
        .levelsVolume: "Volume",
        .levelsMuted: "Muted",
        .levelsBrightness: "Brightness",
        .settingsLevelsHint: "The volume and brightness keys show their level at the notch instead of the system window; tap the badge to pick the audio output. Intercepting keys needs Accessibility — until it is granted, the keys work as usual.",


        .comingSoon: "Coming soon",
        .copied: "Copied",

        .snippetsEmptyTitle: "No snippets yet",
        .snippetsEmptyHint: "Add them in Settings › Snippets",
        .clipboardEmptyTitle: "Clipboard history is empty",
        .clipboardEmptyHint: "Copy something and it shows up here",
        .clipboardListMode: "List",
        .clipboardGridMode: "Cards",
        .previewHint: "Hold to preview, drag to take it out",
        .clipboardImage: "Image",
        .clipboardText: "Text",

        .shelfEmptyTitle: "Shelf is empty",
        .shelfEmptyHint: "Drag files here or press ⌘V — then drag them out wherever you need",
        .shelfCount: "Items",
        .shelfClearAll: "Clear shelf",
        .shelfPaste: "Paste",
        .shelfAirDrop: "AirDrop",
        .shelfAirDropAll: "AirDrop all",
        .shelfAirDropUnavailable: "AirDrop is off",
        .shelfReveal: "Show in Finder",
        .shelfRemove: "Remove from shelf",
        .shelfListMode: "List",
        .shelfGridMode: "Cards",
        .shelfFile: "File",
        .shelfFolder: "Folder",

        .translatePlaceholder: "Type or paste text",
        .translateUnavailable: "Language pair unavailable",

        .calendarAskTitle: "Calendar access needed",
        .calendarAskButton: "Allow",
        .calendarDeniedTitle: "Access denied",
        .calendarDeniedHint: "Turn it on in System Settings › Privacy › Calendars",
        .calendarOpenSettings: "Open Settings",
        .mirrorAskTitle: "Camera access needed",
        .mirrorAskButton: "Allow",
        .mirrorDeniedTitle: "Camera access denied",
        .mirrorDeniedHint: "Turn it on in System Settings › Privacy › Camera",
        .mirrorOpenSettings: "Open Settings",
        .mirrorNoCameraTitle: "No camera",
        .mirrorNoCameraHint: "Connect a camera to see yourself here",
        .mirrorUnbundledTitle: "Run Notch as an app",
        .mirrorUnbundledHint: "macOS only asks for camera access from Notch.app — build it with Scripts/build-app.sh",
        .askAIOffTitle: "Apple Intelligence is off",
        .askAIOffHint: "Turn it on in System Settings › Apple Intelligence & Siri",
        .askAIOpenSettings: "Open Settings",
        .remindersAskTitle: "Reminders access needed",
        .remindersAskButton: "Allow",
        .remindersDeniedTitle: "Reminders access denied",
        .remindersDeniedHint: "Turn it on in System Settings › Privacy › Reminders",
        .remindersOpenSettings: "Open Settings",
        .remindersUnbundledTitle: "Run Notch as an app",
        .remindersUnbundledHint: "macOS only asks for Reminders access from Notch.app — build it with Scripts/build-app.sh",
        .remindersEmptyTitle: "All done",
        .remindersEmptyHint: "Add a reminder below",
        .remindersAddPlaceholder: "New reminder",
        .remindersComplete: "Complete",
        .remindersUndo: "Undo",
        .remindersToday: "Today",
        .remindersTomorrow: "Tomorrow",
        .remindersYesterday: "Yesterday",
        .askAINotEligibleTitle: "Not available on this Mac",
        .askAINotEligibleHint: "The on-device model needs a Mac with Apple silicon",
        .askAINotReadyTitle: "The model is still downloading",
        .askAINotReadyHint: "Apple Intelligence is getting ready — come back in a few minutes",
        .askAIPlaceholder: "Ask anything…",
        .askAIEmptyHint: "The model runs right on this Mac — nothing goes online",
        .askAIClear: "Clear conversation",
        .askAISend: "Send",
        .askAIStop: "Stop",
        .askAICopy: "Copy",
        .askAICopied: "Copied",
        .askAIFailed: "Couldn't answer that. Try rephrasing.",
        .askAINoClipboardText: "No text on the clipboard",
        .askAIRewrite: "Rewrite",
        .askAIShorten: "Shorten",
        .askAIFix: "Fix mistakes",
        .askAITranslate: "Translate to English",
        .calendarUnbundledTitle: "Run Notch as an app",
        .calendarUnbundledHint: "macOS only asks for Calendar access from Notch.app — build it with Scripts/build-app.sh",
        .calendarEmptyTitle: "Nothing coming up",
        .calendarEmptyHint: "No meetings in the next seven days",
        .calendarNoMore: "No other meetings this week",
        .settingsRailInlineGear: "Settings in the row",
        .calendarToday: "Today",
        .calendarDayEmpty: "Nothing on this day",
        .calendarAllDay: "All day",

        .musicIdleTitle: "Nothing playing",
        .musicIdleHint: "Music and Spotify are read directly; other sources need system access",
        .settingsAboutProvider: "Now Playing source",
        .musicSourceOnly: "Playing — track info unavailable for this source",
        .musicSourceSilent: "Open, but silent",
        .musicShelfShow: "Show playlists",
        .musicShelfHide: "Hide playlists",
        .musicDislikeAdd: "Dislike",
        .musicDislikeRemove: "Undo dislike",
        .musicFavoriteAdd: "Add to favorites",
        .musicFavoriteRemove: "Remove from favorites",
        .musicVisualizer: "Wave",
        .musicVisualizerHint: "A slow wave of light under the player, in the artwork's colour. It runs on its own time, not on the audio.",
        .musicShelfPlaylists: "Playlists",
        .musicPlaylistsEmpty: "This source keeps no playlists we can read",
        .musicPlaylistTracks: "tracks",
        .musicShelfStations: "Stations",
        .musicStationFromTrack: "Station from this song",
        .musicStationFromTrackHint: "Apple Music builds it around what is playing",
        .musicNeedsAccessibility: "Allow Accessibility so the buttons reach the player",
        .musicAccessRow: "The row is «Notch» — this exact file:",
        .musicAccessStale: "Already on and still silent? Each rebuild changes the app, and the old entry stops counting: select the row, press −, then add this file again.",
        .musicAccessReveal: "Show the file in Finder",
        .musicAccessReset: "Forget the permission and ask again",
        .musicNeedsAutomation: "Allow Automation so the track name can be read",
        .musicSourceAuto: "Auto",
        .musicSourceNotRunning: "Not running",
        .musicSourceOpen: "Press play to open it",

        .settingsTabHotkeys: "Shortcuts",
        .hotkeyTogglePanel: "Open the panel",
        .hotkeyOpenModule: "Open %@",
        .behaviourDropToShelf: "Catch dragged files",
        .behaviourDropToShelfHint: "Drag a file to the notch and the panel opens on the Shelf, ready to take it",
        .hotkeyRecord: "Set",
        .hotkeyRecording: "Press keys…",
        .hotkeyClear: "Clear",
        .hotkeyNone: "Not set",
        .hotkeysHint: "A shortcut already taken by another app simply will not register.",
        .settingsLaunchUnavailable: "Available only in the packaged app, not the dev build.",
        .searchPlaceholder: "Search",
        .accessGroup: "Access",
        .accessAccessibility: "Accessibility",
        .accessCalendar: "Calendar",
        .accessGranted: "Granted",
        .accessMissing: "Not granted",
        .accessUnavailable: "Run the app bundle",
        .accessHint: "Accessibility is what gestures and hotkeys run on: they read events outside our window, and the system won't hand those over without it. If several Notch entries pile up in the list, only the one this button reveals counts.",
        .accessRevealApp: "Show app in Finder",
        .accessGesturesHint: "Gestures stay dead until Accessibility is granted — see Access in the App tab.",
        .accessHotkeysHint: "Hotkeys stay dead until Accessibility is granted — see Access in the App tab.",
        .searchNothingFound: "Nothing found",

        .trashEmptyTitle: "Trash is empty",
        .trashEmptyHint: "Drag files here to move them to the Trash",
        .trashCount: "Items",
        .trashReveal: "Open in Finder",
        .trashEmpty: "Empty",
        .trashConfirmEmpty: "Delete permanently",
        .trashCancel: "Cancel",

        .settingsTabPrivacy: "Privacy",
        .settingsPersistClipboard: "Keep clipboard history between launches",
        .settingsPersistClipboardHint: "Stored encrypted; the key lives in the Keychain. Turn this off and history exists only in memory.",
        .settingsClearClipboard: "Clear history now",
        .settingsOpenWindow: "Open full settings…",
        .settingsPanelTitle: "Settings",
        .panelHoldOpen: "Keep open when the pointer leaves",
        .panelRelease: "Unpin: close when the pointer leaves",

        .settingsTabSnippets: "Snippets",
        .settingsTabStations: "Stations",
        .settingsTabFeedback: "Feedback",
        .settingsSound: "Sound on appear",
        .settingsHaptics: "Haptic tap on appear",
        .settingsVolume: "Volume",
        .settingsFeedbackHint: "The haptic tap needs a Force Touch trackpad.",
        .settingsSoundChoice: "Sound",
        .settingsSoundNone: "None",
        .settingsSoundPreview: "Play",
        .settingsModulesReorderHint: "Drag to reorder. The order matches the rail.",
        .settingsRailSize: "Rail size",
        .settingsRailPlacement: "Rail position",
        .settingsRailHint: "Across the top or the bottom the rail takes the title row and steps clear of the notch, so the content gains the whole width.",
        .railSizeSmall: "Small",
        .railSizeMedium: "Medium",
        .railSizeLarge: "Large",
        .railPlacementLeading: "Left",
        .railPlacementTrailing: "Right",
        .railPlacementTop: "Top",
        .railPlacementBottom: "Bottom",
        .railPlacementBottomCentered: "Bottom, centered",
        .settingsTabView: "Look",
        .settingsTabNotch: "Notch",
        .settingsTabApp: "App",
        .settingsGroupRail: "Rail",
        .settingsGroupNotchTuning: "Notch fit",
        .settingsGroupIsland: "Dots",
        .settingsGroupBadges: "Badges",
        .settingsGroupTiming: "Timing",
        .settingsGroupModuleList: "Modules",
        .settingsGroupMusic: "Music",
        .settingsGroupOrder: "Order",
        .settingsGroupDisplay: "Where",
        .settingsGroupExpand: "Expanding",
        .settingsGroupHide: "Hiding",
        .settingsGroupGestures: "Gestures",
        .settingsGroupBasics: "Basics",
        .settingsGroupFeedback: "Feedback",
        .settingsGroupClipboard: "Clipboard",
        .settingsRailLabels: "Button labels",
        .settingsRailIcons: "Icons",
        .settingsRailGap: "Button spacing",
        .railLabelsNone: "None",
        .railLabelsActive: "Active only",
        .railIconsOutline: "Outline",
        .railIconsSubtones: "Subtones",
        .railIconsColor: "Color",
        .railGapTight: "Tight",
        .railGapNormal: "Normal",
        .railGapLoose: "Loose",
        .settingsSnippetsHint: "Click a snippet in the panel to copy it.",
        .settingsStationsHint: "Music keeps no list of stations we can read. Copy a link in Music (Share \u{2192} Copy Link) and paste it here \u{2014} the shelf will start it in one click.",
        .settingsStationName: "Name",
        .settingsStationURL: "Link",
        .settingsNewStationName: "Station name",
        .settingsNewStationURL: "https://music.apple.com/\u{2026}",
        .settingsSnippetLabel: "Label",
        .settingsSnippetValue: "Value",
        .settingsAdd: "Add",
        .settingsRemove: "Remove",
        .settingsNewSnippetLabel: "Email",
        .settingsNewSnippetValue: "you@example.com",

        .settingsTabIsland: "Island",
        .settingsIslandHint: "Tap a tile to switch its circle on or off; tap the little notch on it to move the circle to the other side. A circle only shows while the notch is collapsed and there is something to say: the shelf when it holds files, music while a track is playing, the timer while it or the stopwatch is running. Hovering it opens the module.",
        .islandSide: "Side",
        .islandSideLeft: "Left",
        .islandSideRight: "Right",

        .settingsTabActivities: "Activities",
        .settingsActivitiesHint: "The collapsed notch briefly turns into a badge when something happens. Turn off what you do not need.",
        .activityMusic: "Track change",
        .activityPower: "Power",
        .activityLockScreen: "Unlock",
        .activityAudioDevice: "Audio device",
        .activityFocus: "Focus",
        .activityCharging: "Charging",
        .activityOnBattery: "On battery",
        .activityLowBattery: "Low battery",
        .activityLowPowerOn: "Low Power Mode on",
        .activityLowPowerOff: "Low Power Mode off",
        .activityWelcomeBack: "Welcome back",
        .activityConnected: "Connected",
        .activityFocusOn: "Focus on",
        .activityFocusOff: "Focus off",
        .activityDuration: "Badge duration",
        .activityLowBatteryThreshold: "Low battery at",
        .activityCalendar: "Meeting soon",
        .calendarJoin: "Join",
        .calendarStartsIn: "in %@ min",
        .settingsCalendarLead: "Warn before meeting",
        .settingsPinMusicActivity: "Keep track badge",
        .settingsPinMusicActivityHint: "The pinned badge takes up the whole notch, so the circles step out to its edges — the running stopwatch stays in sight. The music circle is not shown next to it: the badge is already about that track, and whoever has no room left beside it hides.",

        .settingsTabBehaviour: "Behaviour",
        .behaviourHint: "Where the panel lives and when it gets out of the way.",
        .behaviourDisplay: "Show on",
        .behaviourDisplayBuiltIn: "Built-in display",
        .behaviourDisplayMain: "Main display",
        .behaviourDisplayActive: "Active display",
        .behaviourExpandOnHover: "Expand on hover",
        .behaviourHoverDuration: "Hover delay",
        .behaviourHideFullscreen: "Hide in fullscreen",
        .behaviourHideGaming: "Hide while gaming",
        .behaviourHideCapture: "Hide from screen capture",
        .behaviourHideMenuBar: "Hide menu bar icon",
        .behaviourSimulatedNotch: "Force simulated notch",
        .behaviourNotchWidth: "Notch width",
        .behaviourNotchHeight: "Notch height",
        .behaviourResetTuning: "Reset tuning",
        .behaviourSwipeToSkip: "Swipe to skip media",
        .behaviourSwipeToToggle: "Swipe to open and close",
        .behaviourGesturesHint: "Swipe over the notch itself: sideways for tracks, down to open, up to dismiss.",
        .behaviourGesturesBlocked: "Gestures need the notch collapsed — turn off «Expand on hover», otherwise the panel opens before your fingers move.",
        .behaviourTuningHint: "Tuning changes the collapsed panel, not the hardware notch itself.",


        .menuSettings: "Settings…",
        .menuQuit: "Quit",

        .settingsTitle: "Notch Settings",
        .settingsTabGeneral: "General",
        .settingsTabModules: "Modules",
        .settingsTabAbout: "About",
        .settingsLanguage: "Language",
        .settingsLanguageHint: "Applies immediately, no restart needed.",
        .settingsLanguageSystem: "System",
        .settingsLaunchAtLogin: "Launch at login",
        .settingsStateOn: "On",
        .settingsStateOff: "Off",
        .settingsLaunchAtLoginHint: "Will be wired up in a later phase.",
        .settingsModulesHint: "Turning modules on and off, and reordering them, comes in the next phase.",
        .settingsAboutVersion: "Version",
        .settingsAboutHint: "A panel at the top edge of the screen.",
        .settingsTabLicense: "License",
        .proLockedTitle: "This module is part of Notch Pro",
        .proLockedHint: "Translate, Ask AI and Teleprompter are unlocked once, for $14.99. No subscription.",
        .proBuy: "Get Notch Pro",
        .proHaveKey: "I have a key",
        .licenseStatus: "Status",
        .licenseStatusLicensed: "Notch Pro — licensed to %@",
        .licenseStatusExpired: "No license key — Pro modules are locked",
        .licenseKeyPlaceholder: "Paste your license key",
        .licenseActivate: "Activate",
        .licenseInvalid: "That key doesn’t check out. Copy it again in full.",
        .licenseDeactivate: "Remove key from this Mac",
        .licenseCoreFree: "Everything else stays free and open source.",
        .licenseProIncludes: "Pro unlocks: Translate, Ask AI, Teleprompter.",
        .settingsUpdateAvailable: "Update available"
    ]

    private static let russian: [Key: String] = [
        .moduleMusic: "Музыка",
        .moduleClipboard: "Буфер",
        .moduleTrash: "Корзина",
        .moduleSnippets: "Заготовки",
        .moduleShelf: "Полка",
        .moduleTranslate: "Перевод",
        .moduleCalendar: "Календарь",
        .moduleBattery: "Батарея",

        .moduleTimers: "Таймер",
        .moduleNotes: "Заметка",
        .moduleApps: "Программы",
        .appsPinHint: "Перетащи сюда программу, чтобы она стояла первым рядом",
        .appsNoResults: "Ничего не нашлось",
        .appsPin: "Закрепить сверху",
        .appsUnpin: "Открепить",
        .appsAddToFolder: "В папку",
        .appsNewFolder: "Новая папка",
        .appsRemoveFromFolder: "Убрать из папки",
        .appsReveal: "Показать в Finder",
        .appsDeleteFolder: "Удалить папку",
        .moduleSystem: "Система",
        .moduleMirror: "Зеркало",
        .moduleAskAI: "Спросить ИИ",
        .moduleReminders: "Напоминания",
        .moduleShortcuts: "Быстрые команды",
        .shortcutsEmptyTitle: "Быстрых команд пока нет",
        .shortcutsEmptyHint: "Создай команду в приложении Быстрые команды — она появится здесь",
        .shortcutsOpenApp: "Открыть Быстрые команды",
        .shortcutsFailedTitle: "Не удалось прочитать команды",
        .shortcutsFailedHint: "Утилита shortcuts не ответила — попробуй обновить",
        .shortcutsNoResults: "Ничего не нашлось",
        .shortcutsRun: "Запустить",
        .shortcutsRunning: "Выполняется…",
        .shortcutsRunFailed: "Команда завершилась с ошибкой",
        .shortcutsPin: "Закрепить сверху",
        .shortcutsUnpin: "Открепить",
        .shortcutsRefresh: "Обновить",
        .moduleConverter: "Конвертер",
        .converterLength: "Длина",
        .converterMass: "Масса",
        .converterTemperature: "Температура",
        .converterVolume: "Объём",
        .converterSpeed: "Скорость",
        .converterArea: "Площадь",
        .converterData: "Данные",
        .converterTime: "Время",
        .converterSwap: "Поменять местами",
        .converterCopyHint: "Щелчок — скопировать",
        .converterEnterNumber: "Введите число",
        .converterEnterNumberHint: "Подойдёт и 1,5, и 1.5",
        .moduleEmoji: "Эмодзи",
        .emojiSearch: "Найти эмодзи",
        .emojiRecent: "Недавние",
        .emojiNoResults: "Ничего не нашлось",
        .emojiSmileys: "Смайлики",
        .emojiPeople: "Люди",
        .emojiNature: "Животные и природа",
        .emojiFood: "Еда и напитки",
        .emojiActivity: "Занятия",
        .emojiTravel: "Путешествия",
        .emojiObjects: "Предметы",
        .emojiSymbols: "Символы",
        .emojiFlags: "Флаги",
        .moduleTeleprompter: "Телепромптер",
        .teleprompterPlay: "Пуск (пробел)",
        .teleprompterPause: "Пауза (пробел)",
        .teleprompterReset: "В начало (R)",
        .teleprompterSmaller: "Мельче",
        .teleprompterLarger: "Крупнее",
        .teleprompterMirror: "Отразить для стекла суфлёра",
        .teleprompterEdit: "Править текст",
        .teleprompterDone: "Готово — к суфлёру",
        .teleprompterPlaceholder: "Вставьте или наберите текст — он поедет прямо под камерой",
        .teleprompterHintPlaying: "колесо или ± — скорость",
        .teleprompterHintPaused: "пробел — пуск · колесо — листать",
        .moduleWeather: "Погода",
        .weatherPickPlaceTitle: "Для какого места показывать погоду?",
        .weatherUseLocation: "Где я сейчас",
        .weatherSearchCity: "Найти город",
        .weatherSearchPlaceholder: "Город",
        .weatherSearchHint: "Начните вводить название города",
        .weatherSearching: "Ищу…",
        .weatherNoResults: "Ничего не нашлось",
        .weatherChangePlace: "Сменить место",
        .weatherMyLocation: "Моё место",
        .weatherLocationDenied: "Доступ к геолокации выключен. Включите его в Настройках → Конфиденциальность → Службы геолокации или выберите город.",
        .weatherFailed: "Не удалось загрузить прогноз",
        .weatherRetry: "Повторить",
        .weatherNow: "Сейчас",
        .weatherFeelsLike: "Ощущается %@",
        .weatherWind: "%d м/с",
        .weatherClear: "Ясно",
        .weatherMostlyClear: "Преимущественно ясно",
        .weatherPartlyCloudy: "Переменная облачность",
        .weatherOvercast: "Пасмурно",
        .weatherFog: "Туман",
        .weatherDrizzle: "Морось",
        .weatherFreezingRain: "Ледяной дождь",
        .weatherRain: "Дождь",
        .weatherHeavyRain: "Сильный дождь",
        .weatherSnow: "Снег",
        .weatherShowers: "Ливень",
        .weatherSnowShowers: "Снегопад",
        .weatherThunder: "Гроза",

        .notesPlaceholder: "Запишите — оно здесь и останется",
        .notesCopy: "Скопировать целиком",
        .notesClear: "Очистить заметку",

        .systemCPU: "Процессор",
        .systemMemory: "Память",
        .systemNetwork: "Сеть",
        .systemDisk: "Диск",
        .systemLoad: "нагрузка",
        .systemFree: "свободно",

        .timersTimer: "Таймер",
        .timersStopwatch: "Секундомер",
        .timersAlarm: "Будильник",
        .timersStart: "Пуск",
        .timersPause: "Пауза",
        .timersReset: "Сброс",
        .timersLap: "Круг",
        .timersPresets: "Готовые",
        .timersMinutesShort: "мин",
        .timersNoLaps: "Кругов пока нет",
        .timersAddAlarm: "Завести",
        .timersNoAlarmsTitle: "Будильников нет",
        .timersNoAlarmsHint: "Пока ничего не заведено",
        .timersDone: "Время вышло",
        .timersAlarmRinging: "Будильник",
        .timersStopRinging: "Стоп",
        .timersLeft: "осталось",
        .timersReady: "готов",
        .timersLaps: "Круги",
        .timersPresetsHint: "Клик выбирает, повторный — запускает",
        .timersActiveAlarms: "Заведено",
        .timersAlarmDragHint: "клик, потом тяни или крути",
        .timersAlarmSetAt: "Завести на %@",
        .timersAlarmNotSet: "не заведён",
        .timersSound: "Фоновый звук",
        .timersSoundOff: "Без звука",
        .timersSoundRain: "Дождь",
        .timersSoundCafe: "Кафе",
        .timersSoundWhite: "Белый шум",
        .timersSoundPink: "Розовый шум",
        .timersSoundBrown: "Бурый шум",
        .timersSoundVolume: "Громкость",
        .activityTimer: "Таймер и будильник",
        .activityLevels: "Громкость и яркость",
        .levelsVolume: "Громкость",
        .levelsMuted: "Без звука",
        .levelsBrightness: "Яркость",
        .settingsLevelsHint: "Клавиши громкости и яркости показывают уровень у выреза вместо системного окна, а нажатие на плашку открывает выбор выхода звука. Чтобы перехватывать клавиши, нужен «Универсальный доступ» — пока его нет, клавиши работают как обычно.",
        .batteryNoDevices: "Подключённые устройства не сообщают о заряде",

        .comingSoon: "Скоро",
        .copied: "Скопировано",

        .snippetsEmptyTitle: "Заготовок пока нет",
        .snippetsEmptyHint: "Добавь их в Настройках › Заготовки",
        .clipboardEmptyTitle: "История буфера пуста",
        .clipboardEmptyHint: "Скопируй что-нибудь — появится здесь",
        .clipboardListMode: "Списком",
        .clipboardGridMode: "Карточками",
        .previewHint: "Зажми — покажу крупно, потяни — заберёшь",
        .clipboardImage: "Картинка",
        .clipboardText: "Текст",

        .shelfEmptyTitle: "Полка пуста",
        .shelfEmptyHint: "Перетащи сюда файлы или нажми ⌘V — потом вытащи куда нужно",
        .shelfCount: "Файлов",
        .shelfClearAll: "Очистить полку",
        .shelfPaste: "Вставить",
        .shelfAirDrop: "AirDrop",
        .shelfAirDropAll: "Всё в AirDrop",
        .shelfAirDropUnavailable: "AirDrop выключен",
        .shelfReveal: "Показать в Finder",
        .shelfRemove: "Убрать с полки",
        .shelfListMode: "Списком",
        .shelfGridMode: "Карточками",
        .shelfFile: "Файл",
        .shelfFolder: "Папка",

        .translatePlaceholder: "Введи или вставь текст",
        .translateUnavailable: "Языковая пара недоступна",

        .calendarAskTitle: "Нужен доступ к Календарю",
        .calendarAskButton: "Разрешить",
        .calendarDeniedTitle: "Доступ запрещён",
        .calendarDeniedHint: "Включи в Системных настройках › Конфиденциальность › Календари",
        .calendarOpenSettings: "Открыть настройки",
        .mirrorAskTitle: "Нужен доступ к камере",
        .mirrorAskButton: "Разрешить",
        .mirrorDeniedTitle: "Доступ к камере запрещён",
        .mirrorDeniedHint: "Включи в Системных настройках › Конфиденциальность › Камера",
        .mirrorOpenSettings: "Открыть настройки",
        .mirrorNoCameraTitle: "Камеры нет",
        .mirrorNoCameraHint: "Подключи камеру, чтобы увидеть себя здесь",
        .mirrorUnbundledTitle: "Запусти Notch приложением",
        .mirrorUnbundledHint: "Доступ к камере macOS спрашивает только у Notch.app — собери его через Scripts/build-app.sh",
        .askAIOffTitle: "Apple Intelligence выключен",
        .askAIOffHint: "Включи в Системных настройках › Apple Intelligence и Siri",
        .askAIOpenSettings: "Открыть настройки",
        .remindersAskTitle: "Нужен доступ к Напоминаниям",
        .remindersAskButton: "Разрешить",
        .remindersDeniedTitle: "Доступ к Напоминаниям запрещён",
        .remindersDeniedHint: "Включи в Системных настройках › Конфиденциальность › Напоминания",
        .remindersOpenSettings: "Открыть настройки",
        .remindersUnbundledTitle: "Запусти Notch приложением",
        .remindersUnbundledHint: "Доступ к Напоминаниям macOS спрашивает только у Notch.app — собери его через Scripts/build-app.sh",
        .remindersEmptyTitle: "Всё сделано",
        .remindersEmptyHint: "Добавь напоминание ниже",
        .remindersAddPlaceholder: "Новое напоминание",
        .remindersComplete: "Выполнено",
        .remindersUndo: "Вернуть",
        .remindersToday: "Сегодня",
        .remindersTomorrow: "Завтра",
        .remindersYesterday: "Вчера",
        .askAINotEligibleTitle: "На этом Mac недоступно",
        .askAINotEligibleHint: "Модели на устройстве нужен Mac на Apple silicon",
        .askAINotReadyTitle: "Модель ещё загружается",
        .askAINotReadyHint: "Apple Intelligence готовится — загляни через пару минут",
        .askAIPlaceholder: "Спроси что угодно…",
        .askAIEmptyHint: "Модель работает прямо на этом Mac — в сеть ничего не уходит",
        .askAIClear: "Очистить разговор",
        .askAISend: "Отправить",
        .askAIStop: "Остановить",
        .askAICopy: "Скопировать",
        .askAICopied: "Скопировано",
        .askAIFailed: "Не получилось ответить. Попробуй сформулировать иначе.",
        .askAINoClipboardText: "В буфере нет текста",
        .askAIRewrite: "Переписать",
        .askAIShorten: "Сократить",
        .askAIFix: "Исправить ошибки",
        .askAITranslate: "Перевести на английский",
        .calendarUnbundledTitle: "Запусти Notch приложением",
        .calendarUnbundledHint: "Доступ к Календарю macOS спрашивает только у Notch.app — собери его через Scripts/build-app.sh",
        .calendarEmptyTitle: "Ближайших встреч нет",
        .calendarEmptyHint: "На ближайшие семь дней ничего не запланировано",
        .calendarNoMore: "Других встреч на неделе нет",
        .settingsRailInlineGear: "Шестерёнка в ряду",
        .calendarToday: "Сегодня",
        .calendarDayEmpty: "В этот день ничего нет",
        .calendarAllDay: "Весь день",

        .musicIdleTitle: "Ничего не играет",
        .musicIdleHint: "Music и Spotify читаются напрямую, остальные источники — через системный доступ",
        .settingsAboutProvider: "Источник данных",
        .musicSourceOnly: "Играет — название трека этот источник не отдаёт",
        .musicSourceSilent: "Открыт, но молчит",
        .musicShelfShow: "Показать плейлисты",
        .musicShelfHide: "Скрыть плейлисты",
        .musicDislikeAdd: "Не нравится",
        .musicDislikeRemove: "Убрать дизлайк",
        .musicFavoriteAdd: "В избранное",
        .musicFavoriteRemove: "Убрать из избранного",
        .musicVisualizer: "Волна",
        .musicVisualizerHint: "Медленная волна света под плеером, в цвет обложки. Живёт по своим часам, звук не слушает.",
        .musicShelfPlaylists: "Плейлисты",
        .musicPlaylistsEmpty: "Плейлистов этот источник не отдаёт",
        .musicPlaylistTracks: "треков",
        .musicShelfStations: "Станции",
        .musicStationFromTrack: "Станция по этой песне",
        .musicStationFromTrackHint: "Apple Music соберёт её вокруг того, что играет",
        .musicNeedsAccessibility: "Разреши Универсальный доступ, иначе кнопки не дойдут до плеера",
        .musicAccessRow: "Строка называется «Notch» — вот этот файл:",
        .musicAccessStale: "Уже включено, а толку нет? Каждая пересборка меняет приложение, и старая запись перестаёт считаться: выдели строку, нажми −, потом добавь этот файл заново.",
        .musicAccessReveal: "Показать файл в Finder",
        .musicAccessReset: "Забыть разрешение и спросить заново",
        .musicNeedsAutomation: "Разреши Автоматизацию — без неё название трека не прочитать",
        .musicSourceAuto: "Авто",
        .musicSourceNotRunning: "Не запущен",
        .musicSourceOpen: "Нажми play — откроется",

        .settingsTabHotkeys: "Клавиши",
        .hotkeyTogglePanel: "Открыть панель",
        .hotkeyOpenModule: "Открыть «%@»",
        .behaviourDropToShelf: "Ловить перетаскивание",
        .behaviourDropToShelfHint: "Поднесите файл к вырезу — панель раскроется на полке и примет его",
        .hotkeyRecord: "Задать",
        .hotkeyRecording: "Нажми сочетание…",
        .hotkeyClear: "Очистить",
        .hotkeyNone: "Не задано",
        .hotkeysHint: "Сочетание, уже занятое другим приложением, просто не зарегистрируется.",
        .settingsLaunchUnavailable: "Доступно только в собранном приложении, не в отладочной сборке.",
        .searchPlaceholder: "Поиск",
        .accessGroup: "Доступ",
        .accessAccessibility: "Универсальный доступ",
        .accessCalendar: "Календарь",
        .accessGranted: "Выдан",
        .accessMissing: "Не выдан",
        .accessUnavailable: "Запусти бандл",
        .accessHint: "На «Универсальном доступе» держатся жесты и горячие клавиши: и те и другие читают события мимо нашего окна, а без разрешения система их не отдаёт. Если в списке скопилось несколько строк «Notch», считается только та, что покажет эта кнопка.",
        .accessRevealApp: "Показать в Finder",
        .accessGesturesHint: "Жесты не сработают, пока не выдан Универсальный доступ — он во вкладке «Приложение», раздел «Доступ».",
        .accessHotkeysHint: "Горячие клавиши не сработают, пока не выдан Универсальный доступ — он во вкладке «Приложение», раздел «Доступ».",
        .searchNothingFound: "Ничего не найдено",

        .trashEmptyTitle: "Корзина пуста",
        .trashEmptyHint: "Перетащи сюда файлы, чтобы отправить их в корзину",
        .trashCount: "Объектов",
        .trashReveal: "Открыть в Finder",
        .trashEmpty: "Очистить",
        .trashConfirmEmpty: "Удалить навсегда",
        .trashCancel: "Отмена",

        .settingsTabPrivacy: "Приватность",
        .settingsPersistClipboard: "Хранить историю буфера между запусками",
        .settingsPersistClipboardHint: "Хранится в зашифрованном виде, ключ лежит в Связке ключей. Выключи — история будет жить только в памяти.",
        .settingsClearClipboard: "Очистить историю сейчас",
        .settingsOpenWindow: "Открыть полные настройки…",
        .settingsPanelTitle: "Настройки",
        .panelHoldOpen: "Закрепить: не закрываться, когда уводишь мышь",
        .panelRelease: "Открепить: закрываться, когда уводишь мышь",

        .settingsTabSnippets: "Заготовки",
        .settingsTabStations: "Станции",
        .settingsTabFeedback: "Отклик",
        .settingsSound: "Звук при появлении",
        .settingsHaptics: "Тактильный отклик при появлении",
        .settingsVolume: "Громкость",
        .settingsFeedbackHint: "Тактильный отклик работает на трекпадах с Force Touch.",
        .settingsSoundChoice: "Звук",
        .settingsSoundNone: "Без звука",
        .settingsSoundPreview: "Послушать",
        .settingsModulesReorderHint: "Перетащи, чтобы изменить порядок — он совпадает с рейлом.",
        .settingsRailSize: "Размер рейла",
        .settingsRailPlacement: "Положение рейла",
        .settingsRailHint: "Поперёк — сверху или снизу — рейл забирает строку заголовка и обходит вырез, зато содержимому достаётся вся ширина.",
        .railSizeSmall: "Мелкий",
        .railSizeMedium: "Обычный",
        .railSizeLarge: "Крупный",
        .railPlacementLeading: "Слева",
        .railPlacementTrailing: "Справа",
        .railPlacementTop: "Сверху",
        .railPlacementBottom: "Снизу",
        .railPlacementBottomCentered: "Снизу по центру",
        .settingsTabView: "Вид",
        .settingsTabNotch: "Вырез",
        .settingsTabApp: "Приложение",
        .settingsGroupRail: "Рейл",
        .settingsGroupNotchTuning: "Подгонка выреза",
        .settingsGroupIsland: "Кружки",
        .settingsGroupBadges: "Плашки",
        .settingsGroupTiming: "Время",
        .settingsGroupModuleList: "Модули",
        .settingsGroupMusic: "Музыка",
        .settingsGroupOrder: "Порядок",
        .settingsGroupDisplay: "Где показывать",
        .settingsGroupExpand: "Раскрытие",
        .settingsGroupHide: "Когда прятать",
        .settingsGroupGestures: "Жесты",
        .settingsGroupBasics: "Основное",
        .settingsGroupFeedback: "Отклик",
        .settingsGroupClipboard: "Буфер обмена",
        .settingsRailLabels: "Подписи кнопок",
        .settingsRailIcons: "Иконки",
        .settingsRailGap: "Зазор между кнопками",
        .railLabelsNone: "Нет",
        .railLabelsActive: "У активной",
        .railIconsOutline: "Контур",
        .railIconsSubtones: "Субтоны",
        .railIconsColor: "Цветные",
        .railGapTight: "Плотно",
        .railGapNormal: "Обычно",
        .railGapLoose: "Просторно",
        .settingsSnippetsHint: "Клик по заготовке в панели копирует её значение.",
        .settingsStationsHint: "Своего списка станций Music не отдаёт. Скопируйте ссылку в Music (\u{00AB}Поделиться \u{2192} Скопировать ссылку\u{00BB}) и вставьте сюда \u{2014} полка запустит станцию одним кликом.",
        .settingsStationName: "Название",
        .settingsStationURL: "Ссылка",
        .settingsNewStationName: "Имя станции",
        .settingsNewStationURL: "https://music.apple.com/\u{2026}",
        .settingsSnippetLabel: "Название",
        .settingsSnippetValue: "Значение",
        .settingsAdd: "Добавить",
        .settingsRemove: "Удалить",
        .settingsNewSnippetLabel: "Почта",
        .settingsNewSnippetValue: "you@example.com",

        .settingsTabIsland: "Остров",
        .settingsIslandHint: "Нажатие на плитку включает и выключает кружок, нажатие на вырез в ней переносит его на другую сторону. Кружок виден, пока вырез схлопнут и есть что показать: полка — когда в ней есть файлы, музыка — когда играет трек, таймер — пока он или секундомер идёт. По наведению открывается модуль.",
        .islandSide: "Сторона",
        .islandSideLeft: "Слева",
        .islandSideRight: "Справа",

        .settingsTabActivities: "События",
        .settingsActivitiesHint: "Схлопнутый вырез ненадолго превращается в плашку, когда что-то происходит. Ненужное можно выключить.",
        .activityMusic: "Смена трека",
        .activityPower: "Питание",
        .activityLockScreen: "Разблокировка",
        .activityAudioDevice: "Аудиоустройство",
        .activityFocus: "Фокусирование",
        .activityCharging: "Заряжается",
        .activityOnBattery: "От аккумулятора",
        .activityLowBattery: "Низкий заряд",
        .activityLowPowerOn: "Экономия энергии включена",
        .activityLowPowerOff: "Экономия энергии выключена",
        .activityWelcomeBack: "С возвращением",
        .activityConnected: "Подключено",
        .activityFocusOn: "Фокусирование включено",
        .activityFocusOff: "Фокусирование выключено",
        .activityDuration: "Время показа",
        .activityLowBatteryThreshold: "Низкий заряд при",
        .activityCalendar: "Скоро встреча",
        .calendarJoin: "Подключиться",
        .calendarStartsIn: "через %@ мин",
        .settingsCalendarLead: "Предупреждать за",
        .settingsPinMusicActivity: "Закреплять плашку трека",
        .settingsPinMusicActivityHint: "Закреплённая плашка занимает вырез целиком, поэтому кружки отходят за её края — идущий секундомер остаётся на виду. Кружка музыки рядом с ней нет: плашка и так про этот трек, а кому места не хватило, тот прячется.",

        .settingsTabBehaviour: "Поведение",
        .behaviourHint: "Где живёт панель и когда она уходит с дороги.",
        .behaviourDisplay: "Показывать на",
        .behaviourDisplayBuiltIn: "Экране с нотчем",
        .behaviourDisplayMain: "Основном экране",
        .behaviourDisplayActive: "Экране под курсором",
        .behaviourExpandOnHover: "Раскрывать наведением",
        .behaviourHoverDuration: "Задержка наведения",
        .behaviourHideFullscreen: "Прятать в фуллскрине",
        .behaviourHideGaming: "Прятать в играх",
        .behaviourHideCapture: "Прятать от записи экрана",
        .behaviourHideMenuBar: "Убрать иконку из меню-бара",
        .behaviourSimulatedNotch: "Всегда рисованный вырез",
        .behaviourNotchWidth: "Ширина выреза",
        .behaviourNotchHeight: "Высота выреза",
        .behaviourResetTuning: "Сбросить подгонку",
        .behaviourSwipeToSkip: "Смахивание переключает трек",
        .behaviourSwipeToToggle: "Смахивание открывает и закрывает",
        .behaviourGesturesHint: "Смахивайте прямо над вырезом: вбок — треки, вниз — открыть, вверх — убрать.",
        .behaviourGesturesBlocked: "Жестам нужен свёрнутый вырез — выключите «Раскрывать при наведении», иначе панель открывается раньше, чем поедут пальцы.",
        .behaviourTuningHint: "Подгонка меняет схлопнутую панель, а не сам вырез в железе.",


        .menuSettings: "Настройки…",
        .menuQuit: "Выйти",

        .settingsTitle: "Настройки Notch",
        .settingsTabGeneral: "Основные",
        .settingsTabModules: "Модули",
        .settingsTabAbout: "О программе",
        .settingsLanguage: "Язык",
        .settingsLanguageHint: "Применяется сразу, перезапуск не нужен.",
        .settingsLanguageSystem: "Системный",
        .settingsLaunchAtLogin: "Запускать при входе",
        .settingsStateOn: "Вкл",
        .settingsStateOff: "Выкл",
        .settingsLaunchAtLoginHint: "Будет подключено на следующих фазах.",
        .settingsModulesHint: "Включение, выключение и порядок модулей появятся на следующей фазе.",
        .settingsAboutVersion: "Версия",
        .settingsAboutHint: "Панель у верхнего края экрана.",
        .settingsTabLicense: "Лицензия",
        .proLockedTitle: "Этот модуль входит в Notch Pro",
        .proLockedHint: "Перевод, ИИ-чат и телесуфлёр открываются один раз — за 990 ₽. Без подписки.",
        .proBuy: "Получить Notch Pro",
        .proHaveKey: "У меня есть ключ",
        .licenseStatus: "Состояние",
        .licenseStatusLicensed: "Notch Pro — лицензия на %@",
        .licenseStatusExpired: "Нет ключа — модули Pro закрыты",
        .licenseKeyPlaceholder: "Вставьте лицензионный ключ",
        .licenseActivate: "Активировать",
        .licenseInvalid: "Ключ не подошёл. Скопируйте его целиком ещё раз.",
        .licenseDeactivate: "Убрать ключ с этого Мака",
        .licenseCoreFree: "Всё остальное остаётся бесплатным и с открытым кодом.",
        .licenseProIncludes: "Pro открывает: перевод, ИИ-чат, телесуфлёр.",
        .settingsUpdateAvailable: "Есть обновление"
    ]

    static func string(_ key: Key, _ language: AppLanguage) -> String {
        let table = language.resolved == .russian ? russian : english
        return table[key] ?? english[key] ?? key.rawValue
    }
}
