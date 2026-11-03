import Testing
@testable import Models

@Suite("Weight")
struct WeightTests {
    @Test("157.5 lb round-trips exactly through kilograms")
    func poundsRoundTrip() {
        let weight = Weight(157.5, .lb)
        #expect(abs(weight.value(in: .lb) - 157.5) < 1e-9)
    }

    @Test("155 lb is about 70.307 kg, and isn't rounded when stored")
    func poundsToKilograms() {
        let weight = Weight(155, .lb)
        #expect(abs(weight.kilograms - 70.30681735) < 1e-9)
    }

    @Test("Display rounding happens only on the way out")
    func displayRounding() {
        let weight = Weight(kilograms: 71.4408)
        #expect(abs(weight.displayValue(in: .lb) - 157.5) < 1e-9)
        #expect(abs(weight.displayValue(in: .kg) - 71.4) < 1e-9)
    }
}
