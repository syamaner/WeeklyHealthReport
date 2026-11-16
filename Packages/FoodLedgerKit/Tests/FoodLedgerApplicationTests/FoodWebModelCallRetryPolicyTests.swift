import Foundation
import FoodLedgerApplication
import FoodLedgerDomain
import XCTest

/// #500: the web lookup model-call retry rules, driven with synthetic outcomes, dates and jitter.
final class FoodWebModelCallRetryPolicyTests: XCTestCase {
    private typealias Policy = FoodWebModelCallRetryPolicy
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyTransientClassesAreRetryable() {
        XCTAssertTrue(Policy.isRetryable(.transportError))
        XCTAssertTrue(Policy.isRetryable(.timedOut))
        for status in [408, 429, 500, 502, 503, 504] {
            XCTAssertTrue(Policy.isRetryable(.httpStatus(status, retryAfter: nil)), "\(status)")
        }
        for status in [400, 401, 402, 403, 404, 422, 501, 505, 529] {
            XCTAssertFalse(Policy.isRetryable(.httpStatus(status, retryAfter: nil)), "\(status)")
            XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .httpStatus(status, retryAfter: "1"), elapsed: 0, now: now, jitter: 0),
                           .stop(.notRetryable))
        }
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .notRetryable, elapsed: 0, now: now, jitter: 0), .stop(.notRetryable))
    }

    func testAtMostThreeAttemptsWithExponentialBackoff() {
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .transportError, elapsed: 0, now: now, jitter: 1),
                       .retry(after: 1, timeout: 90))
        XCTAssertEqual(Policy.next(afterAttempt: 2, outcome: .transportError, elapsed: 0, now: now, jitter: 1),
                       .retry(after: 2, timeout: 90))
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 0, now: now, jitter: 0),
                       .retry(after: 0.5, timeout: 90))
        XCTAssertEqual(Policy.next(afterAttempt: 3, outcome: .transportError, elapsed: 0, now: now, jitter: 0),
                       .stop(.attemptsExhausted))
    }

    func testJitterIsClampedAndNonFiniteJitterIsIgnored() {
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 0, now: now, jitter: 7),
                       .retry(after: 1, timeout: 90))
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 0, now: now, jitter: -3),
                       .retry(after: 0.5, timeout: 90))
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 0, now: now, jitter: .nan),
                       .retry(after: 0.5, timeout: 90))
    }

    func testRetryAfterSecondsAndHTTPDateAreHonoured() {
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .httpStatus(429, retryAfter: "7"), elapsed: 0, now: now, jitter: 0),
                       .retry(after: 7, timeout: 90))
        let date = "Fri, 15 Jan 2027 08:00:05 GMT"
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT"); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let reference = formatter.date(from: date)!.addingTimeInterval(-4)
        XCTAssertEqual(Policy.retryAfter(date, now: reference), 4)
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .httpStatus(503, retryAfter: date), elapsed: 0, now: reference, jitter: 0),
                       .retry(after: 4, timeout: 90))
        // A shorter Retry-After never shortens the backoff; a past date or unreadable text is ignored.
        XCTAssertEqual(Policy.next(afterAttempt: 2, outcome: .httpStatus(503, retryAfter: "0"), elapsed: 0, now: now, jitter: 1),
                       .retry(after: 2, timeout: 90))
        XCTAssertEqual(Policy.retryAfter("Thu, 01 Jan 1970 00:00:00 GMT", now: now), 0)
        XCTAssertNil(Policy.retryAfter("soon", now: now))
        XCTAssertNil(Policy.retryAfter("-5", now: now))
        XCTAssertNil(Policy.retryAfter(nil, now: now))
    }

    func testAWaitLongerThanTheCapIsNotMade() {
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .httpStatus(429, retryAfter: "11"), elapsed: 0, now: now, jitter: 0),
                       .stop(.waitTooLong))
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .httpStatus(429, retryAfter: "10"), elapsed: 0, now: now, jitter: 0),
                       .retry(after: 10, timeout: 90))
    }

    func testWholeCallDeadlineBoundsTheNextAttempt() {
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 90, now: now, jitter: 1),
                       .retry(after: 1, timeout: 29))
        XCTAssertEqual(Policy.next(afterAttempt: 2, outcome: .timedOut, elapsed: 118, now: now, jitter: 1),
                       .stop(.deadline))
        XCTAssertEqual(Policy.attemptTimeout(elapsed: 0), 90)
        // No attempt is started with less than the minimum attempt time left.
        XCTAssertEqual(Policy.minimumAttemptTime, 15)
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 104, now: now, jitter: 1),
                       .retry(after: 1, timeout: 15))
        XCTAssertEqual(Policy.next(afterAttempt: 1, outcome: .timedOut, elapsed: 104.5, now: now, jitter: 1),
                       .stop(.deadline))
        XCTAssertEqual(Policy.attemptTimeout(elapsed: 200), 0)
    }

    func testSelectionFailureMappingIsTypedAndOnlyRequestRejectionCannotBeLookedUpAgain() {
        let cases: [(any Error, FoodProposalSelectionFailure)] = [
            (FoodWebDiscoveryError.connectionFailed, .transport), (FoodWebDiscoveryError.timedOut, .timedOut),
            (FoodWebDiscoveryError.quotaExceeded, .rateLimited), (FoodWebDiscoveryError.serviceUnavailable, .serverError),
            (FoodWebDiscoveryError.invalidResponse, .invalidResponse), (FoodWebDiscoveryError.requestRejected, .requestRejected),
            (FoodWebDiscoveryError.permissionDenied, .requestRejected), (FoodWebDiscoveryError.invalidQuery, .requestRejected),
            (GenericFoodProposalError.invalidSelection, .choiceNotOffered),
            (GenericFoodProposalError.invalidSchema, .invalidResponse), (URLError(.badURL), .invalidResponse)]
        for (error, expected) in cases { XCTAssertEqual(FoodProposalSelectionFailure(error), expected, "\(error)") }
        XCTAssertEqual(FoodProposalSelectionFailure.allCases.filter { !$0.canLookUpAgain }, [.requestRejected])
        XCTAssertEqual(FoodProposalSelectionFailure.allCases.map(\.rawValue),
                       ["transport", "timed_out", "rate_limited", "server_error", "invalid_response", "choice_not_offered", "request_rejected"])
    }
}
