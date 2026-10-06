import CoreLocation
import Foundation

/// Погода: сейчас, по часам на сутки и по дням на неделю.
///
/// Источник — Open-Meteo: без ключа и без аккаунта. WeatherKit от Apple
/// требует платного аккаунта разработчика и права в подписи, а бандл
/// подписывается своим сертификатом — этого системе мало.
///
/// Место выбирает пользователь: город поиском или «где я сейчас» через
/// геолокацию. По умолчанию не выбрано ничего — спрашивать разрешение на
/// геолокацию у того, кто модуль даже не открывал, незачем.
@MainActor
final class WeatherStore: ObservableObject {
    struct Place: Codable, Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
        /// Место взято из геолокации и обновляется само.
        var isCurrentLocation: Bool
    }

    struct Current: Equatable {
        let temperature: Double
        let apparent: Double
        let code: Int
        let isDay: Bool
        let wind: Double
        let humidity: Double
    }

    struct Hour: Identifiable, Equatable {
        var id: Date { time }
        let time: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
        let precipitation: Int
    }

    struct Day: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let precipitation: Int
        /// Восход и закат — по ним небо проходит утро, золотой час и сумерки.
        let sunrise: Date?
        let sunset: Date?
    }

    /// Найденный поиском город — ещё не выбранный.
    struct Candidate: Identifiable, Equatable {
        let id: Int
        let name: String
        let region: String
        let latitude: Double
        let longitude: Double
    }

    enum Status: Equatable {
        case idle, loading, failed, locationDenied
    }

    @Published private(set) var place: Place?
    @Published private(set) var current: Current?
    @Published private(set) var hours: [Hour] = []
    @Published private(set) var days: [Day] = []
    /// Часовой пояс места, а не Мака: «15:00» в Токио — это их пятнадцать.
    @Published private(set) var timeZone: TimeZone = .current
    @Published private(set) var status: Status = .idle

    /// Поиск города: он живёт здесь, потому что поле стоит в строке
    /// заголовка, а результаты — в содержимом модуля.
    @Published var isSearching = false
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var isLookingUp = false

    private let settings: AppSettings
    private let defaults: UserDefaults
    private var timer: Timer?
    private var lastFetch: Date?
    private var fetchTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private lazy var locator = WeatherLocator()

    private static let placeKey = "weather.place"
    /// Погода меняется медленно, а сервис бесплатный: чаще незачем.
    private static let refreshInterval: TimeInterval = 15 * 60

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.placeKey) {
            place = try? JSONDecoder().decode(Place.self, from: data)
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfStale() }
        }
    }

    /// Панель открыли — если данные старше интервала, подтягиваем.
    func refreshIfStale() {
        guard let lastFetch else { return refresh() }
        if Date().timeIntervalSince(lastFetch) >= Self.refreshInterval { refresh() }
    }

    func refresh() {
        guard let place else { return }
        if place.isCurrentLocation {
            // Ноутбук ездит — место берём свежее при каждом обновлении.
            locate()
        } else {
            fetch(for: place)
        }
    }

    // MARK: - Место

    func choose(_ candidate: Candidate) {
        setPlace(Place(
            name: candidate.name,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            isCurrentLocation: false
        ))
        closeSearch()
    }

    func useCurrentLocation() {
        closeSearch()
        locate()
    }

    func closeSearch() {
        isSearching = false
        query = ""
        candidates = []
    }

    private func setPlace(_ place: Place) {
        let moved = self.place.map {
            abs($0.latitude - place.latitude) > 0.01 || abs($0.longitude - place.longitude) > 0.01
        } ?? true
        self.place = place
        if let data = try? JSONEncoder().encode(place) {
            defaults.set(data, forKey: Self.placeKey)
        }
        // Старая погода чужого города хуже, чем никакой.
        if moved {
            current = nil
            hours = []
            days = []
        }
        fetch(for: place)
    }

    private func locate() {
        status = .loading
        locator.request { [weak self] result in
            guard let self else { return }
            switch result {
            case .denied:
                self.status = .locationDenied
            case .failed:
                // Геолокация не ответила — показываем прошлое место, если оно было.
                if let place = self.place { self.fetch(for: place) } else { self.status = .failed }
            case .located(let coordinate, let name):
                self.setPlace(Place(
                    name: name ?? self.place?.name ?? self.settings.t(.weatherMyLocation),
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    isCurrentLocation: true
                ))
            }
        }
    }

    // MARK: - Прогноз

    private func fetch(for place: Place) {
        fetchTask?.cancel()
        status = .loading
        fetchTask = Task { [weak self] in
            do {
                let forecast = try await OpenMeteo.forecast(latitude: place.latitude, longitude: place.longitude)
                guard !Task.isCancelled, let self else { return }
                self.apply(forecast)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.status = .failed
            }
        }
    }

    private func apply(_ forecast: OpenMeteo.Forecast) {
        timeZone = TimeZone(secondsFromGMT: forecast.utc_offset_seconds) ?? .current

        let now = forecast.current
        // NOTCH_WEATHER=95 или 0,n — подменить погоду для снимка вёрстки:
        // грозу и снег по заказу за окном не получить.
        let override = ProcessInfo.processInfo.environment["NOTCH_WEATHER"]?
            .split(separator: ",").map(String.init)
        current = Current(
            temperature: now.temperature_2m,
            apparent: now.apparent_temperature,
            code: override.flatMap { Int($0[0]) } ?? now.weather_code,
            isDay: override.map { $0.count < 2 || $0[1] != "n" } ?? (now.is_day == 1),
            wind: now.wind_speed_10m,
            humidity: now.relative_humidity_2m
        )

        // Сутки вперёд с текущего часа: прошедшие часы сегодняшнего дня
        // ни о чём не говорят.
        let hourStart = Date().timeIntervalSince1970 - 3600
        let hourly = forecast.hourly
        hours = hourly.time.indices
            .filter { Double(hourly.time[$0]) > hourStart }
            .prefix(24)
            .map { index in
                Hour(
                    time: Date(timeIntervalSince1970: Double(hourly.time[index])),
                    temperature: hourly.temperature_2m[index],
                    code: hourly.weather_code[index],
                    isDay: hourly.is_day[index] == 1,
                    precipitation: hourly.precipitation_probability[index] ?? 0
                )
            }

        let daily = forecast.daily
        days = daily.time.indices.map { index in
            Day(
                date: Date(timeIntervalSince1970: Double(daily.time[index])),
                code: daily.weather_code[index],
                high: daily.temperature_2m_max[index],
                low: daily.temperature_2m_min[index],
                precipitation: daily.precipitation_probability_max[index] ?? 0,
                sunrise: daily.sunrise.map { Date(timeIntervalSince1970: Double($0[index])) },
                sunset: daily.sunset.map { Date(timeIntervalSince1970: Double($0[index])) }
            )
        }

        lastFetch = Date()
        status = .idle
    }

    // MARK: - Поиск города

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            candidates = []
            isLookingUp = false
            return
        }
        isLookingUp = true
        let language = settings.language.resolved == .russian ? "ru" : "en"
        searchTask = Task { [weak self] in
            // Ищем, когда набор остановился, а не на каждую букву.
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            let found = (try? await OpenMeteo.search(text, language: language)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.candidates = found
            self.isLookingUp = false
        }
    }
}

// MARK: - Open-Meteo

/// Два запроса к Open-Meteo: прогноз и поиск города. Время просим в
/// секундах Unix — так не нужно разбирать строки в часовом поясе места.
enum OpenMeteo {
    struct Forecast: Decodable {
        let utc_offset_seconds: Int
        let current: CurrentBlock
        let hourly: HourlyBlock
        let daily: DailyBlock
    }

    struct CurrentBlock: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let is_day: Int
        let wind_speed_10m: Double
        let relative_humidity_2m: Double
    }

    struct HourlyBlock: Decodable {
        let time: [Int]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let is_day: [Int]
        let precipitation_probability: [Int?]
    }

    struct DailyBlock: Decodable {
        let time: [Int]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int?]
        let sunrise: [Int]?
        let sunset: [Int]?
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            let id: Int
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Result]?
    }

    static func forecast(latitude: Double, longitude: Double) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "wind_speed_unit", value: "ms")
        ]
        return try await get(components.url!)
    }

    static func search(_ name: String, language: String) async throws -> [WeatherStore.Candidate] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: name),
            .init(name: "count", value: "6"),
            .init(name: "language", value: language),
            .init(name: "format", value: "json")
        ]
        let response: SearchResponse = try await get(components.url!)
        return (response.results ?? []).map {
            WeatherStore.Candidate(
                id: $0.id,
                name: $0.name,
                region: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Геолокация

/// Одно определение места по запросу. Постоянно следить за перемещением
/// незачем: погоде хватает точки раз в четверть часа.
@MainActor
final class WeatherLocator: NSObject, @preconcurrency CLLocationManagerDelegate {
    enum Result {
        case located(CLLocationCoordinate2D, name: String?)
        case denied
        case failed
    }

    private let manager = CLLocationManager()
    private var pending: [(Result) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        // Городу хватает километров, а грубая точка приходит быстрее.
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func request(_ completion: @escaping (Result) -> Void) {
        pending.append(completion)
        guard pending.count == 1 else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.denied)
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !pending.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(.denied)
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, !pending.isEmpty else { return }
        // Название города — ради подписи в строке заголовка. Не нашлось —
        // не беда: погода от этого не меняется.
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] marks, _ in
            let name = marks?.first?.locality ?? marks?.first?.administrativeArea
            Task { @MainActor in
                self?.finish(.located(location.coordinate, name: name))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        finish(denied ? .denied : .failed)
    }

    private func finish(_ result: Result) {
        let callbacks = pending
        pending = []
        callbacks.forEach { $0(result) }
    }
}
