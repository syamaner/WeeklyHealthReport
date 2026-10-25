import FoodLedgerApplication
import FoodLedgerDomain

/// One generic renderer for typed Log requirements and inline decision copy.
/// Copy never tells the user which disclosure to open.
public enum FoodLogRequirementText {
    public static func text(_ requirement: FoodLogRequirement) -> String {
        switch requirement {
        case let .decideDifference(facet):
            "Answer ‘\(question(facet))’ to log."
        case let .sourceIdentityMissing(details):
            "This source does not say: \(detailNames(details)). Choose a different match or add the food details."
        case .amountMissing:
            "Enter an amount greater than zero."
        case .amountTextInvalid:
            "Enter the amount as a number greater than zero, or clear it."
        case .recipeServingsRequired:
            "Enter the number of recipe servings eaten. A weighed portion cannot be converted because the cooked serving weight is unknown."
        case .sourceServingsRequired:
            "Enter the number of source servings eaten. The source gives no serving weight for conversion."
        case .measuredWeightMissing:
            "Enter the total edible weight in grams, greater than zero. Weigh only the food you ate."
        case .weightBasisMissing:
            "Choose whether you weighed it or estimated it."
        case .retainedWeightNeedsConfirmation:
            "The food changed. Check that the weight still describes it, then choose ‘Keep this weight’."
        case .countNeedsMeasuredAmount:
            "Enter the total weight and how you got it, or change the unit to g or mL."
        case .emptyPlateWeightMissing:
            "Enter the empty plate weight, or choose food only."
        case .plateNeedsGramTotal:
            "Plate subtraction needs a total weight in grams."
        case .plateNotLighterThanTotal:
            "The total weight must be greater than the empty plate weight."
        case .occurredAtInFuture:
            "Choose a time that is not in the future."
        case .occurredAtTooEarly:
            "Choose a time within the last \(FoodLogPolicy.backdatingDays) days."
        }
    }

    public static func question(_ facet: IdentityContradiction) -> String {
        switch facet {
        case .preparation: "How was it prepared?"
        case .bone: "Was it on the bone?"
        case .skin: "Was the skin eaten?"
        case .drained: "Was it drained?"
        case .packingMedium: "Was it in the same liquid?"
        case .fortification: "Was it fortified?"
        case .servingBasis: "Use the source’s nutrition basis?"
        case .edibleQuantity: "Use the source’s serving?"
        }
    }

    public static func choice(_ choice: FoodLogDecisionChoice, facet: IdentityContradiction, source: FoodLogSourceState) -> String {
        switch choice {
        case .matchesSource:
            facet == .packingMedium ? "Same as the source" : "\(state(source.token)), as the source"
        case let .differs(value): state(value)
        case .differentMediumOrNone: "Different liquid or none"
        case .notSure: "Not sure"
        case .useSourceBasis: "Use the source’s basis"
        case .useSourceServing: "Use the source’s serving"
        }
    }

    public static func result(_ choice: FoodLogDecisionChoice) -> String {
        choice.isEstimate ? "Logged as an estimate." : "Matches the source."
    }

    static func state(_ token: String) -> String {
        switch token {
        case "as_sold": "As sold"
        case "raw": "Raw"
        case "cooked": "Cooked"
        case "reheated": "Reheated"
        case "named": "As described"
        case "with_bone": "On the bone"
        case "boneless": "Boneless"
        case "skin_on": "With skin"
        case "skinless": "No skin"
        case "drained": "Drained"
        case "undrained": "Not drained"
        case "fortified": "Fortified"
        case "unfortified": "Not fortified"
        case "not_applicable": "Not applicable"
        default: token.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func detailNames(_ details: [IdentityContradiction]) -> String {
        details.map { detail in
            switch detail {
            case .preparation: "raw/cooked preparation"
            case .bone: "bone"
            case .skin: "skin"
            case .drained: "drained state"
            case .packingMedium: "packing liquid or none"
            case .fortification: "fortification"
            case .servingBasis: "nutrition basis"
            case .edibleQuantity: "edible amount"
            }
        }.joined(separator: ", ")
    }
}
