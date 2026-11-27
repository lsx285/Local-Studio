import XCTest

@MainActor
final class LocalStudioUITests: XCTestCase {
    private var app: XCUIApplication!
    private var composer: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "composer").firstMatch
    }
    private var userMessage: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "userMessage").firstMatch
    }
    private var assistantMessage: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assistantMessage").firstMatch
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
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 5))
        XCTAssertEqual(userMessage.label, "Short text")
        capture("03-conversation")
        userMessage.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        capture("04-context-menu")
        app.buttons["Edit"].tap()
        XCTAssertEqual(composer.value as? String, "Short text")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.buttons["newChat"].waitForExistence(timeout: 3))
        XCTAssertGreaterThan(app.buttons["newChat"].frame.midX, app.frame.width * 0.7)
        app.buttons["newChat"].tap()
        XCTAssertFalse(userMessage.exists)
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
        XCTAssertEqual(app.buttons["temporaryChat"].value as? String, "On")
        XCTAssertFalse(app.staticTexts["temporaryBanner"].exists)
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
            if scene == "attachments" || scene == "attachments-long" {
                app.scrollViews["attachmentRail"].swipeLeft()
                capture("reference-\(scene)-scrolled")
            }
        }
    }

    func testGenerationReferencePhases() {
        for offset in ["2", "3", "6.5", "11.5", "16.4", "16.8", "17.1", "17.3", "17.5"] {
            app.terminate()
            app.launchEnvironment["LOCAL_STUDIO_PREVIEW"] = "generation"
            app.launchEnvironment["LOCAL_STUDIO_GENERATION_OFFSET"] = offset
            app.launch()
            XCTAssertTrue(app.otherElements["generation"].waitForExistence(timeout: 5))
            capture("reference-generation-\(offset)")
        }
        app.terminate()
        app.launchEnvironment["LOCAL_STUDIO_PREVIEW"] = "empty"
        app.launchEnvironment.removeValue(forKey: "LOCAL_STUDIO_GENERATION_OFFSET")
        app.launch()
        composer.tap()
        composer.typeText("Generate a pond full of ducks each unique")
        app.buttons["sendPrompt"].tap()
        XCTAssertTrue(app.otherElements["generation"].waitForExistence(timeout: 3))
        let artwork = app.descendants(matching: .any).matching(identifier: "assistantArtwork").firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 22))
        XCTAssertFalse(app.otherElements["generation"].exists)
        capture("reference-generation-completed")
    }

    func testKeyboardSpacingAndContinuousMultilineFocus() {
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let plus = app.buttons["addPhotos"].frame
        let send = app.buttons["sendPrompt"].frame
        XCTAssertEqual(plus.minX - 8, 12, accuracy: 2)
        XCTAssertEqual(send.maxX + 8 - (plus.minX - 8), app.frame.width - 24, accuracy: 3)
        XCTAssertEqual(app.keyboards.firstMatch.frame.minY - send.maxY - 8, 12, accuracy: 3)
        capture("keyboard-empty")
        composer.typeText("Long text that keeps the same editor focused when it wraps into multiple lines. ")
        composer.typeText("Still focused.")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue((composer.value as? String ?? "").hasSuffix("Still focused."))
        XCTAssertGreaterThan(composer.frame.height, 32)
        capture("keyboard-multiline")
    }

    func testComposerSwipeKeyboardGestures() {
        composer.swipeUp()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        composer.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String ?? "", "")
        capture("keyboard-swipe-dismissed")
    }

    func testScrollToBottomDoesNotMoveComposer() {
        launchScene("history")
        let button = app.buttons["scrollToBottom"]
        XCTAssertFalse(button.exists)
        let composerBottom = app.buttons["sendPrompt"].frame.maxY
        app.scrollViews["conversation"].swipeDown()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["sendPrompt"].frame.maxY, composerBottom, accuracy: 1)
        capture("scroll-history-up")
        button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 5))
        let lastReply = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Reply 12.")).firstMatch
        XCTAssertTrue(lastReply.waitForExistence(timeout: 5))
        XCTAssertTrue(lastReply.isHittable)
        capture("scroll-history-bottom")
    }

    func testUserImageCopyOnlyMenu() {
        launchScene("artwork")
        let image = app.descendants(matching: .any).matching(identifier: "userAttachment").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save to photos"].exists)
        XCTAssertFalse(app.buttons["Share"].exists)
        capture("user-image-menu")
        app.buttons["Copy"].tap()
    }

    func testAssistantImageMenu() {
        launchScene("artwork")
        let image = app.descendants(matching: .any).matching(identifier: "assistantArtwork").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        image.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save to photos"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
        capture("assistant-image-menu")
        app.buttons["Copy"].tap()
    }

    func testSelectUserTextInBubble() {
        launchScene("conversation")
        let originalFrame = userMessage.frame
        userMessage.press(forDuration: 1)
        app.buttons["Select text"].tap()
        let selection = app.textViews.matching(NSPredicate(format: "identifier != %@", "composer")).firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        XCTAssertEqual(selection.value as? String, "Hello")
        XCTAssertTrue(originalFrame.intersects(selection.frame))
        XCTAssertFalse(app.navigationBars["Select text"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("inline-user-selection")
    }

    func testSelectAssistantTextInPlace() {
        launchScene("conversation")
        app.buttons["Response options"].firstMatch.tap()
        app.buttons["Select text"].tap()
        let selection = app.textViews.matching(NSPredicate(format: "identifier != %@", "composer")).firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        XCTAssertTrue((selection.value as? String ?? "").hasPrefix("Hello!"))
        XCTAssertFalse(app.navigationBars["Select text"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("inline-assistant-selection")
    }

    private func launchScene(_ scene: String) {
        app.terminate()
        app.launchEnvironment["LOCAL_STUDIO_PREVIEW"] = scene
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
