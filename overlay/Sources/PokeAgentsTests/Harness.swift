import Foundation

/// A minimal test harness.
///
/// XCTest ships with Xcode, not with the Command Line Tools, and requiring a
/// full Xcode install just to run assertions would be a poor trade. This gives
/// the same red/green signal and a non-zero exit code for CI.
public final class Harness {
    private var failures: [String] = []
    private var passed = 0
    private var currentSuite = ""

    public init() {}

    public func suite(_ name: String, _ body: (Harness) -> Void) {
        currentSuite = name
        body(self)
    }

    public func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
        } catch {
            failures.append("\(currentSuite) › \(name): threw \(error)")
        }
    }

    public func expect(_ condition: Bool, _ message: @autoclosure () -> String,
                       file: StaticString = #file, line: UInt = #line) {
        if condition {
            passed += 1
        } else {
            failures.append("\(currentSuite): \(message()) [\(shortFile(file)):\(line)]")
        }
    }

    public func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                    file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected,
               "\(label) — expected \(expected), got \(actual)", file: file, line: line)
    }

    public func close(_ actual: Double, _ expected: Double, _ label: String,
                      accuracy: Double = 0.5,
                      file: StaticString = #file, line: UInt = #line) {
        expect(abs(actual - expected) <= accuracy,
               "\(label) — expected \(expected)±\(accuracy), got \(actual)",
               file: file, line: line)
    }

    public func report() -> Int32 {
        let total = passed + failures.count
        if failures.isEmpty {
            print("\n\(total) assertions passed.")
            return 0
        }
        print("\n\(failures.count) of \(total) assertions FAILED:\n")
        for failure in failures { print("  ✗ \(failure)") }
        return 1
    }

    private func shortFile(_ file: StaticString) -> String {
        URL(fileURLWithPath: "\(file)").lastPathComponent
    }
}
