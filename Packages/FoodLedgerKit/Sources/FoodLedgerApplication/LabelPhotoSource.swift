import Foundation
import FoodLedgerDomain

public enum LabelPhotoSourceError: Error, Equatable, Sendable {
    case invalidManifest(String)
}

/// The one allow-listed model route (docs/label-photo-ai-prefill-v1.md P17, E6; 12.4): a closed
/// list, and a new route is a new route version, an E-line approval and a qualification run.
public enum LabelPhotoRoute {
    public struct Route: Equatable, Sendable {
        public let version: String
        public let model: String
        public let endpoint: String
    }

    /// Gemini 4 Argon on its zero-data-retention endpoint. The endpoint tag is the one the
    /// catalogue lists on the day (expected Google Vertex); L3 confirms it, and any other tag is
    /// a new admitted entry, never an edit.
    public static let v1 = Route(version: LabelPhotoManifest.routeVersion, model: "google/gemini-4-argon", endpoint: "google-vertex")
    public static let admitted: [Route] = [v1]
}

/// The ledger records a label photo manifest stands for, and their verification (8.1 and 8.2).
///
/// One derivation, shared with the pasted route: the stored manifest is projected onto the
/// pasted manifest's shape (in memory only, never stored) and the pasted rules derive the stored
/// basis, nutrients, corrections and servings from it, so the photo route calls them instead of
/// copying them (invariant 6). Only the source identity of each value differs. Verification
/// reads the stored manifest and never re-runs the mapping, the gate or the checks (17.1).
public enum LabelPhotoSource {
    public static let sourceID = "label-photo-ai"
    public static let imageCaptureMethod = "Label photo prepared on device"
    public static let manifestCaptureMethod = "Label photo read by AI"
    public static let licence = "User-supplied label photo read by an AI model; no redistribution licence inferred."
    public static let attribution = "Label photo read by AI"
    /// The locator versions a stored manifest may name (append-only).
    public static let admittedLocatorVersions = ["label-photo-vision-locate-v3"]
    /// The one wire schema a v1 request may name (the reader's `LabelPhotoWire.schemaVersion`).
    public static let wireSchemaVersion = "label-photo-wire-schema-v1"
    /// The closed set of check names `checks_failed` may hold: `label-arithmetic-checks-v2` and the
    /// serving consistency check (`label-photo-serving-consistency-v1`).
    public static let checkNames: Set<String> = ["energy", "kj_kcal_ratio", "serving_scaling", "subrow_not_above_parent",
                                                 "bound_consistency", "net_weight", "basis_plausibility", "serving_consistency"]

    /// `<route>:<model>@<endpoint>:<instruction>:<mapping>:<gate>:<arithmetic>:<consistency>:<conversion>:<serving>:<locator>:<attention>`.
    public static func pipeline(_ manifest: LabelPhotoManifest) -> String {
        [manifest.routeVersion, manifest.request.model + "@" + manifest.request.endpoint, manifest.request.instructionVersion,
         manifest.mappingVersion, manifest.gateVersion, manifest.arithmeticVersion, manifest.consistencyVersion, manifest.conversionVersion,
         manifest.servingVersion, manifest.locations.locatorVersion, manifest.attentionVersion].joined(separator: ":")
    }

    /// Closed and append-only: the pipelines a `label-photo-ai-v1` manifest may name. Pinned by a test.
    public static let admittedPipelines: [String] = admittedLocatorVersions.flatMap { locator in
        LabelPhotoRoute.admitted.map { route in
            [route.version, route.model + "@" + route.endpoint, LabelPhotoManifest.instructionVersion, "label-photo-wire-mapping-v1",
             "label-capture-decline-gate-v2", "label-arithmetic-checks-v2", LabelPhotoManifest.consistencyVersion,
             "pasted-label-conversions-v1", LabelPhotoManifest.servingVersion, locator, LabelPhotoAttention.version].joined(separator: ":")
        }
    }

    public static func schemaVersion(_ manifest: LabelPhotoManifest) -> String { manifest.version + ":" + manifest.labelFormat }

    // MARK: Projection onto the pasted shape (17.1)

    /// The pasted manifest the shared rules read. The photo route has no pasted text; the
    /// serving rules of `pasted-label-serving-v3` apply through parser v3's version (P10). A value
    /// the user left unknown takes every cell of its nutrient in its column out of the projected
    /// candidate (leaving one of two repeated rows unknown never chooses the other), so the
    /// nutrient is stored unknown, and a conversion from those cells is dropped with them.
    static func projection(_ manifest: LabelPhotoManifest) -> PastedLabelEvidenceManifest {
        let leftUnknown = Set(manifest.attention.filter { $0.resolution == .leftUnknown }.map(\.item))
        let candidate = manifest.candidate
        let unknownInColumn = Set(candidate.cells.filter { leftUnknown.contains(LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID)) }
            .map { $0.nutrient + "@" + $0.headerID })
        let cells = candidate.cells.filter { !unknownInColumn.contains($0.nutrient + "@" + $0.headerID) }
        let kept = Set(cells.map { LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID) })
        let projected = PastedLabelManifest.Candidate(route: candidate.route, inputSHA256: candidate.inputSHA256, declined: candidate.declined,
            declineReasons: candidate.declineReasons, wouldMarkReady: candidate.wouldMarkReady, language: candidate.language,
            servingSize: leftUnknown.contains(PastedLabelManifest.Correction.servingSize) ? nil : candidate.servingSize,
            servingsPerPack: leftUnknown.contains(PastedLabelManifest.Correction.servingsPerPack) ? nil : candidate.servingsPerPack,
            headers: candidate.headers, cells: cells, warnings: candidate.warnings)
        let conversions = manifest.conversions.filter { kept.contains(LabelPhotoManifest.cellItem(rowID: $0.sourceRowID, headerID: $0.sourceHeaderID)) }
        return .v1(PastedLabelManifest(pastedText: "", pastedTextSHA256: manifest.image.sha256, parserVersion: PastedLabelSource.parserVersionV3,
            gateVersion: manifest.gateVersion, arithmeticVersion: manifest.arithmeticVersion, conversionVersion: manifest.conversionVersion,
            labelFormat: manifest.labelFormat, launchScope: manifest.launchScope, identityMapping: manifest.identityMapping,
            candidate: projected, storedHeaderID: manifest.storedHeaderID, conversions: conversions, flagsShown: manifest.flagsShown,
            corrections: manifest.corrections, warningsShown: manifest.warningsShown, name: manifest.name, brand: manifest.brand))
    }

    // MARK: Attention (17.5, M2)

    /// The attention set the stored locations, flags and failed checks yield under
    /// `label-photo-attention-v1`: every candidate cell and printed serving line has exactly one
    /// location record, and nothing else has one.
    public static func attention(_ manifest: LabelPhotoManifest) throws -> LabelPhotoAttention.Findings {
        var byItem: [String: LabelPhotoManifest.Location] = [:]
        for record in manifest.locations.records {
            guard byItem.updateValue(record, forKey: record.item) == nil else { throw LabelPhotoSourceError.invalidManifest("location twice") }
            // A found value has a region inside the unit square; the others have none (8.2.6).
            switch (record.status, record.region) {
            case (.found, let region?) where region.isInsideUnitSquare: break
            case (.notFound, nil), (.ambiguous, nil): break
            default: throw LabelPhotoSourceError.invalidManifest("region")
            }
        }
        let candidate = manifest.candidate
        var expected = candidate.cells.map { LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID) }
        if candidate.servingSize != nil { expected.append(PastedLabelManifest.Correction.servingSize) }
        if candidate.servingsPerPack != nil { expected.append(PastedLabelManifest.Correction.servingsPerPack) }
        guard Set(expected).count == expected.count, Set(expected) == Set(byItem.keys) else {
            throw LabelPhotoSourceError.invalidManifest("locations")
        }
        let cells = candidate.cells.map { cell -> LabelPhotoAttention.Cell in
            let item = LabelPhotoManifest.cellItem(rowID: cell.rowID, headerID: cell.headerID)
            return LabelPhotoAttention.Cell(id: item, nutrient: cell.nutrient, basis: cell.basis, known: true, location: byItem[item]!.status)
        }
        let lines = [PastedLabelManifest.Correction.servingSize, PastedLabelManifest.Correction.servingsPerPack].compactMap { id in
            byItem[id].map { LabelPhotoAttention.ServingLine(id: id, location: $0.status) }
        }
        let flagged = Set(manifest.flagsShown.compactMap { LabelReading.Flag(code: $0.code, concerns: $0.concerns).nutrient })
        let failed = manifest.checksFailed.map { LabelPhotoAttention.FailedCheck(name: $0.name, basis: $0.basis, nutrient: $0.nutrient, child: $0.child) }
        return LabelPhotoAttention.items(cells: cells, servingLines: lines, gateFlaggedNutrients: flagged, failedChecks: failed)
    }

    /// The stored attention records equal the recomputed set exactly, each resolved, and every
    /// resolution agrees with the corrections (8.2.5).
    static func checkAttention(_ manifest: LabelPhotoManifest, evidence: CaptureEvidence) throws {
        guard manifest.checksFailed.allSatisfy({ checkNames.contains($0.name) }) else {
            throw LabelPhotoSourceError.invalidManifest("check name")
        }
        let findings = try attention(manifest)
        guard manifest.attention.map(\.item) == findings.items.map(\.id),
              manifest.attention.map(\.reasons) == findings.items.map(\.reasons),
              manifest.warningsShown == manifest.checksFailed.map(\.warningCode) else {
            throw LabelPhotoSourceError.invalidManifest("attention")
        }
        let captured = PastedLabelBasisChoice.milliseconds(evidence.capturedAt)
        let cellsByItem = Dictionary(uniqueKeysWithValues: manifest.candidate.cells.map {
            (LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID), $0)
        })
        for record in manifest.attention {
            // Resolved after the answer arrived and no later than the capture.
            guard manifest.response.completedAt <= record.at, record.at <= captured else {
                throw LabelPhotoSourceError.invalidManifest("attention time")
            }
            let line = record.item == PastedLabelManifest.Correction.servingSize || record.item == PastedLabelManifest.Correction.servingsPerPack
            let matching = manifest.corrections.filter { correction in
                if line { return correction.nutrient == record.item }
                guard let cell = cellsByItem[record.item] else { return false }
                return correction.rowID == cell.rowID && correction.headerID == cell.headerID
            }
            switch record.resolution {
            case .checked, .leftUnknown:
                guard matching.isEmpty else { throw LabelPhotoSourceError.invalidManifest("resolution without correction") }
            case .corrected:
                guard matching.count == 1, matching[0].kind == .corrected else { throw LabelPhotoSourceError.invalidManifest("corrected") }
            case .entered:
                guard line, matching.count == 1, matching[0].kind == .entered else { throw LabelPhotoSourceError.invalidManifest("entered") }
            }
        }
    }

    /// A value left unknown stays unknown (8.2.5): no correction or entry may supply its nutrient
    /// in its column, whatever row it names, and no conversion may calculate it. Checked on the
    /// stored, unprojected manifest, before the projection drops the cell.
    static func checkLeftUnknown(_ manifest: LabelPhotoManifest) throws {
        let cells = Dictionary(uniqueKeysWithValues: manifest.candidate.cells.map {
            (LabelPhotoManifest.cellItem(rowID: $0.rowID, headerID: $0.headerID), $0)
        })
        for record in manifest.attention where record.resolution == .leftUnknown {
            if let cell = cells[record.item] {
                // No conversion may start from any cell of the left-unknown nutrient in its column.
                let fromLeftUnknown = manifest.conversions.contains { conversion in
                    conversion.sourceHeaderID == cell.headerID
                        && cells[LabelPhotoManifest.cellItem(rowID: conversion.sourceRowID, headerID: conversion.sourceHeaderID)]?.nutrient == cell.nutrient
                }
                guard !manifest.corrections.contains(where: { $0.nutrient == cell.nutrient && $0.headerID == cell.headerID }),
                      !manifest.conversions.contains(where: { $0.nutrient == cell.nutrient && $0.sourceHeaderID == cell.headerID }),
                      !fromLeftUnknown else {
                    throw LabelPhotoSourceError.invalidManifest("left unknown supplied")
                }
            } else {
                guard !manifest.corrections.contains(where: { $0.nutrient == record.item }) else {
                    throw LabelPhotoSourceError.invalidManifest("left unknown line supplied")
                }
            }
        }
    }

    // MARK: Building

    /// The confirmation input for a manifest the user is logging: the image evidence (bound to
    /// the prepared bytes' attachment), the manifest evidence (its canonical bytes, encoded once),
    /// the release and the candidate. Nothing is committed here (17.3).
    public static func confirmation(manifest: LabelPhotoManifest, imageEvidenceID: EvidenceID, manifestEvidenceID: EvidenceID,
                                    attachment: AttachmentDescriptor?, capturedAt: Date, locale: LedgerText,
                                    encoder: any CanonicalEncoding, digester: any Digesting,
                                    conversions: (any PastedLabelConversionChecking)?) throws -> PopulatedFoodConfirmation {
        let manifestData = try encoder.encode(manifest)
        guard isCanonical(manifestData, encoder: encoder) else { throw LabelPhotoSourceError.invalidManifest("canonical bytes") }
        let manifestHash = try digester.sha256(manifestData)
        let imageHash = try SHA256Digest(manifest.image.sha256)
        let image = try CaptureEvidence(evidenceID: imageEvidenceID, kind: .packageImage, capturedAt: capturedAt, locale: locale,
            captureMethod: LedgerText(imageCaptureMethod), captureMethodVersion: LedgerText(manifest.image.preparationVersion),
            originalPayload: .descriptor(LedgerText(manifest.image.mediaType)), byteHash: imageHash, attachment: attachment)
        let evidence = try CaptureEvidence(evidenceID: manifestEvidenceID, kind: .packageImage, capturedAt: capturedAt, locale: locale,
            captureMethod: LedgerText(manifestCaptureMethod), captureMethodVersion: LedgerText(manifest.version),
            originalPayload: .text(LedgerText(String(decoding: manifestData, as: UTF8.self))), byteHash: manifestHash)
        let release = try SourceRelease(sourceReleaseID: ExternalIdentifier(sourceID + ":" + manifestHash.value),
            sourceID: ExternalIdentifier(sourceID), releasedAt: capturedAt, artifactHash: imageHash,
            schemaVersion: LedgerText(schemaVersion(manifest)), pipelineVersion: LedgerText(pipeline(manifest)),
            licence: LedgerText(licence), attribution: LedgerText(attribution), manifestHash: manifestHash)
        let candidate = try expectedCandidate(manifest: manifest, release: release, evidence: evidence, image: image,
                                              digester: digester, conversions: conversions)
        return try PopulatedFoodConfirmation(evidence: [evidence, image], sourceReleases: [release], candidates: [candidate],
            expectedIdentity: candidate.candidate.identity, expectedEdibleQuantity: candidate.candidate.edibleQuantity)
    }

    // MARK: Verification (8.2)

    /// Save and reopen verification against the stored manifest.
    public static func verify(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate, encoder: any CanonicalEncoding,
                              digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) -> Bool {
        let source = candidate.candidate
        guard let release = input.sourceReleases.first(where: { $0.sourceReleaseID == source.sourceReleaseID }),
              release.sourceID.value == sourceID, source.evidenceIDs.count == 2,
              let evidence = input.evidence.first(where: { $0.evidenceID == source.evidenceIDs[0] }),
              let image = input.evidence.first(where: { $0.evidenceID == source.evidenceIDs[1] }),
              evidence.kind == .packageImage, evidence.captureMethod.value == manifestCaptureMethod,
              evidence.captureMethodVersion.value == LabelPhotoManifest.version, evidence.attachment == nil,
              case let .text(payload) = evidence.originalPayload else { return false }
        let data = Data(payload.value.utf8)
        guard let hash = try? digester.sha256(data), evidence.byteHash == hash, release.manifestHash == hash,
              isCanonical(data, encoder: encoder), let manifest = LabelPhotoManifest.decode(data),
              let expected = try? expectedCandidate(manifest: manifest, release: release, evidence: evidence, image: image,
                                                    digester: digester, conversions: conversions) else { return false }
        return expected == candidate
    }

    /// Canonical bytes only: a strict manifest that re-encodes to exactly itself.
    public static func isCanonical(_ data: Data, encoder: any CanonicalEncoding) -> Bool {
        guard let manifest = LabelPhotoManifest.decode(data), let encoded = try? encoder.encode(manifest) else { return false }
        return encoded == data
    }

    /// The candidate a manifest yields, after checking the release, evidence and image it is bound to.
    static func expectedCandidate(manifest: LabelPhotoManifest, release: SourceRelease, evidence: CaptureEvidence, image: CaptureEvidence,
                                  digester: any Digesting, conversions: (any PastedLabelConversionChecking)?) throws -> PopulatedFoodCandidate {
        let hash = release.manifestHash
        let wire = Data(manifest.response.wireText.utf8)
        guard release.sourceID.value == sourceID, release.sourceReleaseID.value == sourceID + ":" + hash.value,
              release.schemaVersion.value == schemaVersion(manifest),
              admittedPipelines.contains(pipeline(manifest)), release.pipelineVersion.value == pipeline(manifest),
              release.licence.value == licence, release.attribution.value == attribution, release.releasedAt == evidence.capturedAt,
              release.artifactHash.value == manifest.image.sha256,
              manifest.labelFormat == LabelPhotoReading.labelFormat, manifest.launchScope == LabelPhotoReading.launchScope,
              manifest.servingVersion == LabelPhotoManifest.servingVersion, manifest.attentionVersion == LabelPhotoAttention.version,
              manifest.consistencyVersion == LabelPhotoManifest.consistencyVersion,
              manifest.candidate.route == "C", manifest.candidate.inputSHA256 == manifest.image.sha256, !manifest.candidate.declined,
              wire.count <= LabelPhotoManifest.maximumWireBytes, (try digester.sha256(wire)).value == manifest.response.wireSHA256,
              manifest.response.attempts >= 1, manifest.response.completedAt >= manifest.response.requestedAt,
              manifest.request.model == manifest.request.catalogueCheck.slug,
              manifest.request.wireSchemaVersion == wireSchemaVersion, manifest.image.mediaType == LabelPhotoManifest.mediaType,
              manifest.request.endpoint == manifest.request.catalogueCheck.endpoint else {
            throw LabelPhotoSourceError.invalidManifest("release")
        }
        // The image evidence: the prepared bytes, described and hashed; its attachment, when the
        // photo is on this device, holds exactly those bytes (8.2.7).
        guard image.kind == .packageImage, image.captureMethod.value == imageCaptureMethod,
              image.captureMethodVersion.value == manifest.image.preparationVersion,
              image.captureMethodVersion.value == LabelPhotoManifest.preparationVersion, image.capturedAt == evidence.capturedAt,
              image.originalPayload == .descriptor(try LedgerText(LabelPhotoManifest.mediaType)),
              image.byteHash?.value == manifest.image.sha256,
              image.attachment.map({ $0.sha256.value == manifest.image.sha256 && $0.byteCount == manifest.image.byteCount
                  && $0.mediaKind.value == LabelPhotoManifest.mediaType }) ?? true else {
            throw LabelPhotoSourceError.invalidManifest("image")
        }
        guard admittedLocatorVersions.contains(manifest.locations.locatorVersion) else { throw LabelPhotoSourceError.invalidManifest("locator") }
        try checkAttention(manifest, evidence: evidence)
        try checkLeftUnknown(manifest)
        let projected = projection(manifest)
        let basis = try storedBasis(projected)
        guard manifest.identityMapping.isCoherent(servingBasis: basis) else { throw LabelPhotoSourceError.invalidManifest("identity") }
        let pasted = try PastedLabelSource.expectedNutrients(manifest: projected, basis: basis, hash: hash, release: release,
                                                             evidence: evidence, conversions: conversions)
        let nutrients = try relabel(pasted)
        let neutral = try ProviderNeutralCandidate(sourceReleaseID: release.sourceReleaseID,
            recordID: ExternalIdentifier(sourceID + ":" + hash.value + "#header=" + manifest.storedHeaderID),
            identity: manifest.identityMapping.identity, edibleQuantity: try PastedLabelSource.edibleQuantity(basis), nutrients: nutrients,
            evidenceIDs: [evidence.evidenceID, image.evidenceID])
        return try PopulatedFoodCandidate(candidate: neutral, name: LedgerText(manifest.name),
            brand: manifest.brand.map { try LedgerText($0) }, itemClass: manifest.identityMapping.itemClass)
    }

    /// The stored column's basis by the pasted rule, which reads the projection.
    static func storedBasis(_ projected: PastedLabelEvidenceManifest) throws -> ResolutionBasis {
        do { return try PastedLabelSource.storedBasis(projected) } catch { throw LabelPhotoSourceError.invalidManifest("stored column") }
    }

    /// The pasted derivation names the pasted source; each value names this source instead, with
    /// everything else unchanged.
    static func relabel(_ set: NutrientSet) throws -> NutrientSet {
        try set.relabelling(sourceID: ExternalIdentifier(sourceID))
    }

    /// On reopen the saved product may carry the user's later name or class corrections; the
    /// immutable source candidate keeps the manifest's name, brand and class.
    public static func restoredSourceCandidate(_ input: PopulatedFoodConfirmation,
                                               candidate: PopulatedFoodCandidate) throws -> PopulatedFoodCandidate {
        let source = candidate.candidate
        guard source.evidenceIDs.count == 2, let evidence = input.evidence.first(where: { $0.evidenceID == source.evidenceIDs[0] }),
              case let .text(payload) = evidence.originalPayload, let manifest = LabelPhotoManifest.decode(Data(payload.value.utf8)) else {
            throw LabelPhotoSourceError.invalidManifest("evidence")
        }
        return try PopulatedFoodCandidate(candidate: source, name: LedgerText(manifest.name),
            brand: manifest.brand.map { try LedgerText($0) }, itemClass: manifest.identityMapping.itemClass)
    }

    /// Whether the input carries photo evidence (either record of the route). The route's two
    /// capture-method versions are this route's own, never a pasted one.
    public static func hasPhotoEvidence(_ input: PopulatedFoodConfirmation, candidate: PopulatedFoodCandidate) -> Bool {
        input.evidence.contains { candidate.candidate.evidenceIDs.contains($0.evidenceID)
            && ($0.captureMethodVersion.value == LabelPhotoManifest.version || $0.captureMethodVersion.value == LabelPhotoManifest.preparationVersion) }
    }
}
