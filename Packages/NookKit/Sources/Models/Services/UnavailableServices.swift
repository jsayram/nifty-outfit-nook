import Foundation

extension NookServices {
    /// Services that can't do anything: every store call fails with `StoreError.unavailable` and
    /// every provider fails too. It's what a screen gets when nothing put real services in its
    /// environment (a preview, or a test that doesn't need data), so it shows its error state
    /// instead of pretending to load or save. The app always supplies real services.
    public static let unavailable = NookServices(
        closet: UnavailableStore(),
        looks: UnavailableStore(),
        suitcases: UnavailableStore(),
        profile: UnavailableStore(),
        stylist: UnavailableProvider(),
        weather: UnavailableProvider(),
        images: UnavailableProvider(),
        drafts: UnavailableStore(),
        photos: UnavailableProvider(),
        descriptions: UnavailableProvider(),
        cutouts: UnavailableProvider(),
        lookDrafts: UnavailableStore(),
        pictures: UnavailableStore(),
        tryOn: UnavailableProvider(),
        tours: UnavailableStore(),
        onboarding: UnavailableStore()
    )
}

/// Every store protocol, failing every call with `unavailable`.
private struct UnavailableStore: ClosetStore, LookStore, SuitcaseStore, ProfileStore, DraftStore, LookDraftStore,
    TryOnPictureStore, TourProgressStore, OnboardingStateStore
{
    func eraseAll() async throws(StoreError) { throw .unavailable }

    // ClosetStore
    func garments() async throws(StoreError) -> [Garment] { throw .unavailable }
    func garment(_ id: Garment.ID) async throws(StoreError) -> Garment { throw .unavailable }
    func save(_ garment: Garment) async throws(StoreError) { throw .unavailable }
    func update(_ id: Garment.ID, _ change: @Sendable (inout Garment) -> Void) async throws(StoreError) -> Garment {
        throw .unavailable
    }
    func recordWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) { throw .unavailable }
    func removeWear(of ids: [Garment.ID], on date: Date) async throws(StoreError) { throw .unavailable }
    func setLaundry(_ state: LaundryState, for ids: [Garment.ID]) async throws(StoreError) { throw .unavailable }
    func delete(_ id: Garment.ID, at date: Date) async throws(StoreError) { throw .unavailable }
    func restore(_ id: Garment.ID) async throws(StoreError) { throw .unavailable }
    func purgeExpired(asOf date: Date) async throws(StoreError) -> [Garment.ID] { throw .unavailable }

    // LookStore
    func looks() async throws(StoreError) -> [Look] { throw .unavailable }
    func look(_ id: Look.ID) async throws(StoreError) -> Look { throw .unavailable }
    func save(_ look: Look) async throws(StoreError) { throw .unavailable }
    func update(_ id: Look.ID, _ change: @Sendable (inout Look) -> Void) async throws(StoreError) -> Look {
        throw .unavailable
    }
    func delete(_ id: Look.ID) async throws(StoreError) { throw .unavailable }
    func recordWear(of id: Look.ID, on date: Date) async throws(StoreError) { throw .unavailable }
    func removeWear(of id: Look.ID, on date: Date) async throws(StoreError) { throw .unavailable }

    // SuitcaseStore
    func suitcases() async throws(StoreError) -> [Suitcase] { throw .unavailable }
    func suitcase(_ id: Suitcase.ID) async throws(StoreError) -> Suitcase { throw .unavailable }
    func create(name: String, icon: SuitcaseIcon, at date: Date) async throws(StoreError) -> Suitcase {
        throw .unavailable
    }
    func update(_ id: Suitcase.ID, _ change: @Sendable (inout Suitcase) -> Void) async throws(StoreError) -> Suitcase {
        throw .unavailable
    }
    func add(_ garmentIDs: [Garment.ID], to id: Suitcase.ID) async throws(StoreError) { throw .unavailable }
    func remove(_ garmentIDs: [Garment.ID], from id: Suitcase.ID) async throws(StoreError) { throw .unavailable }
    func markUsed(_ id: Suitcase.ID, at date: Date) async throws(StoreError) { throw .unavailable }
    func delete(_ id: Suitcase.ID) async throws(StoreError) { throw .unavailable }
    func restore(_ suitcase: Suitcase) async throws(StoreError) { throw .unavailable }

    // ProfileStore
    func profile() async throws(StoreError) -> Profile { throw .unavailable }
    func save(_ profile: Profile) async throws(StoreError) { throw .unavailable }
    func update(_ change: @Sendable (inout Profile) -> Void) async throws(StoreError) -> Profile { throw .unavailable }

    // DraftStore
    func drafts() async throws(StoreError) -> [GarmentDraft] { throw .unavailable }
    func draft(for target: GarmentDraft.Target) async throws(StoreError) -> GarmentDraft? { throw .unavailable }
    func save(_ draft: GarmentDraft) async throws(StoreError) { throw .unavailable }
    func discard(_ target: GarmentDraft.Target) async throws(StoreError) { throw .unavailable }

    // LookDraftStore
    func draft() async throws(StoreError) -> LookDraft? { throw .unavailable }
    func save(_ draft: LookDraft) async throws(StoreError) { throw .unavailable }
    func discard() async throws(StoreError) { throw .unavailable }

    // TryOnPictureStore
    func pictures() async throws(StoreError) -> [TryOnPicture] { throw .unavailable }
    func picture(_ id: TryOnPicture.ID) async throws(StoreError) -> TryOnPicture { throw .unavailable }
    func save(_ picture: TryOnPicture) async throws(StoreError) { throw .unavailable }
    func delete(_ id: TryOnPicture.ID) async throws(StoreError) { throw .unavailable }

    // TourProgressStore
    func progress() async throws(StoreError) -> TourProgress { throw .unavailable }
    func record(_ record: TourRecord) async throws(StoreError) { throw .unavailable }
    func setShowsTipsOnNewScreens(_ isOn: Bool) async throws(StoreError) { throw .unavailable }
    func forgetSeenTours() async throws(StoreError) { throw .unavailable }

    // OnboardingStateStore
    func state() async throws(StoreError) -> OnboardingState { throw .unavailable }
    func complete(startingCloset closet: StartingCloset) async throws(StoreError) { throw .unavailable }
}

/// Every provider protocol, failing every call.
private struct UnavailableProvider: Stylist, WeatherProvider, ImageProvider, PhotoIntake, GarmentDescriptionReader,
    CutoutService, TryOnService
{
    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome { throw .notCompleted }
    func currentWeather() async throws(WeatherError) -> WeatherSnapshot { throw .unavailable }
    func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
        throw .unavailable
    }
    func photo(from source: PhotoSource) async throws(PhotoIntakeError) -> PhotoReference { throw .unreadable }
    func suggestions(for description: String) async throws(DescriptionError) -> [GarmentSuggestion] {
        throw .unavailable
    }
    func cutout(from imageData: Data) async throws(CutoutError) -> CutoutResult { throw .failed }
    func makePicture(of look: Look, at date: Date) async throws(TryOnError) -> TryOnPicture { throw .notCompleted }
}
