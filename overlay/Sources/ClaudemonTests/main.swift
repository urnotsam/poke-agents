import Foundation

let harness = Harness()
runLayoutTests(harness)
runStoreTests(harness)
exit(harness.report())
