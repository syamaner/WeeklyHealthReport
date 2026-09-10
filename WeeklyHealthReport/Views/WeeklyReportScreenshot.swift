import Foundation

struct WeeklyReportScreenshotSnapshot: Equatable {
    let period: ReportPeriod
    let steps: WeeklyReportViewModel.State
    let weight: WeeklyReportViewModel.WeightState
    let bodyFat: WeeklyReportViewModel.BodyFatState
    let waist: MetricState<WaistSummary>
    let glucose: MetricState<GlucoseSummary>
    let vo2Max: MetricState<VO2MaxSummary>
    let bloodOxygen: MetricState<BloodOxygenSummary>
    let bloodPressure: MetricState<BloodPressureSummary>
    let restingHeartRate: MetricState<HeartMetricTrendSummary>
    let hrv: MetricState<HeartMetricTrendSummary>
    let watchCoverage: MetricState<WatchCoverageSummary>
    let exercise: MetricState<Double>
    let activeEnergy: MetricState<Double>
    let workouts: MetricState<WorkoutSummary>
    let sleep: MetricState<SleepSummary>
    let medications: MetricState<MedicationSummary>
    let includesMedicationSection: Bool
    let showsMorningBloodPressureDetails: Bool
    let showsEveningBloodPressureDetails: Bool
}

struct WeeklyReportPDFDocument: Equatable {
    enum SectionID: String, CaseIterable {
        case steps
        case weight
        case bodyComposition
        case heart
        case bloodPressure
        case cardiorespiratory
        case glucose
        case activity
        case sleep
        case medications
    }

    enum RowStyle: Equatable {
        case standard
        case secondary
        case failure
        case note
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let label: String?
        let value: String
        let style: RowStyle

        init(
            _ id: String,
            label: String? = nil,
            value: String,
            style: RowStyle = .standard
        ) {
            self.id = id
            self.label = label
            self.value = value
            self.style = style
        }
    }

    struct Section: Equatable, Identifiable {
        let id: SectionID
        let title: String
        let rows: [Row]
        let footer: String?
    }

    let title: String
    let selection: String
    let period: String
    let sections: [Section]

    init(
        snapshot: WeeklyReportScreenshotSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        title = "Weekly Health Report"
        selection = snapshot.period.selection.rawValue
        period = snapshot.period.completedDays.isEmpty
            ? "No completed days"
            : HealthReportFormatter.period(
                snapshot.period,
                calendar: calendar,
                locale: locale
            )

        var result = [
            Self.stepsSection(snapshot.steps, locale: locale),
            Self.weightSection(snapshot.weight, calendar: calendar, locale: locale),
            Self.bodyCompositionSection(
                bodyFat: snapshot.bodyFat,
                waist: snapshot.waist,
                calendar: calendar,
                locale: locale
            ),
            Self.heartSection(
                restingHeartRate: snapshot.restingHeartRate,
                hrv: snapshot.hrv,
                watchCoverage: snapshot.watchCoverage,
                comparisonDayCount: snapshot.period.completedDays.count,
                locale: locale
            ),
            Self.bloodPressureSection(
                snapshot.bloodPressure,
                showsMorningDetails: snapshot.showsMorningBloodPressureDetails,
                showsEveningDetails: snapshot.showsEveningBloodPressureDetails,
                calendar: calendar,
                locale: locale
            ),
            Self.cardiorespiratorySection(
                vo2Max: snapshot.vo2Max,
                bloodOxygen: snapshot.bloodOxygen,
                calendar: calendar,
                locale: locale
            ),
            Self.glucoseSection(snapshot.glucose, locale: locale),
            Self.activitySection(
                activeEnergy: snapshot.activeEnergy,
                exercise: snapshot.exercise,
                workouts: snapshot.workouts,
                calendar: calendar,
                locale: locale
            ),
            Self.sleepSection(snapshot.sleep)
        ]

        if snapshot.includesMedicationSection {
            result.append(Self.medicationSection(
                snapshot.medications,
                calendar: calendar,
                locale: locale
            ))
        }
        sections = result
    }

    var searchableText: String {
        ([title, selection, period] + sections.flatMap { section in
            [section.title] + section.rows.flatMap { row in
                [row.label, row.value].compactMap { $0 }
            } + [section.footer].compactMap { $0 }
        }).joined(separator: "\n")
    }

    private static func stepsSection(
        _ state: WeeklyReportViewModel.State,
        locale: Locale
    ) -> Section {
        let rows: [Row]
        switch state {
        case .idle, .loading:
            rows = [Row("steps-loading", value: "Reading Apple Health…", style: .secondary)]
        case .loaded(let summary):
            rows = [
                Row(
                    "steps-average",
                    label: "Average Daily Steps",
                    value: HealthReportFormatter.integer(summary.averageDailySteps, locale: locale)
                ),
                Row(
                    "steps-total",
                    label: "Weekly Total",
                    value: HealthReportFormatter.integer(summary.totalSteps, locale: locale)
                )
            ]
        case .noCompletedDays:
            rows = [Row(
                "steps-no-completed-days",
                value: "There are no completed days in this period yet.",
                style: .secondary
            )]
        case .noDataOrAccess:
            rows = [Row(
                "steps-no-data",
                value: "No step data is visible, or Health access was not granted.",
                style: .secondary
            )]
        case .healthUnavailable:
            rows = [Row(
                "steps-unavailable",
                value: "Health data is unavailable on this device.",
                style: .secondary
            )]
        case .failed(let message):
            rows = [Row(
                "steps-failed",
                value: "Step query failed: \(message)",
                style: .failure
            )]
        }
        return Section(id: .steps, title: "Steps", rows: rows, footer: nil)
    }

    private static func weightSection(
        _ state: WeeklyReportViewModel.WeightState,
        calendar: Calendar,
        locale: Locale
    ) -> Section {
        let rows: [Row]
        switch state {
        case .idle, .loading:
            rows = [Row("weight-loading", value: "Reading latest weight…", style: .secondary)]
        case .available(let summary):
            rows = [
                Row(
                    "weight-latest",
                    label: "Latest Weight",
                    value: HealthReportFormatter.weightKilograms(
                        summary.latest.kilograms,
                        locale: locale
                    )
                ),
                Row(
                    "weight-measured",
                    label: "Measured",
                    value: HealthReportFormatter.dateAndTime(
                        summary.latest.date,
                        calendar: calendar,
                        locale: locale
                    )
                ),
                Row(
                    "weight-average",
                    label: "7-day Average",
                    value: summary.currentSevenDayAverage.map {
                        HealthReportFormatter.weightKilograms($0, locale: locale)
                    } ?? "Insufficient history",
                    style: summary.currentSevenDayAverage == nil ? .secondary : .standard
                ),
                Row(
                    "weight-trend",
                    label: "Weight Trend",
                    value: summary.trendKilograms.map {
                        HealthReportFormatter.signedChange(
                            $0,
                            unit: "kg",
                            comparison: "previous 7d",
                            locale: locale
                        )
                    } ?? "Insufficient history",
                    style: summary.trendKilograms == nil ? .secondary : .standard
                )
            ]
        case .noDataOrAccess:
            rows = [Row(
                "weight-no-data",
                value: "No weight data is visible, or Health access was not granted.",
                style: .secondary
            )]
        case .healthUnavailable:
            rows = [Row(
                "weight-unavailable",
                value: "Health data is unavailable on this device.",
                style: .secondary
            )]
        case .failed(let message):
            rows = [Row(
                "weight-failed",
                value: "Weight query failed: \(message)",
                style: .failure
            )]
        }
        return Section(id: .weight, title: "Weight", rows: rows, footer: nil)
    }

    private static func bodyCompositionSection(
        bodyFat: WeeklyReportViewModel.BodyFatState,
        waist: MetricState<WaistSummary>,
        calendar: Calendar,
        locale: Locale
    ) -> Section {
        var rows: [Row]
        switch bodyFat {
        case .idle, .loading:
            rows = [Row(
                "body-fat-loading",
                value: "Reading body-fat history…",
                style: .secondary
            )]
        case .available(let summary):
            rows = [Row(
                "body-fat-latest",
                label: "Body Fat",
                value: "\(HealthReportFormatter.percentage(summary.latest.percentage, locale: locale)) latest"
            )]
            if let average = summary.sevenDayAverage {
                rows.append(Row(
                    "body-fat-seven-day",
                    label: "7-day Average",
                    value: HealthReportFormatter.percentage(average, locale: locale)
                ))
            }
            rows.append(Row(
                "body-fat-28-day",
                label: "28-day Average",
                value: summary.current28DayAverage.map {
                    HealthReportFormatter.percentage($0, locale: locale)
                } ?? "Insufficient history",
                style: summary.current28DayAverage == nil ? .secondary : .standard
            ))
            rows.append(Row(
                "body-fat-trend",
                label: "Body Fat Trend",
                value: summary.trendPercentagePoints.map {
                    HealthReportFormatter.percentagePointTrend($0, locale: locale)
                } ?? "Insufficient history",
                style: summary.trendPercentagePoints == nil ? .secondary : .standard
            ))
        case .noDataOrAccess:
            rows = [Row(
                "body-fat-no-data",
                value: "No body-fat data is visible, or Health access was not granted.",
                style: .secondary
            )]
        case .healthUnavailable:
            rows = [Row(
                "body-fat-unavailable",
                value: "Health data is unavailable on this device.",
                style: .secondary
            )]
        case .failed(let message):
            rows = [Row(
                "body-fat-failed",
                value: "Body-fat query failed: \(message)",
                style: .failure
            )]
        }

        rows.append(metricRow(
            id: "waist",
            label: "Waist Circumference",
            state: waist,
            format: { HealthReportFormatter.waistCentimetres($0.latest.centimetres, locale: locale) }
        ))
        if case .available(let summary) = waist {
            rows.append(Row(
                "waist-measured",
                label: "Waist Measured",
                value: HealthReportFormatter.dateAndTime(
                    summary.latest.date,
                    calendar: calendar,
                    locale: locale
                )
            ))
            rows.append(Row(
                "waist-trend",
                label: "4-week Waist Trend",
                value: summary.fourWeekChangeCentimetres.map {
                    HealthReportFormatter.signedChange(
                        $0,
                        unit: "cm",
                        comparison: "~4 weeks earlier",
                        locale: locale
                    )
                } ?? "Insufficient history",
                style: summary.fourWeekChangeCentimetres == nil ? .secondary : .standard
            ))
        }
        return Section(
            id: .bodyComposition,
            title: "Body Composition",
            rows: rows,
            footer: nil
        )
    }

    private static func heartSection(
        restingHeartRate: MetricState<HeartMetricTrendSummary>,
        hrv: MetricState<HeartMetricTrendSummary>,
        watchCoverage: MetricState<WatchCoverageSummary>,
        comparisonDayCount: Int,
        locale: Locale
    ) -> Section {
        let comparison = "previous \(comparisonDayCount)d"
        return Section(
            id: .heart,
            title: "Heart",
            rows: [
                metricRow(
                    id: "resting-heart-rate-average",
                    label: "Resting HR Average",
                    state: restingHeartRate,
                    format: { HealthReportFormatter.heartRate($0.current.average, locale: locale) }
                ),
                trendRow(
                    id: "resting-heart-rate-trend",
                    label: "Resting HR Trend",
                    state: restingHeartRate,
                    unit: "bpm",
                    comparison: comparison,
                    locale: locale
                ),
                metricRow(
                    id: "hrv-average",
                    label: "HRV Average",
                    state: hrv,
                    format: { HealthReportFormatter.hrvMilliseconds($0.current.average, locale: locale) }
                ),
                trendRow(
                    id: "hrv-trend",
                    label: "HRV Trend",
                    state: hrv,
                    unit: "ms",
                    comparison: comparison,
                    locale: locale
                ),
                metricRow(
                    id: "watch-coverage",
                    label: "Watch Data Coverage",
                    state: watchCoverage,
                    format: { "\($0.daysWithWatchData) / \($0.reportingDayCount) days" }
                )
            ],
            footer: nil
        )
    }

    private static func bloodPressureSection(
        _ state: MetricState<BloodPressureSummary>,
        showsMorningDetails: Bool,
        showsEveningDetails: Bool,
        calendar: Calendar,
        locale: Locale
    ) -> Section {
        let rows: [Row]
        switch state {
        case .idle, .loading:
            rows = [Row(
                "blood-pressure-loading",
                value: "Reading blood pressure…",
                style: .secondary
            )]
        case .available(let summary):
            var availableRows = [
                Row(
                    "blood-pressure-latest",
                    label: "Latest reading",
                    value: HealthReportFormatter.bloodPressure(
                        systolic: summary.latest.systolicMillimetresOfMercury,
                        diastolic: summary.latest.diastolicMillimetresOfMercury,
                        locale: locale
                    )
                ),
                Row(
                    "blood-pressure-recorded",
                    label: "Recorded",
                    value: HealthReportFormatter.dateAndTime(
                        summary.latest.date,
                        calendar: calendar,
                        locale: locale
                    ),
                    style: .secondary
                )
            ]
            availableRows += bloodPressureSlotRows(
                id: "morning",
                title: "Morning average",
                periodSummary: summary.morning,
                latestBatch: summary.latestMorningBatch,
                isExpanded: showsMorningDetails,
                calendar: calendar,
                locale: locale
            )
            availableRows += bloodPressureSlotRows(
                id: "evening",
                title: "Evening average",
                periodSummary: summary.evening,
                latestBatch: summary.latestEveningBatch,
                isExpanded: showsEveningDetails,
                calendar: calendar,
                locale: locale
            )
            rows = availableRows
        case .noDataOrAccess:
            rows = [Row(
                "blood-pressure-no-data",
                value: "No complete blood-pressure readings are visible, or Health access was not granted.",
                style: .secondary
            )]
        case .healthUnavailable:
            rows = [Row(
                "blood-pressure-unavailable",
                value: "Health data is unavailable on this device.",
                style: .secondary
            )]
        case .failed(let message):
            rows = [Row(
                "blood-pressure-failed",
                value: "Blood-pressure query failed: \(message)",
                style: .failure
            )]
        }
        return Section(
            id: .bloodPressure,
            title: "Blood Pressure",
            rows: rows,
            footer: "Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings are excluded from both slot summaries."
        )
    }

    private static func bloodPressureSlotRows(
        id: String,
        title: String,
        periodSummary: BloodPressurePeriodSlotSummary?,
        latestBatch: BloodPressureBatchSummary?,
        isExpanded: Bool,
        calendar: Calendar,
        locale: Locale
    ) -> [Row] {
        var rows = [Row(
            "blood-pressure-\(id)-average",
            label: title,
            value: periodSummary.map {
                HealthReportFormatter.bloodPressure(
                    systolic: $0.averageSystolic,
                    diastolic: $0.averageDiastolic,
                    locale: locale
                )
            } ?? "No data",
            style: periodSummary == nil ? .secondary : .standard
        )]
        guard isExpanded else { return rows }

        rows.append(Row(
            "blood-pressure-\(id)-latest-batch",
            label: "Latest batch",
            value: latestBatch.map {
                HealthReportFormatter.bloodPressure(
                    systolic: $0.averageSystolic,
                    diastolic: $0.averageDiastolic,
                    locale: locale
                )
            } ?? "No data",
            style: latestBatch == nil ? .secondary : .standard
        ))
        rows.append(Row(
            "blood-pressure-\(id)-recorded",
            label: "Recorded",
            value: latestBatch.map {
                let count = $0.readingCount == 1 ? "1 reading" : "\($0.readingCount) readings"
                return "\(HealthReportFormatter.dateAndTime($0.latestReadingDate, calendar: calendar, locale: locale)) · \(count)"
            } ?? "No data",
            style: latestBatch == nil ? .secondary : .standard
        ))
        rows.append(Row(
            "blood-pressure-\(id)-coverage",
            label: "Coverage",
            value: periodSummary.map {
                "\($0.sampledDayCount)/\($0.reportingDayCount) days · \($0.readingCount) readings"
            } ?? "No period data",
            style: periodSummary == nil ? .secondary : .standard
        ))
        return rows
    }

    private static func cardiorespiratorySection(
        vo2Max: MetricState<VO2MaxSummary>,
        bloodOxygen: MetricState<BloodOxygenSummary>,
        calendar: Calendar,
        locale: Locale
    ) -> Section {
        var rows = [metricRow(
            id: "vo2-max-latest",
            label: "Latest VO₂ Max",
            state: vo2Max,
            format: {
                HealthReportFormatter.vo2Max(
                    $0.latest.millilitresPerKilogramMinute,
                    locale: locale
                )
            }
        )]
        if case .available(let summary) = vo2Max {
            rows += [
                Row(
                    "vo2-max-measured",
                    label: "VO₂ Max Measured",
                    value: HealthReportFormatter.dateAndTime(
                        summary.latest.date,
                        calendar: calendar,
                        locale: locale
                    )
                ),
                Row(
                    "vo2-max-four-week",
                    label: "4-Week Average",
                    value: HealthReportFormatter.vo2MaxWindow(summary.fourWeek, locale: locale)
                ),
                Row(
                    "vo2-max-three-month",
                    label: "3-Month Average",
                    value: HealthReportFormatter.vo2MaxWindow(summary.threeMonth, locale: locale)
                ),
                Row(
                    "vo2-max-six-month",
                    label: "6-Month Average",
                    value: HealthReportFormatter.vo2MaxWindow(summary.sixMonth, locale: locale)
                )
            ]
        }

        rows.append(metricRow(
            id: "blood-oxygen-latest",
            label: "Latest Blood Oxygen",
            state: bloodOxygen,
            format: { HealthReportFormatter.bloodOxygen($0.latest.percentage, locale: locale) }
        ))
        if case .available(let summary) = bloodOxygen {
            rows += [
                Row(
                    "blood-oxygen-measured",
                    label: "Blood Oxygen Measured",
                    value: HealthReportFormatter.dateAndTime(
                        summary.latest.date,
                        calendar: calendar,
                        locale: locale
                    )
                ),
                Row(
                    "blood-oxygen-typical",
                    label: "Period Typical",
                    value: summary.typicalPercentage.map {
                        HealthReportFormatter.bloodOxygen($0, locale: locale)
                    } ?? "No data",
                    style: summary.typicalPercentage == nil ? .secondary : .standard
                ),
                Row(
                    "blood-oxygen-range",
                    label: "Daily Median Range",
                    value: summary.minimumDailyMedian.flatMap { minimum in
                        summary.maximumDailyMedian.map { maximum in
                            HealthReportFormatter.bloodOxygenRange(
                                minimum: minimum,
                                maximum: maximum,
                                locale: locale
                            )
                        }
                    } ?? "No data",
                    style: summary.minimumDailyMedian == nil || summary.maximumDailyMedian == nil
                        ? .secondary
                        : .standard
                ),
                Row(
                    "blood-oxygen-coverage",
                    label: "Blood Oxygen Coverage",
                    value: "\(summary.validDayCount) / \(summary.reportingDayCount) days"
                )
            ]
        }
        rows.append(Row(
            "blood-oxygen-note",
            value: "Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.",
            style: .note
        ))
        return Section(
            id: .cardiorespiratory,
            title: "Cardiorespiratory",
            rows: rows,
            footer: nil
        )
    }

    private static func glucoseSection(
        _ state: MetricState<GlucoseSummary>,
        locale: Locale
    ) -> Section {
        Section(
            id: .glucose,
            title: "Glucose",
            rows: [
                metricRow(
                    id: "glucose-average",
                    label: "Daily Average",
                    state: state,
                    format: { HealthReportFormatter.glucose($0.averageMillimolesPerLiter, locale: locale) }
                ),
                metricRow(
                    id: "glucose-range",
                    label: "Observed Range",
                    state: state,
                    format: {
                        HealthReportFormatter.glucoseRange(
                            minimum: $0.minimumMillimolesPerLiter,
                            maximum: $0.maximumMillimolesPerLiter,
                            locale: locale
                        )
                    }
                ),
                metricRow(
                    id: "glucose-coverage",
                    label: "Data Coverage",
                    state: state,
                    format: { "\($0.validDayCount) / \($0.reportingDayCount) days" }
                )
            ],
            footer: nil
        )
    }

    private static func activitySection(
        activeEnergy: MetricState<Double>,
        exercise: MetricState<Double>,
        workouts: MetricState<WorkoutSummary>,
        calendar: Calendar,
        locale: Locale
    ) -> Section {
        var rows = [
            metricRow(
                id: "active-energy",
                label: "Active Energy",
                state: activeEnergy,
                format: { HealthReportFormatter.energyKilocalories($0, locale: locale) }
            ),
            metricRow(
                id: "exercise",
                label: "Exercise",
                state: exercise,
                format: { HealthReportFormatter.minutes($0, locale: locale) }
            ),
            metricRow(
                id: "workouts",
                label: "Workouts",
                state: workouts,
                format: { String($0.count) }
            )
        ]
        if case .available(let summary) = workouts {
            rows.append(Row(
                "workout-time",
                label: "Workout Time",
                value: HealthReportFormatter.duration(summary.totalDuration)
            ))
            rows += summary.workouts.enumerated().map { index, workout in
                Row(
                    "workout-\(index)",
                    label: workout.activityName,
                    value: "\(HealthReportFormatter.duration(workout.duration)) — \(HealthReportFormatter.workoutDateAndTime(workout.startDate, calendar: calendar))"
                )
            }
        }
        return Section(id: .activity, title: "Activity", rows: rows, footer: nil)
    }

    private static func sleepSection(_ state: MetricState<SleepSummary>) -> Section {
        Section(
            id: .sleep,
            title: "Sleep",
            rows: [metricRow(
                id: "sleep-average",
                label: "Average Sleep",
                state: state,
                format: { HealthReportFormatter.duration($0.averageDuration) }
            )],
            footer: nil
        )
    }

    private static func medicationSection(
        _ state: MetricState<MedicationSummary>,
        calendar: Calendar,
        locale: Locale
    ) -> Section {
        let rows: [Row]
        switch state {
        case .idle, .loading:
            rows = [Row(
                "medications-loading",
                value: "Reading authorised medication events…",
                style: .secondary
            )]
        case .available(let summary):
            rows = summary.groups.enumerated().map { index, group in
                Row(
                    "medication-\(index)",
                    label: group.medicationName,
                    value: HealthReportFormatter.medicationGroupDetail(
                        group,
                        calendar: calendar,
                        locale: locale
                    )
                )
            }
        case .noDataOrAccess:
            rows = [Row(
                "medications-no-data",
                value: "No taken medication events are visible for this period.",
                style: .secondary
            )]
        case .healthUnavailable:
            rows = [Row(
                "medications-unavailable",
                value: "Health data is unavailable on this device.",
                style: .secondary
            )]
        case .failed(let message):
            rows = [Row(
                "medications-failed",
                value: "Medication query failed: \(message)",
                style: .failure
            )]
        }
        return Section(
            id: .medications,
            title: "Medications Taken",
            rows: rows,
            footer: nil
        )
    }

    private static func metricRow<Value: Equatable>(
        id: String,
        label: String,
        state: MetricState<Value>,
        format: (Value) -> String
    ) -> Row {
        switch state {
        case .idle, .loading:
            Row(id, label: label, value: "Loading…", style: .secondary)
        case .available(let value):
            Row(id, label: label, value: format(value))
        case .noDataOrAccess:
            Row(id, label: label, value: "No data", style: .secondary)
        case .healthUnavailable:
            Row(id, label: label, value: "Unavailable", style: .secondary)
        case .failed:
            Row(id, label: label, value: "Query failed", style: .failure)
        }
    }

    private static func trendRow(
        id: String,
        label: String,
        state: MetricState<HeartMetricTrendSummary>,
        unit: String,
        comparison: String,
        locale: Locale
    ) -> Row {
        switch state {
        case .available(let summary):
            Row(
                id,
                label: label,
                value: summary.trend.map {
                    HealthReportFormatter.signedChange(
                        $0,
                        unit: unit,
                        comparison: comparison,
                        locale: locale
                    )
                } ?? "Insufficient history",
                style: summary.trend == nil ? .secondary : .standard
            )
        case .idle, .loading:
            Row(id, label: label, value: "Loading…", style: .secondary)
        case .noDataOrAccess:
            Row(id, label: label, value: "No data", style: .secondary)
        case .healthUnavailable:
            Row(id, label: label, value: "Unavailable", style: .secondary)
        case .failed:
            Row(id, label: label, value: "Query failed", style: .failure)
        }
    }
}
