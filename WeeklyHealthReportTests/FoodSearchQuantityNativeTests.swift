import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import FoodLedgerPresentation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class FoodSearchQuantityNativeTests: XCTestCase {
    func testSelectedCandidateRendersEditableParsedQuantityWithoutAutomaticSave() async throws {
        let ids = NativeQuantityIDs()
        let searcher = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids),USDAGenericFoodSearch(ids: ids)],ids:ids)
        for (query,amount,unit) in [("200g Greek yoghurt 10% fat",200.0,QuantityUnit.grams),
            ("0.25kg rice",250.0,.grams),("200ml milk",200.0,.millilitres),("2 eggs",2.0,.count)] {
            let search = try GenericFoodSearchViewModel(searcher:searcher,locale:LedgerText("en_GB"))
            search.query=query;search.search()
            let input = try XCTUnwrap(search.confirmation(at:1),query)
            var saves=0
            let model=FoodConfirmationViewModel(state:FoodConfirmationState(input:input,queryQuantity:search.parsedQuery?.quantity)) { _ in
                saves += 1;throw CocoaError(.fileWriteUnknown)
            }
            let host=UIHostingController(rootView:NavigationStack { FoodConfirmationView(model:model,leave:{}) })
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            let window=UIWindow(windowScene:scene);window.frame=CGRect(x:0,y:0,width:430,height:932);window.rootViewController=host
            window.makeKeyAndVisible()
            defer { window.isHidden=true; previousKeyWindow?.makeKey() }
            host.view.layoutIfNeeded()
            var field:UITextField?
            for _ in 0..<24 {
                try await Task.sleep(for:.milliseconds(100))
                host.view.layoutIfNeeded()
                field=descendants(host.view).compactMap { $0 as? UITextField }.first { $0.text == String(amount) }
                if field != nil { break }
                if let scroll=descendants(host.view).compactMap({ $0 as? UIScrollView }).first {
                    scroll.setContentOffset(CGPoint(x:0,y:min(scroll.contentOffset.y+400,max(0,scroll.contentSize.height-scroll.bounds.height))),animated:false)
                }
            }
            let diagnostics = descendants(host.view).compactMap { view -> String? in
                if let text = view as? UITextField { return "field: \(text.text ?? "nil") / \(text.accessibilityLabel ?? "nil")" }
                if let scroll = view as? UIScrollView { return "scroll: \(scroll.contentOffset) size \(scroll.contentSize)" }
                return nil
            }.joined(separator:"; ")
            let quantityField=try XCTUnwrap(field,"Quantity should render \(amount) for \(query). \(diagnostics)")
            XCTAssertEqual(model.state.quantity.unit,unit)
            quantityField.text=String(amount+5);quantityField.sendActions(for:.editingChanged)
            try await Task.sleep(for:.milliseconds(100))
            XCTAssertEqual(model.state.quantity.value,amount+5,query)
            XCTAssertEqual(model.state.quantity.unit,unit)
            XCTAssertEqual(saves,0);XCTAssertEqual(model.state.decision,.undecided)
        }
    }
    private func descendants(_ view:UIView)->[UIView] { [view]+view.subviews.flatMap(descendants) }
}
private final class NativeQuantityIDs:LedgerIDGenerating,@unchecked Sendable {
    private var value=1
    func makeID<Tag>(_ tag:Tag.Type)throws->LedgerID<Tag> {
        defer { value += 1 };return try LedgerID(String(format:"00000000-0000-0000-0000-%012x",value))
    }
}
