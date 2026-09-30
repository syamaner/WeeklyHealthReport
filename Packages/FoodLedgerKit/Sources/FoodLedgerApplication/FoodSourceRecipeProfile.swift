import Foundation
import FoodLedgerDomain

/// Correspondence to one captured recipe, not the user's food identity or quantity.
public struct FoodSourceRecipeProfile: Equatable, Sendable {
    public static let version = "food-source-recipe-evidence-v1"
    public static let schema = "recipe-source-panel-v1"
    public struct Declaration: Equatable, Sendable {
        public let field: NutrientKey
        public let value: SourceExactNutrientValue
        public let literal: String
        public let jsonPointer: String
        public let visibleValueNode: Int
        public let visibleUnitNode: Int
        public init(field: NutrientKey, value: SourceExactNutrientValue, literal: String,
                    jsonPointer: String, visibleValueNode: Int, visibleUnitNode: Int) {
            self.field = field; self.value = value; self.literal = literal
            self.jsonPointer = jsonPointer; self.visibleValueNode = visibleValueNode; self.visibleUnitNode = visibleUnitNode
        }
    }
    public let name: String
    public let recordID: String
    public let htmlSHA256: String
    public let recipePointer: String
    public let servings: Double
    public let servingLiteral: String
    public let ingredients: [String]
    public let declarations: [Declaration]
    public var cookedWeightGrams: Double? { nil }
    public static var basis: ResolutionBasis {
        // These closed literals satisfy the existing validated domain types.
        .named(try! LedgerText("1 recipe serving"), try! PositiveQuantity(value: 1, unit: .count))
    }
    public init(name: String, recordID: String, htmlSHA256: String, recipePointer: String,
                servings: Double, servingLiteral: String, ingredients: [String], declarations: [Declaration]) throws {
        guard !name.isEmpty, name.count <= 300, !recordID.isEmpty, recipePointer.hasPrefix("/"),
              htmlSHA256.count == 64, htmlSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
              servings.isFinite, servings > 0, servings <= 100_000, servingLiteral == "1 serving",
              ingredients.count <= 128, ingredients.allSatisfy({ !$0.isEmpty && $0.count <= 1000 }),
              Set(declarations.map(\.field)) == [.energyConsumed, .fatTotal, .carbohydrates, .protein], declarations.count == 4,
              declarations.allSatisfy({ $0.value.basis == Self.basis && $0.value.unit.value == $0.field.canonicalUnit.rawValue
                  && !$0.literal.isEmpty && $0.jsonPointer.hasPrefix(recipePointer + "/nutrition/")
                  && $0.visibleValueNode > 0 && $0.visibleUnitNode > 0 }) else {
            throw FoodSourceBindingError.invalidDocument
        }
        self.name = name; self.recordID = recordID; self.htmlSHA256 = htmlSHA256; self.recipePointer = recipePointer
        self.servings = servings; self.servingLiteral = servingLiteral; self.ingredients = ingredients; self.declarations = declarations
    }
}
