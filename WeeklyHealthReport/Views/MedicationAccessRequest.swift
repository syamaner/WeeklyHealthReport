import SwiftUI
import HealthKit
import HealthKitUI

/// Carries the long-lived HealthKit store from the app composition root to the
/// iOS 26 medication authorization modifier.
struct MedicationAccessRequest {
    let store: HKHealthStore
}

extension View {
    @available(iOS 26.0, *)
    func medicationAccessRequest(
        _ request: MedicationAccessRequest,
        trigger: Int,
        onResult: @escaping @Sendable (Result<Bool, any Error>) -> Void
    ) -> some View {
        healthDataAccessRequest(
            store: request.store,
            objectType: .userAnnotatedMedicationType(),
            trigger: trigger,
            completion: onResult
        )
    }
}
