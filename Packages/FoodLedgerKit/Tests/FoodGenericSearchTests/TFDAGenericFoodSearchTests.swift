import Foundation
import FoodGenericSearch
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

final class TFDAGenericFoodSearchTests: XCTestCase {
    private func request(_ text: String, identity: GenericFoodIdentityQuery = .init()) throws -> GenericFoodSearchRequest {
        try .init(text: LedgerText(text), identity: identity, capturedAt: Date(timeIntervalSince1970: 1_700_000_000), locale: LedgerText("en_GB"))
    }
    private func route(_ source: any GenericFoodSearching, _ text: String) throws -> GenericFoodConfirmationRoute {
        guard case let .confirmation(route) = try source.search(request(text)) else {
            throw NSError(domain: "Missing expected TFDA result: " + text, code: 1)
        }
        return route
    }

    func testReviewedFruitVegetablesAndStaplesHaveBilingualRetrievalAndExactRecordProvenance() throws {
        let source = try TFDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        XCTAssertEqual(source.recordCount, 63)
        let cases = [("guava", "D15002"), ("芭樂", "D15002"), ("wax apple", "D18001"), ("lian wu", "D18001"),
            ("蓮霧", "D18001"), ("red dragon fruit", "D0700201"), ("longan", "D2300101"), ("lychee", "D22001"),
            ("sugar apple", "D1200101"), ("star fruit", "D16001"), ("pomelo", "D3500101"), ("papaya", "D02001"),
            ("water spinach", "E5600101"), ("空心菜", "E5600101"), ("sweet potato leaves", "E3100101"),
            ("bitter melon", "E6500101"), ("bok choy", "E3201201"), ("winter melon", "E62001"),
            ("okra", "E7600101"), ("shiitake mushroom", "G08001"), ("tofu", "R4700902"),
            ("unsweetened soy milk", "H1150201"), ("scallion pancake", "R2700101"), ("蔥油餅", "R2700101")]
        for (query, id) in cases {
            let route = try route(source, query)
            let candidate = try XCTUnwrap(route.matches.first { $0.candidate.candidate.recordID.value == "tfda:" + id }?.candidate)
            XCTAssertTrue(candidate.name.value.contains(" · "))
            XCTAssertEqual(candidate.candidate.identity.servingBasis, .per100Grams)
            XCTAssertEqual(route.confirmation.evidence[0].originalPayload, .text(try LedgerText(query)))
            XCTAssertEqual(FoodConfirmationState(input: route.confirmation).decision, .undecided)
            let release = try XCTUnwrap(route.confirmation.sourceReleases.first)
            XCTAssertEqual(release.sourceID.value, "tfda-taiwan")
            XCTAssertEqual(release.manifestHash.value, TFDAGenericFoodSearch.corpusSHA256)
            XCTAssertTrue(release.licence.value.contains("Open Government Data License"))
            for value in candidate.candidate.nutrients.entries.flatMap({ $0.value.provenance }) {
                XCTAssertEqual(value.sourceReleaseID, release.sourceReleaseID)
                XCTAssertEqual(value.recordID?.value, "tfda:" + id)
                XCTAssertTrue(value.manifestReference?.value.contains("每100克含量") == true)
            }
        }
    }

    func testLiteralValuesAndUnknownsDoNotGetConvertedOrFilledFromOtherRecords() throws {
        let source = try TFDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        let fruit = try route(source, "wax apple").matches[0].candidate.candidate
        for (field, amount) in [(NutrientKey.energyConsumed, 39.0), (.protein, 0.4), (.fatTotal, 0.3), (.carbohydrates, 10.0)] {
            guard case let .augmented(value) = fruit.nutrients.entries.first(where: { $0.key == field })?.value else { return XCTFail() }
            XCTAssertEqual(value.amount, amount)
            XCTAssertEqual(value.sourceValue, .exact(try SourceExactNutrientValue(amount: amount, unit: LedgerText(field.canonicalUnit.rawValue), basis: .per100Grams)))
        }
        XCTAssertEqual(fruit.identity.preparation.kind, .unknown)
        for field in [NutrientKey.water, .vitaminA, .vitaminD, .vitaminK] {
            XCTAssertEqual(fruit.nutrients.entries.first(where: { $0.key == field })?.value, .unknown(.notDeclared))
        }
        let pancake = try route(source, "scallion pancake").matches[0].candidate.candidate
        guard case let .augmented(energy) = pancake.nutrients.entries.first(where: { $0.key == .energyConsumed })?.value else { return XCTFail() }
        XCTAssertEqual(energy.amount, 305)
        XCTAssertEqual(pancake.identity.preparation.kind, .unknown)
    }

    func testPreparationFrozenAndDryFormsStaySeparateAndExtraIngredientsNeverDisappear() throws {
        let source = try TFDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        for (text, id, state) in [("raw bamboo shoots", "E1500101", PreparationKind.raw),
                                  ("cooked green bamboo shoots", "E1500201", .cooked),
                                  ("dried shiitake mushroom", "G08101", .unknown),
                                  ("frozen scallion pancake", "R2700201", .unknown)] {
            let found = try route(source, text)
            XCTAssertTrue(found.matches.contains { $0.candidate.candidate.recordID.value == "tfda:" + id })
            XCTAssertTrue(found.matches.allSatisfy { $0.candidate.candidate.identity.preparation.kind == state })
        }
        XCTAssertFalse(try route(source, "scallion pancake").matches.contains { $0.candidate.name.value.contains("frozen") })
        XCTAssertFalse(try route(source, "shiitake mushroom").matches.contains { $0.candidate.name.value.contains("dried") })
        for text in ["scallion pancake with eggs and cheese", "cooked water spinach", "raw cooked bamboo shoots",
                     "Puy lentils", "guava juice", "salted guava", "FAGE tofu", "wax apple yoghurt"] {
            guard case .noResult = try source.search(request(text)) else { return XCTFail("Unverified identity: " + text) }
        }
    }

    func testCountVolumeAndSpecificIdentityCannotInventMassOrPreparation() throws {
        let source = try TFDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        for text in ["2 wax apples", "200ml unsweetened soy milk"] {
            let input = try route(source, text).confirmation
            let state = FoodConfirmationState(input: input, queryQuantity: FoodQueryParser.parse(text).quantity)
            XCTAssertEqual(state.decision, .undecided)
            XCTAssertNil(state.quantity.conversion)
            if state.quantity.value != nil {
                let totals = FoodIntakeSummary(contributions: [FoodIntakeContribution(quantity: try state.quantity.calculatedEdibleQuantity(),
                    basis: input.candidates[0].candidate.identity.servingBasis, nutrients: input.candidates[0].candidate.nutrients)])
                XCTAssertTrue(totals.totals.allSatisfy { $0.knownAmount == nil })
            }
        }
        guard case .noResult = try source.search(request("wax apple", identity: .init(servingBasis: .per100Millilitres))) else { return XCTFail() }
        guard case .noResult = try source.search(request("guava", identity: .init(preparation: try PreparationState(kind: .cooked)))) else { return XCTFail() }
    }

    func testEveryReviewedAliasReachesItsOwnRecord() throws {
        let source = try TFDAGenericFoodSearch(ids: RandomLedgerIDGenerator())
        // Exposed development roster; independently reviewed source IDs, not an accuracy holdout.
        let cases = [("guava", "D15002"),
            ("ba le", "D15002"),
            ("芭樂", "D15002"),
            ("番石榴", "D15002"),
            ("wax apple", "D18001"),
            ("lian wu", "D18001"),
            ("蓮霧", "D18001"),
            ("white dragon fruit", "D0700101"),
            ("dragon fruit", "D0700101"),
            ("pitaya", "D0700101"),
            ("紅龍果", "D0700101"),
            ("白肉火龍果", "D0700101"),
            ("red dragon fruit", "D0700201"),
            ("dragon fruit", "D0700201"),
            ("pitaya", "D0700201"),
            ("紅肉火龍果", "D0700201"),
            ("longan", "D2300101"),
            ("long yan", "D2300101"),
            ("龍眼", "D2300101"),
            ("lychee", "D22001"),
            ("litchi", "D22001"),
            ("li zhi", "D22001"),
            ("荔枝", "D22001"),
            ("sugar apple", "D1200101"),
            ("sweet sop", "D1200101"),
            ("shi jia", "D1200101"),
            ("釋迦", "D1200101"),
            ("atemoya", "D1200201"),
            ("鳳梨釋迦", "D1200201"),
            ("star fruit", "D16001"),
            ("carambola", "D16001"),
            ("yang tao", "D16001"),
            ("楊桃", "D16001"),
            ("passion fruit", "D0400101"),
            ("bai xiang guo", "D0400101"),
            ("百香果", "D0400101"),
            ("pomelo", "D3500101"),
            ("wendan", "D3500101"),
            ("文旦", "D3500101"),
            ("indian jujube", "D3100101"),
            ("mi zao", "D3100101"),
            ("蜜棗", "D3100101"),
            ("banana", "D08001"),
            ("xiang jiao", "D08001"),
            ("香蕉", "D08001"),
            ("北蕉", "D08001"),
            ("pineapple", "D11002"),
            ("feng li", "D11002"),
            ("鳳梨", "D11002"),
            ("mango", "D21002"),
            ("mang guo", "D21002"),
            ("芒果", "D21002"),
            ("papaya", "D02001"),
            ("mu gua", "D02001"),
            ("木瓜", "D02001"),
            ("watermelon", "D19002"),
            ("red watermelon", "D19002"),
            ("西瓜", "D19002"),
            ("紅肉西瓜", "D19002"),
            ("watermelon", "D19004"),
            ("yellow watermelon", "D19004"),
            ("黃肉西瓜", "D19004"),
            ("persimmon", "D2600101"),
            ("筆柿", "D2600101"),
            ("sweet persimmon", "D2700201"),
            ("fuyu persimmon", "D2700201"),
            ("甜柿", "D2700201"),
            ("water spinach", "E5600101"),
            ("kong xin cai", "E5600101"),
            ("空心菜", "E5600101"),
            ("蕹菜", "E5600101"),
            ("pak choi", "E3200601"),
            ("xiao bai cai", "E3200601"),
            ("小白菜", "E3200601"),
            ("qingjiang pak choi", "E3201201"),
            ("bok choy", "E3201201"),
            ("qing jiang cai", "E3201201"),
            ("青江菜", "E3201201"),
            ("sweet potato leaves", "E3100101"),
            ("di gua ye", "E3100101"),
            ("地瓜葉", "E3100101"),
            ("甘藷葉", "E3100101"),
            ("bitter melon", "E6500101"),
            ("bitter gourd", "E6500101"),
            ("ku gua", "E6500101"),
            ("苦瓜", "E6500101"),
            ("loofah", "E6800101"),
            ("sponge gourd", "E6800101"),
            ("si gua", "E6800101"),
            ("絲瓜", "E6800101"),
            ("green bamboo shoots", "E1500101"),
            ("bamboo shoots", "E1500101"),
            ("綠竹筍", "E1500101"),
            ("cooked green bamboo shoots", "E1500201"),
            ("cooked bamboo shoots", "E1500201"),
            ("熟綠竹筍", "E1500201"),
            ("cooked arrow bamboo shoots", "E1600101"),
            ("cooked bamboo shoots", "E1600101"),
            ("熟箭竹筍", "E1600101"),
            ("winter melon", "E62001"),
            ("wax gourd", "E62001"),
            ("dong gua", "E62001"),
            ("冬瓜", "E62001"),
            ("aubergine", "E7300101"),
            ("eggplant", "E7300101"),
            ("long aubergine", "E7300101"),
            ("茄子", "E7300101"),
            ("長茄子", "E7300101"),
            ("okra", "E7600101"),
            ("qiu kui", "E7600101"),
            ("秋葵", "E7600101"),
            ("黃秋葵", "E7600101"),
            ("tomato", "E74001"),
            ("large red tomato", "E74001"),
            ("番茄", "E74001"),
            ("small red tomato", "E74004"),
            ("cherry tomato", "E74004"),
            ("小番茄", "E74004"),
            ("broccoli", "E5800402"),
            ("青花菜", "E5800402"),
            ("cabbage", "E3000104"),
            ("高麗菜", "E3000104"),
            ("甘藍", "E3000104"),
            ("chinese cabbage", "E33001"),
            ("napa cabbage", "E33001"),
            ("大白菜", "E33001"),
            ("結球白菜", "E33001"),
            ("chinese kale", "E3900101"),
            ("gai lan", "E3900101"),
            ("芥藍菜", "E3900101"),
            ("mustard greens", "E38004"),
            ("芥菜", "E38004"),
            ("white radish", "E0400101"),
            ("daikon", "E0400101"),
            ("白蘿蔔", "E0400101"),
            ("carrot", "E0200101"),
            ("胡蘿蔔", "E0200101"),
            ("cucumber", "E6400101"),
            ("胡瓜", "E6400101"),
            ("mung bean sprouts", "E7700701"),
            ("bean sprouts", "E7700701"),
            ("綠豆芽", "E7700701"),
            ("pumpkin", "E63001"),
            ("南瓜", "E63001"),
            ("baby corn", "E1300201"),
            ("玉米筍", "E1300201"),
            ("shiitake mushroom", "G08001"),
            ("香菇", "G08001"),
            ("dried shiitake mushroom", "G08101"),
            ("乾香菇", "G08101"),
            ("king oyster mushroom", "G1300101"),
            ("杏香菇", "G1300101"),
            ("white rice", "A0550601"),
            ("cooked rice", "A0550601"),
            ("白飯", "A0550601"),
            ("taro", "B0500101"),
            ("yu tou", "B0500101"),
            ("芋頭", "B0500101"),
            ("red sweet potato", "B0400401"),
            ("red flesh sweet potato", "B0400401"),
            ("紅肉甘藷", "B0400401"),
            ("yellow sweet potato", "B0400601"),
            ("yellow flesh sweet potato", "B0400601"),
            ("黃肉甘藷", "B0400601"),
            ("sweet corn", "A0400301"),
            ("甜玉米", "A0400301"),
            ("tofu", "R4700902"),
            ("traditional tofu", "R4700902"),
            ("dou fu", "R4700902"),
            ("豆腐", "R4700902"),
            ("傳統豆腐", "R4700902"),
            ("soft tofu", "R4701201"),
            ("嫩豆腐", "R4701201"),
            ("frozen tofu", "R4701001"),
            ("冷凍豆腐", "R4701001"),
            ("egg tofu", "R4701301"),
            ("雞蛋豆腐", "R4701301"),
            ("unsweetened soy milk", "H1150201"),
            ("無糖豆漿", "H1150201"),
            ("salted soy milk", "R5000301"),
            ("xian dou jiang", "R5000301"),
            ("鹹豆漿", "R5000301"),
            ("scallion pancake", "R2700101"),
            ("spring onion pancake", "R2700101"),
            ("cong you bing", "R2700101"),
            ("蔥油餅", "R2700101"),
            ("frozen scallion pancake", "R2700201"),
            ("冷凍蔥油餅", "R2700201"),
            ("chicken egg", "K01001"),
            ("whole egg", "K01001"),
            ("雞蛋", "K01001"),
            ("dried wheat noodles", "R2000101"),
            ("乾麵條", "R2000101")]
        for (query, id) in cases {
            let found = try route(source, query)
            XCTAssertTrue(found.matches.contains { $0.candidate.candidate.recordID.value == "tfda:" + id }, query)
        }
    }

    func testTamperedCorpusCannotLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{}".utf8).write(to: url)
        XCTAssertThrowsError(try TFDAGenericFoodSearch(corpusURL: url, ids: RandomLedgerIDGenerator())) {
            XCTAssertEqual($0 as? TFDASearchError, .hashMismatch)
        }
    }

    func testLocalCompositeFindsTaiwanFoodWithSharedEvidenceAndKeepsExistingSources() throws {
        let ids = RandomLedgerIDGenerator()
        let composite = try CompositeGenericFoodSearch(sources: [CoFIDGenericFoodSearch(ids: ids), USDAGenericFoodSearch(ids: ids), TFDAGenericFoodSearch(ids: ids)], ids: ids)
        let found = try route(composite, "wax apple")
        XCTAssertTrue(found.matches.contains { $0.candidate.candidate.recordID.value == "tfda:D18001" })
        XCTAssertEqual(found.confirmation.evidence.count, 1)
        let milk = try route(composite, "whole milk")
        XCTAssertTrue(milk.confirmation.sourceReleases.contains { $0.sourceID.value.contains("cofid") })
        XCTAssertTrue(milk.confirmation.sourceReleases.contains { $0.sourceID.value.contains("usda") })
    }
}
