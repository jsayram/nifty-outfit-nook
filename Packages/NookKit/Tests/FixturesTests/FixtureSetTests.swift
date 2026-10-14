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
