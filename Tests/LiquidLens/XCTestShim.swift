// XCTestShim.swift

// The few XCTest assertions the lens tests use, so that they run as a plain macOS executable: the app has no test
// target, and the flex and motion plan are pure math.

import Foundation

// MARK: - XCTestCase

/// A test case: a fresh instance runs each test.
protocol XCTestCase {
    init()
}

nonisolated(unsafe) var failureCount = 0

private func fail(_ message: String, _ file: StaticString, _ line: UInt) {
    failureCount += 1
    print("\(file):\(line): error: \(message)")
}

func XCTAssertEqual<T: Equatable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    let a = lhs()
    let b = rhs()
    if a != b { fail("XCTAssertEqual failed: (\(a)) is not equal to (\(b)) \(message)", file, line) }
}

func XCTAssertEqual<T: FloatingPoint>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    accuracy: T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    let a = lhs()
    let b = rhs()
    if !(abs(a - b) <= accuracy) {
        fail("XCTAssertEqual failed: (\(a)) is not equal to (\(b)) +/- (\(accuracy)) \(message)", file, line)
    }
}

func XCTAssertGreaterThan<T: Comparable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    let a = lhs()
    let b = rhs()
    if !(a > b) { fail("XCTAssertGreaterThan failed: (\(a)) is not greater than (\(b))", file, line) }
}

func XCTAssertLessThan<T: Comparable>(
    _ lhs: @autoclosure () -> T,
    _ rhs: @autoclosure () -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    let a = lhs()
    let b = rhs()
    if !(a < b) { fail("XCTAssertLessThan failed: (\(a)) is not less than (\(b))", file, line) }
}

func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value() { fail("XCTAssertTrue failed", file, line) }
}

func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value() { fail("XCTAssertFalse failed", file, line) }
}

/// Runs each test on a fresh instance and reports it as XCTest does.
func run<Case: XCTestCase>(_: Case.Type, _ tests: [(String, (Case) -> () -> Void)]) {
    for (name, test) in tests {
        let before = failureCount
        test(Case())()
        print("Test Case '\(Case.self).\(name)' \(failureCount == before ? "passed" : "failed").")
    }
}
