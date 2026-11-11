import Foundation

/// Brief 80: what WeatherKit's current condition means for a companion. Core has no WeatherKit, so the table takes
/// `WeatherCondition`'s raw value (the case's own name, "heavyRain"); the app passes `condition.rawValue`.
///
/// Thunder and severe weather are `storm`; drizzle, rain, showers and freezing rain are `rain`; snow, sleet, flurries
/// and blizzards are `snow`; clear and mostly clear are `clear`; everything else (cloud, fog, haze, wind, heat, cold,
/// and any condition WeatherKit adds later) is `clouds`. An observation is never `unknown`.
extension CompanionSky {
    public init(weatherCondition: String) {
        self = Self.weatherConditions[weatherCondition] ?? .clouds
    }

    /// Every condition WeatherKit had in the Xcode 27.2 SDK, by name.
    public static let weatherConditions: [String: CompanionSky] = [
        // Thunder and severe weather.
        "thunderstorms": .storm, "isolatedThunderstorms": .storm, "scatteredThunderstorms": .storm,
        "strongStorms": .storm, "tropicalStorm": .storm, "hurricane": .storm, "hail": .storm,
        // Drizzle, rain, showers, freezing rain.
        "drizzle": .rain, "rain": .rain, "heavyRain": .rain, "sunShowers": .rain,
        "freezingDrizzle": .rain, "freezingRain": .rain,
        // Snow, sleet, flurries, blizzards.
        "snow": .snow, "heavySnow": .snow, "sleet": .snow, "flurries": .snow, "sunFlurries": .snow,
        "blizzard": .snow, "blowingSnow": .snow, "wintryMix": .snow,
        // Clear.
        "clear": .clear, "mostlyClear": .clear,
        // Everything else.
        "cloudy": .clouds, "mostlyCloudy": .clouds, "partlyCloudy": .clouds, "foggy": .clouds, "haze": .clouds,
        "smoky": .clouds, "blowingDust": .clouds, "breezy": .clouds, "windy": .clouds, "hot": .clouds,
        "frigid": .clouds,
    ]
}
