import XCTest
@testable import CmdSpace

final class CalculatorTests: XCTestCase {
    func testOperatorPrecedenceAndParentheses() {
        XCTAssertEqual(Calculator.evaluate("2 + 3 * 4")?.value, "14")
        XCTAssertEqual(Calculator.evaluate("(2 + 3) * 4")?.value, "20")
        XCTAssertEqual(Calculator.evaluate("2^3^2")?.value, "512")
        XCTAssertEqual(Calculator.evaluate("-2^2")?.value, "-4")
        XCTAssertEqual(Calculator.evaluate("1,000 + 2,500")?.value, "3500")
    }

    func testNaturalOperatorsPercentAndFactorial() {
        XCTAssertEqual(Calculator.evaluate("18 percent of 240")?.value, "43.2")
        XCTAssertEqual(Calculator.evaluate("20 divided by 4 plus 3")?.value, "8")
        XCTAssertEqual(Calculator.evaluate("6!")?.value, "720")
    }

    func testConstantsFunctionsAndDegrees() {
        XCTAssertEqual(Calculator.evaluate("sqrt(144)")?.value, "12")
        XCTAssertEqual(Calculator.evaluate("2pi")?.value, "6.28318530718")
        XCTAssertEqual(Calculator.evaluate("sin(30 deg)")?.value, "0.5")
        XCTAssertEqual(Calculator.evaluate("max(4, 9, 2)")?.value, "9")
        XCTAssertEqual(Calculator.evaluate("√144")?.value, "12")
        XCTAssertEqual(Calculator.evaluate("12 squared")?.value, "144")
        XCTAssertEqual(Calculator.evaluate("cbrt(-8)")?.value, "-2")
    }

    func testComplexArithmeticAndFunctions() {
        XCTAssertEqual(
            Calculator.evaluate("2 * e + pi * i ^ 2")?.value,
            "2.29497100333"
        )
        XCTAssertEqual(Calculator.evaluate("i^2")?.value, "-1")
        XCTAssertEqual(Calculator.evaluate("sqrt(-1)")?.value, "i")
        XCTAssertEqual(Calculator.evaluate("(1 + i) * (1 - i)")?.value, "2")
        XCTAssertEqual(Calculator.evaluate("2 + 3i")?.value, "2 + 3i")
        XCTAssertEqual(Calculator.evaluate("1 / i")?.value, "-i")
        XCTAssertEqual(Calculator.evaluate("abs(3 + 4i)")?.value, "5")
        XCTAssertEqual(Calculator.evaluate("exp(i * pi) + 1")?.value, "0")
        XCTAssertEqual(Calculator.evaluate("e ^ (pi * i)")?.value, "-1")
    }

    func testExplicitCalculatorPrefix() {
        XCTAssertEqual(Calculator.evaluate("= 42")?.value, "42")
        XCTAssertEqual(Calculator.evaluate("what is 7 * 8")?.value, "56")
        XCTAssertEqual(Calculator.evaluate("calc 1 / 8")?.value, "0.125")
    }

    func testDoesNotHijackOrdinaryQueries() {
        XCTAssertNil(Calculator.evaluate(""))
        XCTAssertNil(Calculator.evaluate("2026"))
        XCTAssertNil(Calculator.evaluate("Photoshop"))
        XCTAssertNil(Calculator.evaluate("report 2026"))
        XCTAssertNil(Calculator.evaluate("1 / 0"))
    }

    func testLengthAreaAndCompoundHeightConversions() {
        XCTAssertEqual(Calculator.evaluate("12 km to miles")?.value, "7.45645430685 mi")
        XCTAssertEqual(Calculator.evaluate("10 square feet to m2")?.value, "0.9290304 m²")
        XCTAssertEqual(Calculator.evaluate("5 ft 10 in to cm")?.value, "177.8 cm")
    }

    func testTemperatureMassAndVolumeConversions() {
        XCTAssertEqual(Calculator.evaluate("72 f in c")?.value, "22.2222222222 °C")
        XCTAssertEqual(Calculator.evaluate("0 c to f")?.value, "32 °F")
        XCTAssertEqual(Calculator.evaluate("10 lb to kg")?.value, "4.5359237 kg")
        XCTAssertEqual(Calculator.evaluate("2 gallons to liters")?.value, "7.570823568 L")
        XCTAssertEqual(Calculator.evaluate("-40 °C to °F")?.value, "-40 °F")
    }

    func testSpeedTimeAndStorageConversions() {
        XCTAssertEqual(Calculator.evaluate("60 mph to kmh")?.value, "96.56064 km/h")
        XCTAssertEqual(Calculator.evaluate("3 days to hours")?.value, "72 h")
        XCTAssertEqual(Calculator.evaluate("2 GiB to MB")?.value, "2147.483648 MB")
        XCTAssertEqual(Calculator.evaluate("3 * 4 km to m")?.value, "12000 m")
    }

    func testRejectsMismatchedOrIncompleteConversions() {
        XCTAssertNil(Calculator.evaluate("10 kg to miles"))
        XCTAssertNil(Calculator.evaluate("10 km to"))
        XCTAssertNil(Calculator.evaluate("km to miles"))
    }

    func testScientificUnitFamilies() {
        XCTAssertEqual(Calculator.evaluate("180 degrees to radians")?.value, "3.14159265359 rad")
        XCTAssertEqual(Calculator.evaluate("1 kwh to joules")?.value, "3600000 J")
        XCTAssertEqual(Calculator.evaluate("1 horsepower to kw")?.value, "0.745699871582 kW")
        XCTAssertEqual(Calculator.evaluate("1 atm to psi")?.value, "14.6959487755 psi")
        XCTAssertEqual(Calculator.evaluate("2.4 ghz to mhz")?.value, "2400 MHz")
    }
}
