import SwiftUI

struct StepsReportSection: View {
    let state: WeeklyReportViewModel.State

    var body: some View {
        Section("Steps") {
            switch state {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Reading Apple Health…")
                }

            case .loaded(let summary):
                LabeledContent(
                    "Average Daily Steps",
                    value: summary.averageDailySteps.formatted(
                        .number.precision(.fractionLength(0))
                    )
                )
                LabeledContent(
                    "Data Coverage",
                    value: HealthReportFormatter.stepCoverage(summary)
                )
                LabeledContent(
                    "Weekly Total",
                    value: summary.totalSteps.formatted(
                        .number.precision(.fractionLength(0))
                    )
                )

            case .noCompletedDays:
                Text("There are no completed days in this period yet.")
                    .foregroundStyle(.secondary)

            case .noDataOrAccess:
                Text("No step data is visible, or Health access was not granted.")
                    .foregroundStyle(.secondary)

            case .healthUnavailable:
                Text("Health data is unavailable on this device.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Text("Step query failed: \(message)")
                    .foregroundStyle(.red)
            }
        }
    }
}

struct BodyMeasurementsReportSections: View {
    let weightState: WeeklyReportViewModel.WeightState
    let bodyFatState: WeeklyReportViewModel.BodyFatState
    let waistState: MetricState<WaistSummary>

    var body: some View {
        Section("Weight") {
            switch weightState {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Reading latest weight…")
                }

            case .available(let summary):
                LabeledContent(
                    "Latest Weight",
                    value: HealthReportFormatter.weightKilograms(summary.latest.kilograms)
                )
                LabeledContent(
                    "Measured",
                    value: HealthReportFormatter.dateAndTime(summary.latest.date)
                )
                if let average = summary.currentSevenDayAverage {
                    LabeledContent(
                        "7-day Average",
                        value: HealthReportFormatter.weightKilograms(average)
                    )
                } else {
                    LabeledContent("7-day Average", value: "Insufficient history")
                        .foregroundStyle(.secondary)
                }
                if let trend = summary.trendKilograms {
                    LabeledContent(
                        "Weight Trend",
                        value: HealthReportFormatter.signedChange(
                            trend,
                            unit: "kg",
                            comparison: "previous 7d"
                        )
                    )
                } else {
                    LabeledContent("Weight Trend", value: "Insufficient history")
                        .foregroundStyle(.secondary)
                }

            case .noDataOrAccess:
                Text("No weight data is visible, or Health access was not granted.")
                    .foregroundStyle(.secondary)

            case .healthUnavailable:
                Text("Health data is unavailable on this device.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Text("Weight query failed: \(message)")
                    .foregroundStyle(.red)
            }
        }

        Section("Body Composition") {
            switch bodyFatState {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Reading body-fat history…")
                }

            case .available(let summary):
                LabeledContent(
                    "Body Fat",
                    value: "\(HealthReportFormatter.percentage(summary.latest.percentage)) latest"
                )
                if let average = summary.sevenDayAverage {
                    LabeledContent(
                        "7-day Average",
                        value: HealthReportFormatter.percentage(average)
                    )
                }
                if let average = summary.current28DayAverage {
                    LabeledContent(
                        "28-day Average",
                        value: HealthReportFormatter.percentage(average)
                    )
                } else {
                    LabeledContent("28-day Average", value: "Insufficient history")
                        .foregroundStyle(.secondary)
                }
                if let trend = summary.trendPercentagePoints {
                    LabeledContent(
                        "Body Fat Trend",
                        value: HealthReportFormatter.percentagePointTrend(trend)
                    )
                } else {
                    LabeledContent("Body Fat Trend", value: "Insufficient history")
                        .foregroundStyle(.secondary)
                }

            case .noDataOrAccess:
                Text("No body-fat data is visible, or Health access was not granted.")
                    .foregroundStyle(.secondary)

            case .healthUnavailable:
                Text("Health data is unavailable on this device.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Text("Body-fat query failed: \(message)")
                    .foregroundStyle(.red)
            }

            ReportMetricRow(
                "Waist Circumference",
                state: waistState,
                format: { HealthReportFormatter.waistCentimetres($0.latest.centimetres) }
            )
            if case .available(let summary) = waistState {
                LabeledContent(
                    "Waist Measured",
                    value: HealthReportFormatter.dateAndTime(summary.latest.date)
                )
                if let change = summary.fourWeekChangeCentimetres {
                    LabeledContent(
                        "4-week Waist Trend",
                        value: HealthReportFormatter.signedChange(
                            change,
                            unit: "cm",
                            comparison: "~4 weeks earlier"
                        )
                    )
                } else {
                    LabeledContent("4-week Waist Trend", value: "Insufficient history")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct HeartReportSection: View {
    let restingHeartRateState: MetricState<HeartMetricTrendSummary>
    let hrvState: MetricState<HeartMetricTrendSummary>
    let watchCoverageState: MetricState<WatchCoverageSummary>
    let comparisonDayCount: Int

    var body: some View {
        Section("Heart") {
            ReportMetricRow(
                "Resting HR Average",
                state: restingHeartRateState,
                format: { HealthReportFormatter.heartRate($0.current.average) }
            )
            HeartTrendRow(
                "Resting HR Trend",
                state: restingHeartRateState,
                unit: "bpm",
                comparisonDayCount: comparisonDayCount
            )
            ReportMetricRow(
                "HRV Average",
                state: hrvState,
                format: { HealthReportFormatter.hrvMilliseconds($0.current.average) }
            )
            HeartTrendRow(
                "HRV Trend",
                state: hrvState,
                unit: "ms",
                comparisonDayCount: comparisonDayCount
            )
            ReportMetricRow(
                "Watch Data Coverage",
                state: watchCoverageState,
                format: { "\($0.daysWithWatchData) / \($0.reportingDayCount) days" }
            )
        }
    }
}

struct BloodPressureReportSection: View {
    let state: MetricState<BloodPressureSummary>
    @Binding var showsMorningDetails: Bool
    @Binding var showsEveningDetails: Bool

    var body: some View {
        Section {
            switch state {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Reading blood pressure…")
                }
            case .available(let summary):
                VStack(alignment: .leading, spacing: 5) {
                    responsiveLabel(
                        "Latest reading",
                        value: HealthReportFormatter.bloodPressure(
                            systolic: summary.latest.systolicMillimetresOfMercury,
                            diastolic: summary.latest.diastolicMillimetresOfMercury
                        )
                    )
                    Text(HealthReportFormatter.dateAndTime(summary.latest.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                disclosure(
                    title: "Morning average",
                    periodSummary: summary.morning,
                    latestBatch: summary.latestMorningBatch,
                    isExpanded: $showsMorningDetails
                )
                disclosure(
                    title: "Evening average",
                    periodSummary: summary.evening,
                    latestBatch: summary.latestEveningBatch,
                    isExpanded: $showsEveningDetails
                )
            case .noDataOrAccess:
                Text("No complete blood-pressure readings are visible, or Health access was not granted.")
                    .foregroundStyle(.secondary)
            case .healthUnavailable:
                Text("Health data is unavailable on this device.")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text("Blood-pressure query failed: \(message)")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Blood Pressure")
        } footer: {
            Text("Period averages use completed days. Morning is before 14:00; evening is from 17:00. Mid-afternoon readings remain visible in Diagnostics.")
        }
    }

    @ViewBuilder
    private func responsiveLabel(_ label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func disclosure(
        title: String,
        periodSummary: BloodPressurePeriodSlotSummary?,
        latestBatch: BloodPressureBatchSummary?,
        isExpanded: Binding<Bool>
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            responsiveLabel(
                "Latest batch",
                value: latestBatch.map {
                    HealthReportFormatter.bloodPressure(
                        systolic: $0.averageSystolic,
                        diastolic: $0.averageDiastolic
                    )
                } ?? "No data"
            )
            responsiveLabel(
                "Recorded",
                value: latestBatch.map {
                    let count = $0.readingCount == 1
                        ? "1 reading"
                        : "\($0.readingCount) readings"
                    return "\(HealthReportFormatter.dateAndTime($0.latestReadingDate)) · \(count)"
                } ?? "No data"
            )
            responsiveLabel(
                "Coverage",
                value: periodSummary.map {
                    "\($0.sampledDayCount)/\($0.reportingDayCount) days · \($0.readingCount) readings"
                }
                    ?? "No period data"
            )
        } label: {
            responsiveLabel(
                title,
                value: periodSummary.map {
                    HealthReportFormatter.bloodPressure(
                        systolic: $0.averageSystolic,
                        diastolic: $0.averageDiastolic
                    )
                } ?? "No data"
            )
        }
    }
}

struct CardiorespiratoryReportSection: View {
    let vo2MaxState: MetricState<VO2MaxSummary>
    let bloodOxygenState: MetricState<BloodOxygenSummary>

    var body: some View {
        Section("Cardiorespiratory") {
            ReportMetricRow(
                "Latest VO₂ Max",
                state: vo2MaxState,
                format: {
                    HealthReportFormatter.vo2Max(
                        $0.latest.millilitresPerKilogramMinute
                    )
                }
            )
            if case .available(let summary) = vo2MaxState {
                LabeledContent(
                    "VO₂ Max Measured",
                    value: HealthReportFormatter.dateAndTime(summary.latest.date)
                )
                LabeledContent(
                    "4-Week Average",
                    value: HealthReportFormatter.vo2MaxWindow(summary.fourWeek)
                )
                LabeledContent(
                    "3-Month Average",
                    value: HealthReportFormatter.vo2MaxWindow(summary.threeMonth)
                )
                LabeledContent(
                    "6-Month Average",
                    value: HealthReportFormatter.vo2MaxWindow(summary.sixMonth)
                )
            }

            ReportMetricRow(
                "Latest Blood Oxygen",
                state: bloodOxygenState,
                format: { HealthReportFormatter.bloodOxygen($0.latest.percentage) }
            )
            if case .available(let summary) = bloodOxygenState {
                LabeledContent(
                    "Blood Oxygen Measured",
                    value: HealthReportFormatter.dateAndTime(summary.latest.date)
                )
                LabeledContent(
                    "Period Typical",
                    value: summary.typicalPercentage.map {
                        HealthReportFormatter.bloodOxygen($0)
                    } ?? "No data"
                )
                LabeledContent(
                    "Daily Median Range",
                    value: summary.minimumDailyMedian.flatMap { minimum in
                        summary.maximumDailyMedian.map { maximum in
                            HealthReportFormatter.bloodOxygenRange(
                                minimum: minimum,
                                maximum: maximum
                            )
                        }
                    } ?? "No data"
                )
                LabeledContent(
                    "Blood Oxygen Coverage",
                    value: "\(summary.validDayCount) / \(summary.reportingDayCount) days"
                )
            }

            Text("Apple Watch blood-oxygen measurements are wellness estimates, not medical measurements.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct GlucoseReportSection: View {
    let state: MetricState<GlucoseSummary>

    var body: some View {
        Section("Glucose") {
            ReportMetricRow(
                "Daily Average",
                state: state,
                format: { HealthReportFormatter.glucose($0.averageMillimolesPerLiter) }
            )
            ReportMetricRow(
                "Observed Range",
                state: state,
                format: {
                    HealthReportFormatter.glucoseRange(
                        minimum: $0.minimumMillimolesPerLiter,
                        maximum: $0.maximumMillimolesPerLiter
                    )
                }
            )
            ReportMetricRow(
                "Data Coverage",
                state: state,
                format: { "\($0.validDayCount) / \($0.reportingDayCount) days" }
            )
        }
    }
}

struct ActivityReportSection: View {
    let activeEnergyState: MetricState<Double>
    let exerciseState: MetricState<Double>
    let workoutState: MetricState<WorkoutSummary>

    var body: some View {
        Section("Activity") {
            ReportMetricRow(
                "Active Energy",
                state: activeEnergyState,
                format: { HealthReportFormatter.energyKilocalories($0) }
            )
            ReportMetricRow(
                "Exercise",
                state: exerciseState,
                format: { HealthReportFormatter.minutes($0) }
            )
            ReportMetricRow(
                "Workouts",
                state: workoutState,
                format: { String($0.count) }
            )
            if case .available(let summary) = workoutState {
                LabeledContent(
                    "Workout Time",
                    value: HealthReportFormatter.duration(summary.totalDuration)
                )
                ForEach(summary.workouts) { workout in
                    LabeledContent(
                        workout.activityName,
                        value: "\(HealthReportFormatter.duration(workout.duration)) — \(HealthReportFormatter.workoutDateAndTime(workout.startDate))"
                    )
                }
            }
        }
    }
}

struct SleepReportSection: View {
    let state: MetricState<SleepSummary>

    var body: some View {
        Section("Sleep") {
            ReportMetricRow(
                "Average Sleep",
                state: state,
                format: { HealthReportFormatter.duration($0.averageDuration) }
            )
        }
    }
}

private struct ReportMetricRow<Value: Equatable>: View {
    let label: String
    let state: MetricState<Value>
    let format: (Value) -> String

    init(
        _ label: String,
        state: MetricState<Value>,
        format: @escaping (Value) -> String
    ) {
        self.label = label
        self.state = state
        self.format = format
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            LabeledContent(label) { ProgressView() }
        case .available(let value):
            LabeledContent(label, value: format(value))
        case .noDataOrAccess:
            LabeledContent(label, value: "No data")
                .foregroundStyle(.secondary)
        case .healthUnavailable:
            LabeledContent(label, value: "Unavailable")
                .foregroundStyle(.secondary)
        case .failed:
            LabeledContent(label, value: "Query failed")
                .foregroundStyle(.red)
        }
    }
}

private struct HeartTrendRow: View {
    let label: String
    let state: MetricState<HeartMetricTrendSummary>
    let unit: String
    let comparisonDayCount: Int

    init(
        _ label: String,
        state: MetricState<HeartMetricTrendSummary>,
        unit: String,
        comparisonDayCount: Int
    ) {
        self.label = label
        self.state = state
        self.unit = unit
        self.comparisonDayCount = comparisonDayCount
    }

    var body: some View {
        switch state {
        case .available(let summary):
            if let trend = summary.trend {
                LabeledContent(
                    label,
                    value: HealthReportFormatter.signedChange(
                        trend,
                        unit: unit,
                        comparison: "previous \(comparisonDayCount)d"
                    )
                )
            } else {
                LabeledContent(label, value: "Insufficient history")
                    .foregroundStyle(.secondary)
            }
        case .idle, .loading:
            LabeledContent(label) { ProgressView() }
        case .noDataOrAccess:
            LabeledContent(label, value: "No data").foregroundStyle(.secondary)
        case .healthUnavailable:
            LabeledContent(label, value: "Unavailable").foregroundStyle(.secondary)
        case .failed:
            LabeledContent(label, value: "Query failed").foregroundStyle(.red)
        }
    }
}
