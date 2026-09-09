import XCTest
@testable import AsdfGUI

final class WriteOperationGateTests: XCTestCase {
    @MainActor
    func testExternalWriteGateParticipatesInHasActiveOperation() {
        let model = AppModel()

        XCTAssertFalse(model.hasActiveOperation)
        XCTAssertTrue(model.beginExternalWriteOperation())
        XCTAssertTrue(model.hasActiveOperation)
        XCTAssertFalse(model.beginExternalWriteOperation())

        model.endExternalWriteOperation()
        XCTAssertFalse(model.hasActiveOperation)
    }

    @MainActor
    func testEndingGateCannotUnderflow() {
        let model = AppModel()
        model.endExternalWriteOperation()
        XCTAssertEqual(model.externalWriteOperationCount, 0)
        XCTAssertFalse(model.hasActiveOperation)
    }
}
