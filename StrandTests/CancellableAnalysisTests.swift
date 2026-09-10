import XCTest
@testable import Strand

final class CancellableAnalysisTests: XCTestCase {
    func testCancellationReachesDetachedCPUWorker() async {
        let started = expectation(description: "CPU worker started")
        let task = Task {
            await CancellableAnalysis.run {
                started.fulfill()
                while !Task.isCancelled { await Task.yield() }
                return Task.isCancelled
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }
}
