import Testing

@testable import DesignSystem

struct RGBATests {
    @Test func readsHexChannels() {
        let colour = RGBA(hex: 0x4B3628)
        #expect(colour.red == 0x4B)
        #expect(colour.green == 0x36)
        #expect(colour.blue == 0x28)
        #expect(colour.alpha == 1)
        #expect(colour.description == "#4B3628")
    }

    @Test func describesOpacity() {
        #expect(RGBA(hex: 0x0A0B0C, alpha: 0.5).description == "#0A0B0C at 0.5")
    }

    @Test func contrastMatchesKnownWCAGValues() {
        let black = RGBA(hex: 0x000000)
        let white = RGBA(hex: 0xFFFFFF)
        #expect(RGBA.contrastRatio(black, white) == 21)
        #expect(RGBA.contrastRatio(white, white) == 1)
        #expect(RGBA.contrastRatio(white, black) == RGBA.contrastRatio(black, white))
        // #777777 on white is the textbook "just under 4.5" grey.
        let grey = RGBA.contrastRatio(RGBA(hex: 0x777777), white)
        #expect(abs(grey - 4.48) < 0.01)
    }

    @Test func compositesTintsLikeABrowser() {
        let wall = RGBA(hex: 0xF4EEE6)
        #expect(RGBA(hex: 0xFFFFFF, alpha: 0).composited(over: wall) == wall)
        #expect(RGBA(hex: 0x000000, alpha: 1).composited(over: wall) == RGBA(hex: 0x000000))
        // rgba(255,255,255,.55) over #F4EEE6: 255*.55 + 244*.45 = 250.05 -> 250, and so on.
        #expect(RGBA(hex: 0xFFFFFF, alpha: 0.55).composited(over: wall) == RGBA(red: 250, green: 247, blue: 244))
    }
}
