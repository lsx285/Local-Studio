import XCTest

@MainActor
final class LocalStudioUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testComposerConversationAndNewChat() {
        capture("01-empty")
        let composer = app.textFields["composer"]
        composer.tap()
        composer.typeText("Short text")
        capture("02-short-composer")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["userMessage"].label, "Short text")
        capture("03-conversation")
        app.staticTexts["userMessage"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        capture("04-context-menu")
        app.buttons["Edit"].tap()
        XCTAssertEqual(app.textFields["composer"].value as? String, "Short text")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.buttons["newChat"].waitForExistence(timeout: 3))
        app.buttons["newChat"].tap()
        XCTAssertFalse(app.staticTexts["userMessage"].exists)
        XCTAssertTrue(app.buttons["temporaryChat"].exists)
    }

    func testMultilineGenerationAndCancellation() {
        app.textFields["composer"].tap()
        app.textFields["composer"].typeText("Generate an image of a pond with various animals residing in it")
        capture("05-long-composer")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.otherElements["generation"].waitForExistence(timeout: 5))
        capture("06-generation")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.buttons["sendPrompt"].exists)
        XCTAssertFalse(app.otherElements["generation"].exists)
    }

    func testTemporaryModeAndNativePhotoPicker() {
        app.buttons["temporaryChat"].tap()
        XCTAssertTrue(app.staticTexts["temporaryBanner"].exists)
        capture("07-temporary")
        app.buttons["addPhotos"].tap()
        // PHPicker runs in a system service; assert a presented sheet rather than private hierarchy details.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5) || app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("08-photo-picker")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
