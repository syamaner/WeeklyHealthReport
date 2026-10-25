import Foundation

/// One Read label with AI tap, end to end (docs/label-photo-ai-prefill-v1.md sections 3, 6, 7.2
/// and 9): the session's read of the prepared image, the reading of the answer, the on-device
/// locator, and Confirm's review. Pure orchestration over ports. The image was prepared before the
/// tap (`prepare`), so the bytes shown on the Label photo screen are exactly the bytes sent.
public struct LabelPhotoReadFlow: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// A usable reading, ready for Confirm.
        case review(LabelPhotoReview)
        /// The model or the frozen rules declined: the codes, shown with the photo kept (7.2).
        case declined([String])
        /// Nothing to show (7.2).
        case failed(LabelImageReadingFailure)
    }

    let preparer: any LabelImagePreparing
    public let session: LabelPhotoReadSession
    let interpreter: any LabelPhotoInterpreting
    let locator: any LabelValueLocating
    let builder: LabelPhotoConfirmation

    public init(preparer: any LabelImagePreparing, session: LabelPhotoReadSession, interpreter: any LabelPhotoInterpreting,
                locator: any LabelValueLocating, builder: LabelPhotoConfirmation) {
        self.preparer = preparer; self.session = session; self.interpreter = interpreter; self.locator = locator; self.builder = builder
    }

    /// The crop as it will be sent, or why it cannot be (7.2 crop too small, photo too large).
    public func prepare(_ source: Data, crop: LabelCropRect) -> Result<PreparedLabelImage, LabelImagePreparationError> {
        do { return .success(try preparer.prepare(source, crop: crop)) } catch let error as LabelImagePreparationError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }
    }

    public func todayReads() async -> Int? { await session.todayReads() }

    public func read(_ image: PreparedLabelImage, progress: (@Sendable (Int) -> Void)? = nil) async -> Outcome {
        switch await session.read(image, progress: progress) {
        case let .failed(failure):
            return .failed(failure)
        case let .answered(reply, request):
            guard let reading = interpreter.reading(wireText: reply.wireText, imageSHA256: image.sha256) else {
                return .failed(.unreadableAnswer)
            }
            let declines = reading.hardDeclines
            guard declines.isEmpty, reading.isUsable else { return .declined(declines.isEmpty ? ["unreadable_table"] : declines) }
            if Task.isCancelled { return .failed(.cancelled) }
            // The locator never fails open: an error is a failed read, never values marked found.
            guard let locations = try? await locator.locate(image, candidate: reading.candidate),
                  let review = try? builder.review(reading: reading, image: image, reply: reply, request: request, locations: locations) else {
                return .failed(.failed)
            }
            return .review(review)
        }
    }
}
