import CoreGraphics
import Testing
@testable import PatterCore

@Suite("Keeping the HUD on screen")
struct GeometryTests {
    // Jordan's setup: main display, and a portrait one to its left that reaches lower.
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    let portrait = CGRect(x: -1080, y: -498, width: 1080, height: 1890)

    @Test func frameInsideAScreenIsLeftAlone() {
        let f = CGRect(x: 600, y: 400, width: 300, height: 111)
        #expect(Geometry.keepInside(f, screens: [main, portrait]) == f)
    }

    @Test func frameBelowTheBottomEdgeMovesUp() {
        // The stranded pill: 9 pt of it on the main display.
        let f = CGRect(x: 548, y: -35, width: 54, height: 44)
        #expect(Geometry.keepInside(f, screens: [main, portrait]) == CGRect(x: 548, y: 0, width: 54, height: 44))
    }

    @Test func expandedCardOverflowingStaysOnItsScreen() {
        let f = CGRect(x: 1800, y: 1000, width: 300, height: 213)
        #expect(Geometry.keepInside(f, screens: [main, portrait]) == CGRect(x: 1620, y: 837, width: 300, height: 213))
    }

    @Test func pickTheScreenItOverlapsMost() {
        // Mostly on the portrait display, slightly over the main one.
        let f = CGRect(x: -250, y: -400, width: 300, height: 111)
        #expect(Geometry.keepInside(f, screens: [main, portrait]) == CGRect(x: -300, y: -400, width: 300, height: 111))
    }

    @Test func frameOnNoScreenGoesToTheNearestOne() {
        let f = CGRect(x: 2500, y: 500, width: 300, height: 111)
        #expect(Geometry.keepInside(f, screens: [main, portrait]) == CGRect(x: 1620, y: 500, width: 300, height: 111))
    }

    @Test func noScreensChangesNothing() {
        let f = CGRect(x: 10, y: 10, width: 30, height: 30)
        #expect(Geometry.keepInside(f, screens: []) == f)
    }
}
