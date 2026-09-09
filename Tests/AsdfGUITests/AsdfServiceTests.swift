import XCTest
@testable import AsdfGUI

final class AsdfServiceTests: XCTestCase {
    func testParsePluginsWithURLs() {
        let output = """
        nodejs https://github.com/asdf-vm/asdf-nodejs.git
        python https://github.com/danhper/asdf-python.git
        """

        let plugins = AsdfService.parsePlugins(output)
        XCTAssertEqual(plugins.count, 2)
        XCTAssertEqual(plugins[0].name, "nodejs")
        XCTAssertEqual(plugins[0].url, "https://github.com/asdf-vm/asdf-nodejs.git")
        XCTAssertEqual(plugins[1].name, "python")
    }

    func testParsePluginWithoutURL() {
        let plugins = AsdfService.parsePlugins("nodejs\n")
        XCTAssertEqual(plugins, [AsdfPlugin(name: "nodejs", url: nil)])
    }
}
