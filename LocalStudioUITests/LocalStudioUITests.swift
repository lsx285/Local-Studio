import XCTest

@MainActor
final class LocalStudioUITests: XCTestCase {
    private var app: XCUIApplication!
    private var composer: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "composer").firstMatch
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertFalse(app.buttons["Chat"].exists)
        XCTAssertFalse(app.buttons["Work"].exists)
    }

    func testComposerConversationAndNewChat() {
        capture("01-empty")
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
        XCTAssertEqual(composer.value as? String, "Short text")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.buttons["newChat"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(app.buttons["newChat"].frame.midX, app.frame.width * 0.7)
        app.buttons["newChat"].tap()
        XCTAssertFalse(app.staticTexts["userMessage"].exists)
        XCTAssertTrue(app.buttons["temporaryChat"].exists)
    }

    func testMultilineGenerationAndCancellation() {
        composer.tap()
        composer.typeText("Generate an image of a pond with various animals residing in it")
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
        // Picker content belongs to a private system service; our surrounding controls remain testable.
        XCTAssertTrue(app.buttons["closePhotoGallery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirmPhotos"].exists)
        capture("08-photo-picker")
        app.buttons["closePhotoGallery"].tap()
        XCTAssertFalse(app.buttons["closePhotoGallery"].exists)
    }

    func testReferenceScenes() {
        for scene in ["empty", "short", "long", "attachments", "attachments-long", "conversation", "generation"] {
            app.terminate()
            app.launchEnvironment["LOCAL_STUDIO_PREVIEW"] = scene
            app.launch()
            XCTAssertTrue(app.buttons["addPhotos"].waitForExistence(timeout: 5))
            capture("reference-\(scene)")
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
