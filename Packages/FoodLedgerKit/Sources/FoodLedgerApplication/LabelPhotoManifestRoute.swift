import Foundation

/// The route version a label photo manifest records (docs/label-photo-ai-prefill-v1.md 17.21).
///
/// The manifest codec (`LabelPhotoManifest.swift`) is frozen, and its memberwise initialiser always
/// records route v1's version. Route v2 changes only `max_tokens`, so the builder records the
/// version of the admitted route that the request describes (model, endpoint and tokens) through
/// this copy. The codec, its keys and its bytes are unchanged; `route_version` was always data.
extension LabelPhotoManifest {
    /// This manifest, recording the version of the admitted route its request was sent under. A
    /// request that no admitted route describes keeps the recorded version, and then fails
    /// verification.
    public func recordingRoute() -> LabelPhotoManifest {
        LabelPhotoManifest(copying: self, routeVersion: LabelPhotoRoute.route(for: request)?.version ?? routeVersion)
    }

    init(copying m: LabelPhotoManifest, routeVersion: String) {
        version = m.version
        self.routeVersion = routeVersion
        image = m.image
        request = m.request
        response = m.response
        mappingVersion = m.mappingVersion
        gateVersion = m.gateVersion
        arithmeticVersion = m.arithmeticVersion
        conversionVersion = m.conversionVersion
        servingVersion = m.servingVersion
        labelFormat = m.labelFormat
        launchScope = m.launchScope
        identityMapping = m.identityMapping
        candidate = m.candidate
        locations = m.locations
        storedHeaderID = m.storedHeaderID
        basisChoices = m.basisChoices
        conversions = m.conversions
        flagsShown = m.flagsShown
        checksFailed = m.checksFailed
        warningsShown = m.warningsShown
        corrections = m.corrections
        attention = m.attention
        attentionVersion = m.attentionVersion
        consistencyVersion = m.consistencyVersion
        name = m.name
        brand = m.brand
    }
}
