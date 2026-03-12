//
//  s_wishlist_x2UITests.swift
//  s_wishlist_x2UITests
//
//  Created by K. Franklin on 2/23/2026.
//

import XCTest

final class s_wishlist_x2UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testOwnerCanRevealArchiveActionBySwipingLeftOnItemRow() throws {
        let app = XCUIApplication()
        app.launch()

        if app.buttons["Sign in or create account"].waitForExistence(timeout: 4) {
            try authenticateAndReachWishlistRoot(app: app)
        }

        try createWishlistIfNeeded(app: app)
        try openWishlistEditor(app: app)
        try addItemForSwipeValidation(app: app)

        let itemTitle = app.staticTexts["Swipe Test Item"]
        XCTAssertTrue(itemTitle.waitForExistence(timeout: 20), "Seed item did not appear in editor list.")
        itemTitle.swipeLeft()

        let archiveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Archive"))
        let archiveVisible = archiveButtons.allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
        XCTAssertTrue(archiveVisible, "Archive action was not revealed after swiping left.")
    }

    @MainActor
    private func authenticateAndReachWishlistRoot(app: XCUIApplication) throws {
        let entryButton = app.buttons["Sign in or create account"]
        XCTAssertTrue(entryButton.waitForExistence(timeout: 8))
        entryButton.tap()

        let signInSegment = app.segmentedControls.buttons["Sign in"]
        XCTAssertTrue(signInSegment.waitForExistence(timeout: 8))
        signInSegment.tap()

        let env = ProcessInfo.processInfo.environment
        guard
            let email = env["UITEST_OWNER_EMAIL"],
            let password = env["UITEST_OWNER_PASSWORD"],
            !email.isEmpty,
            !password.isEmpty
        else {
            throw XCTSkip("Set UITEST_OWNER_EMAIL and UITEST_OWNER_PASSWORD to run this verification.")
        }

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 8))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 8))
        passwordField.tap()
        passwordField.typeText(password)

        try tapHittableButton(label: "Sign in", in: app)

        let didReachWishlists = waitForAnyElement(
            timeout: 20,
            elements: [
                app.navigationBars["My wishlists"],
                app.staticTexts["My wishlists"],
                app.buttons["Log out"],
                app.buttons["Create wishlist"]
            ]
        )
        XCTAssertTrue(didReachWishlists, "Did not reach My wishlists after sign-in.")
    }

    @MainActor
    private func createWishlistIfNeeded(app: XCUIApplication) throws {
        if app.buttons["Create wishlist"].waitForExistence(timeout: 3) {
            app.buttons["Create wishlist"].tap()
            let titleField = app.textFields["Wishlist title"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 8))
            titleField.tap()
            titleField.typeText("Swipe Archive Validation")
            try tapHittableButton(label: "Create wishlist", in: app)
        }
    }

    @MainActor
    private func openWishlistEditor(app: XCUIApplication) throws {
        let editorTitle = app.navigationBars["Wishlist editor"]
        if editorTitle.waitForExistence(timeout: 4) {
            return
        }

        let wishlistCardTitle = app.staticTexts["Swipe Archive Validation"]
        if wishlistCardTitle.waitForExistence(timeout: 8) {
            wishlistCardTitle.tap()
        } else {
            let firstWishlistTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Birthday")).firstMatch
            XCTAssertTrue(firstWishlistTitle.waitForExistence(timeout: 8), "No wishlist card found to open editor.")
            firstWishlistTitle.tap()
        }

        XCTAssertTrue(editorTitle.waitForExistence(timeout: 20), "Wishlist editor was not opened.")
    }

    @MainActor
    private func addItemForSwipeValidation(app: XCUIApplication) throws {
        let existing = app.staticTexts["Swipe Test Item"]
        if existing.waitForExistence(timeout: 2) {
            return
        }

        let addItemToolbarButton = app.buttons["Add item"]
        XCTAssertTrue(addItemToolbarButton.waitForExistence(timeout: 8), "Add item toolbar button not found.")
        addItemToolbarButton.tap()

        let draftEditor = app.textViews.firstMatch
        XCTAssertTrue(draftEditor.waitForExistence(timeout: 8), "Add item form did not appear.")
        draftEditor.tap()
        draftEditor.typeText(
            "Title: Swipe Test Item\nPrice: $12.34\nDescription:\nArchive swipe verification item."
        )

        try tapHittableButton(label: "Add item", in: app)
    }

    @MainActor
    private func tapHittableButton(label: String, in app: XCUIApplication) throws {
        let query = app.buttons.matching(NSPredicate(format: "label == %@", label))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "\"\(label)\" button not found.")

        if let button = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
            button.tap()
            return
        }

        query.firstMatch.tap()
    }

    @MainActor
    private func waitForAnyElement(timeout: TimeInterval, elements: [XCUIElement]) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
