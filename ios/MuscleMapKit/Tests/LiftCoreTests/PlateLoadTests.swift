import Testing
import Models
@testable import LiftCore

/// AC-18 (specs/log-workout.llm.md, "Plates").
@Suite("Plate load")
struct PlateLoadTests {
    @Test("AC-18: the empty bar is the bar")
    func emptyBar() {
        #expect(PlateLoad(plateSet: .pounds).total == 45)
        #expect(PlateLoad(plateSet: .kilograms).total == 20)
    }

    @Test("AC-18: add puts a pair on, so the total grows by two plates")
    func addPairs() {
        var load = PlateLoad(plateSet: .pounds)
        load.add(45)
        #expect(load.pairs == [45])
        #expect(load.total == 135)
        load.add(10)
        #expect(load.pairs == [45, 10])
        #expect(load.total == 155)
    }

    @Test("AC-18: 155 lb reads 45 bar + 55 per side")
    func breakdownPounds() {
        var load = PlateLoad(plateSet: .pounds)
        load.add(45)
        load.add(10)
        #expect(load.breakdown == "45 bar + 55 per side")
    }

    @Test("AC-18: 100 kg reads 20 bar + 40 per side")
    func breakdownKilograms() {
        var load = PlateLoad(plateSet: .kilograms)
        load.add(25)
        load.add(15)
        #expect(load.total == 100)
        #expect(load.breakdown == "20 bar + 40 per side")
    }

    @Test("AC-18: the same plate twice adds two pairs")
    func samePlateTwice() {
        var load = PlateLoad(plateSet: .pounds)
        load.add(45)
        load.add(45)
        #expect(load.total == 225)
        #expect(load.breakdown == "45 bar + 90 per side")
    }

    @Test("AC-18: removeLast takes off the last pair added")
    func removeLast() {
        var load = PlateLoad(plateSet: .pounds)
        load.add(45)
        load.add(10)
        load.removeLast()
        #expect(load.pairs == [45])
        #expect(load.total == 135)
    }

    @Test("AC-18: removeLast on the empty bar leaves the empty bar")
    func removeLastOnEmpty() {
        var load = PlateLoad(plateSet: .pounds)
        load.removeLast()
        #expect(load.pairs.isEmpty)
        #expect(load.total == 45)
    }

    @Test("AC-18: reset goes back to the empty bar")
    func reset() {
        var load = PlateLoad(plateSet: .kilograms)
        load.add(20)
        load.add(5)
        load.reset()
        #expect(load.pairs.isEmpty)
        #expect(load.total == 20)
    }

    @Test("AC-18: nearestLoad for 157 lb is 155 lb")
    func nearest157() {
        let load = PlateLoad.nearestLoad(to: 157, with: .pounds)
        #expect(load.total == 155)
        #expect(load.plateSet == .pounds)
    }

    @Test("AC-18: nearestLoad for a load the plates can make is that load")
    func nearestExact() {
        #expect(PlateLoad.nearestLoad(to: 155, with: .pounds).total == 155)
        #expect(PlateLoad.nearestLoad(to: 135, with: .pounds).total == 135)
        #expect(PlateLoad.nearestLoad(to: 100, with: .kilograms).total == 100)
    }

    @Test("AC-18: nearestLoad never goes above the target")
    func nearestIsNotAbove() {
        for target in [46.0, 99.0, 156.0, 200.0, 317.0] {
            let total = PlateLoad.nearestLoad(to: target, with: .pounds).total
            #expect(total <= target)
            #expect(target - total < 5, "within one 2.5 lb pair of plates")
        }
    }

    @Test("AC-18: nearestLoad at or below the bar is the empty bar")
    func nearestBelowBar() {
        #expect(PlateLoad.nearestLoad(to: 45, with: .pounds).total == 45)
        #expect(PlateLoad.nearestLoad(to: 30, with: .pounds).total == 45)
        #expect(PlateLoad.nearestLoad(to: 0, with: .kilograms).total == 20)
    }
}
