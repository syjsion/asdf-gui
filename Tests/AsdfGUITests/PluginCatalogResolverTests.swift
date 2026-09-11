import XCTest
@testable import AsdfGUI

final class PluginCatalogResolverTests: XCTestCase {
    func testExactEntryMatchesNameCaseInsensitively() {
        let catalog = [
            AsdfPluginCatalogEntry(name: "nodejs", url: "https://github.com/asdf-vm/asdf-nodejs.git"),
            AsdfPluginCatalogEntry(name: "python", url: "https://github.com/danhper/asdf-python.git")
        ]

        let match = PluginCatalogResolver.exactEntry(for: "NodeJS", in: catalog)

        XCTAssertEqual(match?.name, "nodejs")
        XCTAssertEqual(match?.url, "https://github.com/asdf-vm/asdf-nodejs.git")
    }

    func testExactEntryDoesNotUsePrefixOrSubstringMatches() {
        let catalog = [
            AsdfPluginCatalogEntry(name: "nodejs", url: "https://example.com/nodejs.git"),
            AsdfPluginCatalogEntry(name: "node-build", url: "https://example.com/node-build.git")
        ]

        XCTAssertNil(PluginCatalogResolver.exactEntry(for: "node", in: catalog))
    }

    func testExactEntryReturnsNilForMissingTool() {
        let catalog = [AsdfPluginCatalogEntry(name: "ruby", url: "https://example.com/ruby.git")]

        XCTAssertNil(PluginCatalogResolver.exactEntry(for: "python", in: catalog))
    }
}
