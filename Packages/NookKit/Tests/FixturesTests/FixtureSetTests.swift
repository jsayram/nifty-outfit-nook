import Fixtures
import Testing

struct FixtureSetTests {
    @Test(arguments: FixtureSet.allCases)
    func readsEachNamedSet(_ set: FixtureSet) {
        let arguments = ["NiftyOutfitNook", "-fixtures", set.rawValue]
        #expect(FixtureSet(launchArguments: arguments) == set)
    }

    @Test func defaultsToDemoWithoutTheFlag() {
        #expect(FixtureSet(launchArguments: ["NiftyOutfitNook"]) == .demo)
    }

    @Test func defaultsToDemoWhenTheValueIsMissing() {
        #expect(FixtureSet(launchArguments: ["NiftyOutfitNook", "-fixtures"]) == .demo)
    }

    @Test func defaultsToDemoForAnUnknownName() {
        #expect(FixtureSet(launchArguments: ["NiftyOutfitNook", "-fixtures", "huge"]) == .demo)
    }

    @Test func ignoresOtherArguments() {
        let arguments = ["NiftyOutfitNook", "-AppleLanguages", "(en)", "-fixtures", "large"]
        #expect(FixtureSet(launchArguments: arguments) == .large)
    }
}

struct FixtureConfigurationTests {
    @Test func readsASetAndABehavior() {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "large:stylist-fails"])
        #expect(configuration == FixtureConfiguration(set: .large, behavior: .stylistFails))
        #expect(FixtureSet(launchArguments: ["App", "-fixtures", "empty:offline"]) == .empty)
    }

    @Test(arguments: FixtureBehavior.allCases)
    func readsEachBehavior(_ behavior: FixtureBehavior) {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:\(behavior.rawValue)"])
        #expect(configuration.behavior == behavior)
    }

    @Test func unknownPartsFallBackToDemoAndNormal() {
        #expect(FixtureConfiguration(launchArguments: ["App"]) == FixtureConfiguration())
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo"]).behavior == .normal)
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:wobbly"]).behavior == .normal)
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "huge:slow"]).set == .demo)
    }
}
