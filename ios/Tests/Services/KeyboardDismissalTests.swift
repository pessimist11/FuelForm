import XCTest
import UIKit
@testable import FuelForm

@MainActor final class KeyboardDismissalTests: XCTestCase {
    func testDecimalFieldEndsEditingAndKeepsValue() throws {
        try withWindow { window, anchor in
            let field = UITextField(frame: CGRect(x: 20, y: 100, width: 200, height: 40))
            field.keyboardType = .decimalPad
            field.text = "75.5"
            window.rootViewController!.view.addSubview(field)
            XCTAssertTrue(field.becomeFirstResponder())
            let controller = KeyboardDismissalController()
            controller.anchor = anchor
            controller.dismiss()
            XCTAssertFalse(field.isFirstResponder)
            XCTAssertEqual(field.text, "75.5")
        }
    }

    func testMultilineInputWithoutFocusBindingEndsEditingAndKeepsText() throws {
        try withWindow { window, anchor in
            let field = UITextView(frame: CGRect(x: 20, y: 100, width: 200, height: 100))
            field.text = "合成备注\n第二行"
            window.rootViewController!.view.addSubview(field)
            XCTAssertTrue(field.becomeFirstResponder())
            let controller = KeyboardDismissalController()
            controller.anchor = anchor
            controller.dismiss()
            XCTAssertFalse(field.isFirstResponder)
            XCTAssertEqual(field.text, "合成备注\n第二行")
        }
    }

    private func withWindow(_ test: (UIWindow, UIView) throws -> Void) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; previous?.makeKey() }
        let anchor = UIView(frame: .zero)
        window.rootViewController!.view.addSubview(anchor)
        try test(window, anchor)
    }
}
