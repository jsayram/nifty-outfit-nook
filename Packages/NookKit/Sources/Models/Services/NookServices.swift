/// Every service the app uses, as protocols. The app target builds one and hands it to the
/// screens; features never create services themselves.
///
/// Stage A fills it from a fixture set (`FixtureServices` in Fixtures). Stage B swaps in real
/// stores and providers without touching any screen.
public struct NookServices: Sendable {
    public var closet: any ClosetStore
    public var looks: any LookStore
    public var suitcases: any SuitcaseStore
    public var profile: any ProfileStore
    public var stylist: any Stylist
    public var weather: any WeatherProvider
    public var images: any ImageProvider

    public init(
        closet: any ClosetStore,
        looks: any LookStore,
        suitcases: any SuitcaseStore,
        profile: any ProfileStore,
        stylist: any Stylist,
        weather: any WeatherProvider,
        images: any ImageProvider
    ) {
        self.closet = closet
        self.looks = looks
        self.suitcases = suitcases
        self.profile = profile
        self.stylist = stylist
        self.weather = weather
        self.images = images
    }
}
