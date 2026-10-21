# Weather (Phase 29)

Spec: PRD 11.5, amendment LR-04 and RD-01 (the window), closet `DATA_MAP.md` (F14), `compliance/PERMISSIONS.md` (Location).

Live weather feeds two things: the Home window, and the weather in a styling request. It is **off until she turns it on** in Privacy and terms. Until the WeatherKit switch below is on for the build, a stand-in supplies the weather and nothing is sent anywhere.

## What she can do (Privacy and terms, Weather)

| Control | What it does |
|---|---|
| Live weather (switch) | On: the window and Style Me use the forecast. Off: they behave as before Phase 29 (the stand-in's weather in this test build; no weather once WeatherKit is on). |
| City | Type a city, pick a match. **No permission at all.** The words she types go to Apple Maps to find it (`MapKitCityFinder`), and only a name and a point rounded to 0.1 degree are kept. |
| Use my location (switch) | Optional. The app explains first (alert: Continue or Type a city instead), then iOS asks. Approximate only, While Using only. If iOS says no, or she turned it off in Settings later, the switch goes back to off, the note says why, "Open Settings" is offered, and the city keeps working. |

## Privacy rules built in

- Every coordinate goes through `CoarseCoordinate`, which rounds to 0.1 degree (about 11 km). Its only initializer rounds, and so does decoding.
- Location is requested with reduced accuracy (`NSLocationDefaultAccuracyReduced` is in `Configs/AppInfo.plist`, and the manager asks for reduced accuracy too). One fix at a time, no background location, no "Always". The raw fix never leaves `CoreLocationApproximateProvider`.
- Nothing about where she is is stored except the city she picked (name and rounded point, in a `UserDefaults` suite only this app reads, erased by Delete my data). Her position is in memory for up to an hour and is never logged.
- Only `WeatherSummary` may go into a styling request: condition, temperature, today's low and high in whole degrees, chance of precipitation to the nearest 10 percent, night or day. `WeatherSummaryTests` checks the exact keys. Phase 27a must serialize this type, not `WeatherSnapshot`.
- Apple's WeatherKit receives the rounded coordinate, which it needs by its nature. Nothing about weather goes to Convex or the stylist but the summary.

## Caching and limits

`PlaceWeatherProvider` asks the source at most once per place and hour, and shares one ask between simultaneous callers. There is no polling: Home and Style Me ask when they appear. If an ask fails (offline, over WeatherKit's call limit), the last forecast for that place stands in for up to 3 hours, then the weather reads as unavailable and everything else works as usual (LR-04.3). The cache is in memory only.

## Apple Weather credit

Apple requires its mark and a legal link wherever its data shows. `WeatherCreditView` is shown under Home's room (all three layouts), under Style Me's Weather row while "Use today's weather" is chosen, and in the weather settings. The mark comes from WeatherKit's attribution URLs (light and dark); the words "Apple Weather" stand in while it loads. The link goes to the URL WeatherKit returns, or Apple's published page if it can't be asked. It isn't shown for the stand-in weather in Release builds.

## Turning on WeatherKit (Jose)

1. Apple Developer, Certificates, Identifiers and Profiles, Identifiers, `com.jsayram.niftyoutfitnook`: tick **WeatherKit** under Capabilities, save. (Also in the App Services tab, it can take up to 30 minutes to be ready.)
2. Set `NOOK_WEATHERKIT = YES` in `Configs/Secrets.xcconfig` (ignored by git, so it applies to builds from your Mac), or in `Configs/Base.xcconfig` once you're sure. That one setting does two things: it signs the app with `Configs/NiftyOutfit-WeatherKit.entitlements` (which adds `com.apple.developer.weatherkit`) and it tells the app to use WeatherKit (`NookWeatherKitEnabled` in Info.plist).
3. In Xcode, Signing & Capabilities should now show WeatherKit. If signing fails with an entitlement error, step 1 isn't finished.
4. Build to a device and run the device checklist below.

Never crashes or shows an error when it's off: with `NOOK_WEATHERKIT = NO` (the default) no WeatherKit call is made. With it on but the service refusing (no capability yet, no network, over the limit), every failure is the same quiet "unavailable".

## Debug launch arguments (Debug builds only)

`-weather-cities fixture|offline` (a short fixed city list, or one that says offline), `-weather-location allowed|denied|ask|askDeny` (a scripted permission), `-weather-settings-memory` (keep her choices in memory). The sample weather itself is `-fixtures demo:weather=<state>` as before.

## Tests

`CoarseCoordinateTests`, `WeatherSummaryTests` (Models), `PlaceWeatherProviderTests` (Fixtures: the choices, the cache per place and hour, one ask for many callers, offline and stale), `WeatherSettingsStoreTests` (Services), `WeatherSettingsModelTests` and the `privacyWeather` and `liveWeather` snapshots (Features), `WeatherTests` (UI: pick a city, Home's window and the credit, location refused and the fallback, allowed, type a city instead).

## Needs a device

The real WeatherKit call (after the steps above): today's weather for a typed city and for approximate location, the Apple mark loading, the legal link, the call counting once per hour, and airplane mode showing the last forecast. iOS's real location alert and the Settings round trip.
