import Foundation
import FoodLedgerApplication
import FoodLedgerDomain

/// A synthetic label photo entry (docs/label-photo-ai-prefill-v1.md 8.1): the pasted fixture's
/// table, read by route C from a prepared image. Nothing here was read from a photo or a model.
enum LabelPhotoFixtures {
    typealias M = LabelPhotoManifest
    static let imageBytes = Data("synthetic prepared label photo bytes, never a real photo".utf8)
    static let wireText = #"{"declined":false,"decline_reasons":[],"language":"zh-Hant","serving_size_text":"每一份量30公克","servings_per_pack_text":"本包裝含10份","headers":[],"rows":[]}"#
    static let capturedAt = Date(timeIntervalSince1970: 1_700_001_000)
    static let hex64 = String(repeating: "ab", count: 32)

    static func sha(_ data: Data) throws -> String { try LedgerFixtures.digester.sha256(data).value }
    static func imageSHA() throws -> String { try sha(imageBytes) }

    static func candidate() throws -> PastedLabelManifest.Candidate {
        let pasted = try PastedLabelFixtures.candidate()
        return PastedLabelManifest.Candidate(route: "C", inputSHA256: try imageSHA(), declined: false, declineReasons: [],
            wouldMarkReady: pasted.wouldMarkReady, language: pasted.language, servingSize: pasted.servingSize,
            servingsPerPack: pasted.servingsPerPack, headers: pasted.headers, cells: pasted.cells, warnings: [])
    }

    static let region = M.Region(x: "0.1", y: "0.2", w: "0.05", h: "0.03")

    /// Every cell found except protein per 100 g (not found); the servings-per-pack line ambiguous.
    static func locations(_ candidate: PastedLabelManifest.Candidate,
                          overriding: [String: LabelPhotoAttention.Location] = [:]) -> M.Locations {
        var items = candidate.cells.map { M.cellItem(rowID: $0.rowID, headerID: $0.headerID) }
        items += ["serving_size", "servings_per_pack"]
        let defaults: [String: LabelPhotoAttention.Location] = ["蛋白質@h2": .notFound, "servings_per_pack": .ambiguous]
        let records = items.map { item -> M.Location in
            let status = overriding[item] ?? defaults[item] ?? .found
            return M.Location(item: item, status: status, region: status == .found ? region : nil)
        }
        return M.Locations(locatorVersion: "label-photo-vision-locate-v3", visionRevision: 3, languages: ["zh-Hant", "en-US"], records: records)
    }

    static func request() -> M.Request {
        M.Request(model: "google/gemini-4-argon", endpoint: "google-vertex", reasoningLimit: 500, maxOutputTokens: 1_200,
                  instructionVersion: M.instructionVersion, instructionSHA256: hex64, wireSchemaVersion: "label-photo-wire-schema-v1",
                  wireSchemaSHA256: hex64,
                  catalogueCheck: .init(at: 1_700_000_500_000, slug: "google/gemini-4-argon", endpoint: "google-vertex",
                                        inputModalities: ["text", "image"], zeroDataRetention: true, promptPrice: "0.000002",
                                        completionPrice: "0.00001"))
    }

    static func response(wire: String = wireText, cost: String = "0.0105") throws -> M.Response {
        M.Response(model: "google/gemini-4-argon", provider: "Google", generationID: "gen-synthetic-0001", finishReason: "stop", attempts: 1,
                   usage: .init(promptTokens: 2_100, completionTokens: 640, reasoningTokens: nil, costUSD: cost),
                   requestedAt: 1_700_000_600_000, completedAt: 1_700_000_610_000, wireText: wire, wireSHA256: try sha(Data(wire.utf8)))
    }

    /// The manifest with its attention computed from its own locations and resolved: protein per
    /// 100 g corrected (the pasted fixture's correction), everything else checked.
    static func manifest(candidate: PastedLabelManifest.Candidate? = nil, locations: M.Locations? = nil,
                         corrections: [PastedLabelManifest.Correction] = PastedLabelFixtures.corrections,
                         resolutions: [String: LabelPhotoAttention.Resolution] = ["蛋白質@h2": .corrected],
                         attention: [M.Attention]? = nil, response: M.Response? = nil, request: M.Request? = nil,
                         flags: [PastedLabelManifest.Flag] = [.init(code: "required_row_missing", concerns: "fibre")],
                         checksFailed: [M.FailedCheck] = []) throws -> M {
        let candidate = try candidate ?? self.candidate()
        let locations = locations ?? self.locations(candidate)
        func build(_ attention: [M.Attention]) throws -> M {
            M(image: .init(sha256: try imageSHA(), byteCount: imageBytes.count, pixelWidth: 1_200, pixelHeight: 900, jpegQuality: "0.8"),
              request: request ?? self.request(), response: try response ?? self.response(), mappingVersion: "label-photo-wire-mapping-v1",
              gateVersion: "label-capture-decline-gate-v2", arithmeticVersion: "label-arithmetic-checks-v2",
              conversionVersion: "pasted-label-conversions-v1",
              identityMapping: try .init(fortificationAnswer: .no, servingBasis: .per100Grams), candidate: candidate, locations: locations,
              storedHeaderID: "h2", conversions: [PastedLabelFixtures.kcal, PastedLabelFixtures.sodium], flagsShown: flags,
              checksFailed: checksFailed, warningsShown: checksFailed.map(\.warningCode), corrections: corrections, attention: attention,
              name: "Synthetic oat crackers", brand: "Synthetic Mill")
        }
        if let attention { return try build(attention) }
        let findings = try LabelPhotoSource.attention(try build([]))
        return try build(findings.items.map { M.Attention(item: $0.id, reasons: $0.reasons, resolution: resolutions[$0.id] ?? .checked,
                                                          at: 1_700_000_900_000) })
    }

    static func attachment() throws -> AttachmentDescriptor {
        try AttachmentDescriptor(sha256: SHA256Digest(try imageSHA()), mediaKind: LedgerText("image/jpeg"), byteCount: imageBytes.count,
                                 relativePath: LedgerText("label-photos/synthetic.jpg"))
    }

    static func input(_ manifest: M, attachment: AttachmentDescriptor? = nil) throws -> PopulatedFoodConfirmation {
        try LabelPhotoSource.confirmation(manifest: manifest, imageEvidenceID: LedgerFixtures.id(9_201, EvidenceTag.self),
            manifestEvidenceID: LedgerFixtures.id(9_200, EvidenceTag.self), attachment: attachment, capturedAt: capturedAt,
            locale: LedgerText("zh_TW"), encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester,
            conversions: GoldenPastedLabelConversions())
    }

    static func verify(_ input: PopulatedFoodConfirmation) -> Bool {
        LabelPhotoSource.verify(input, candidate: input.candidates[0], encoder: LedgerFixtures.encoder, digester: LedgerFixtures.digester,
                                conversions: GoldenPastedLabelConversions())
    }

    /// The input with the manifest evidence's text replaced and every hash rebound to it, so only a
    /// content rule can refuse it.
    static func rebound(_ input: PopulatedFoodConfirmation, manifest: M) throws -> PopulatedFoodConfirmation {
        let data = try LedgerFixtures.encoder.encode(manifest)
        let hash = try LedgerFixtures.digester.sha256(data)
        let old = input.evidence[0], image = input.evidence[1], release = input.sourceReleases[0]
        let evidence = try CaptureEvidence(evidenceID: old.evidenceID, kind: old.kind, capturedAt: old.capturedAt, locale: old.locale,
            captureMethod: old.captureMethod, captureMethodVersion: old.captureMethodVersion,
            originalPayload: .text(LedgerText(String(decoding: data, as: UTF8.self))), byteHash: hash)
        let newRelease = try SourceRelease(sourceReleaseID: ExternalIdentifier("label-photo-ai:" + hash.value), sourceID: release.sourceID,
            releasedAt: release.releasedAt, artifactHash: release.artifactHash, schemaVersion: release.schemaVersion,
            pipelineVersion: LedgerText(LabelPhotoSource.pipeline(manifest)), licence: release.licence, attribution: release.attribution,
            manifestHash: hash)
        let source = input.candidates[0]
        let neutral = try ProviderNeutralCandidate(sourceReleaseID: newRelease.sourceReleaseID,
            recordID: ExternalIdentifier("label-photo-ai:" + hash.value + "#header=" + manifest.storedHeaderID),
            identity: source.candidate.identity, edibleQuantity: source.candidate.edibleQuantity,
            nutrients: try relink(source.candidate.nutrients, release: newRelease.sourceReleaseID, hash: hash),
            evidenceIDs: source.candidate.evidenceIDs)
        let candidate = try PopulatedFoodCandidate(candidate: neutral, name: source.name, brand: source.brand, itemClass: source.itemClass)
        return try PopulatedFoodConfirmation(evidence: [evidence, image], sourceReleases: [newRelease], candidates: [candidate],
            expectedIdentity: neutral.identity, expectedEdibleQuantity: neutral.edibleQuantity)
    }

    /// Values pointing at the new release and manifest hash, otherwise unchanged.
    static func relink(_ set: NutrientSet, release: ExternalIdentifier, hash: SHA256Digest) throws -> NutrientSet {
        func provenance(_ list: [NutrientProvenance]) -> [NutrientProvenance] {
            list.map { value in
                let reference = value.manifestReference.map { text -> String in
                    guard let range = text.value.range(of: ";") else { return text.value }
                    return "manifest-sha256=" + hash.value + String(text.value[range.lowerBound...])
                }
                return NutrientProvenance(sourceKind: value.sourceKind, sourceID: value.sourceID, sourceReleaseID: release,
                    recordID: value.recordID, evidenceID: value.evidenceID, capturedAt: value.capturedAt, responseHash: value.responseHash,
                    manifestReference: reference.flatMap { try? LedgerText($0) }, decisionID: value.decisionID,
                    assertionID: value.assertionID, transforms: value.transforms)
            }
        }
        func value(_ value: NutrientValue) throws -> NutrientValue {
            switch value {
            case let .measured(exact): .measured(try ExactNutrientValue(amount: exact.amount, unit: exact.unit, sourceValue: exact.sourceValue,
                                                                        provenance: provenance(exact.provenance)))
            case let .augmented(exact): .augmented(try ExactNutrientValue(amount: exact.amount, unit: exact.unit, sourceValue: exact.sourceValue,
                                                                          provenance: provenance(exact.provenance)))
            case let .bounded(b): .bounded(try NutrientBounds(lower: b.lower, upper: b.upper, lowerClosed: b.lowerClosed, upperClosed: b.upperClosed,
                                                              origin: b.origin, unit: b.unit, sourceValue: b.sourceValue,
                                                              provenance: provenance(b.provenance)))
            case .unknown: value
            }
        }
        return try NutrientSet(entries: set.entries.map { try NutrientEntry(key: $0.key, value: value($0.value), status: $0.status,
                                                                            conflictCandidates: $0.conflictCandidates.map(value)) })
    }
}
