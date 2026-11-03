import Testing
import Models
@testable import LiftCore

@Suite("Plate sets")
struct PlateSetTests {
    @Test("lb set: 45 lb bar and the mockup's plates")
    func pounds() {
        let set = PlateSet.standard(for: .lb)
        #expect(set.bar == 45)
        #expect(set.plates == [45, 35, 25, 10, 5, 2.5])
    }

    @Test("kg set: 20 kg bar and standard kg plates")
    func kilograms() {
        let set = PlateSet.standard(for: .kg)
        #expect(set.bar == 20)
        #expect(set.plates == [25, 20, 15, 10, 5, 2.5, 1.25])
    }

    @Test("Plates are listed heaviest first")
    func ordered() {
        for set in [PlateSet.pounds, .kilograms] {
            #expect(set.plates == set.plates.sorted(by: >))
        }
    }
}
