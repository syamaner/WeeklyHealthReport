/// Transient authority for one request. Never persisted, displayed, encoded or logged.
public struct FoodWebRequestCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let key: String
    public let generation: Int
    public init(key: String, generation: Int) { self.key = key; self.generation = generation }
    public var description: String { "[Validated food-search credential]" }
    public var debugDescription: String { description }
}

@MainActor
public protocol FoodWebCredentialAuthorizing: AnyObject, Sendable {
    func credentialForRequest() throws -> FoodWebRequestCredential
    func isCurrent(_ credential: FoodWebRequestCredential) -> Bool
    func reject(_ credential: FoodWebRequestCredential)
}
