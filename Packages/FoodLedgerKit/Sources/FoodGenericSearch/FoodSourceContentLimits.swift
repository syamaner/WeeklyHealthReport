/// Closed resource limits for independent source HTML and its much smaller table projection.
/// HTML often contains large script payloads; those are never executed or projected.
enum FoodSourceContentLimits {
    static let htmlBytes = 2_000_000
    static let projectionBytes = 500_000
}
