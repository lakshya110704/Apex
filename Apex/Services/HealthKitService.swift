import Foundation
import HealthKit
import Observation

@Observable
final class HealthKitService {

    var isAuthorized = false
    var healthNotice: String?
    var todaySteps: Int = 0
    var todayActiveCalories: Double = 0
    var todayExerciseMinutes: Double = 0
    var todayStandHours: Int = 0
    var moveGoal: Double = 500
    var exerciseGoal: Double = 30
    var standGoal: Int = 12
    var restingHeartRate: Double = 0
    var hrv: Double = 0
    var sleepHoursLast: Double = 0
    var recentWorkouts: [HKWorkout] = []

    // Extended metrics
    var vo2Max: Double = 0
    var respiratoryRate: Double = 0
    var weight: Double = 0
    var mindfulMinutes: Double = 0

    // 7-day trends
    var weeklyAvgSleep: Double = 0
    var weeklyAvgHRV: Double = 0
    var weeklyAvgActiveCalories: Double = 0
    var weeklyWorkoutCount: Int = 0

    private let store = HKHealthStore()

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthNotice = "Health data isn't available on this device."
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.activitySummaryType(),
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            await fetchAllTodayData()
            let noData = todaySteps == 0 && restingHeartRate == 0 && hrv == 0 && sleepHoursLast == 0
            healthNotice = noData ? "No Health data found yet. If you declined access, turn it on in Settings > Health > Data Access & Devices > Apex." : nil
        } catch {
            healthNotice = "Couldn't connect to Health. Check Settings > Health > Data Access & Devices > Apex."
        }
    }

    // MARK: - Fetch All

    func fetchAllTodayData() async {
        async let steps       = fetchTodaySteps()
        async let calories    = fetchTodayActiveCalories()
        async let exerciseMins = fetchTodayExerciseMinutes()
        async let rhr         = fetchRestingHeartRate()
        async let hrvVal      = fetchHRV()
        async let sleep       = fetchLastNightSleep()
        async let workouts    = fetchRecentWorkouts(days: 14)
        async let summary     = fetchActivitySummary()
        async let vo2         = fetchVO2Max()
        async let resp        = fetchRespiratoryRate()
        async let bw          = fetchWeight()
        async let mindful     = fetchMindfulMinutes()
        async let avgSleep    = fetchWeeklyAvgSleep()
        async let avgHRV      = fetchWeeklyAvgHRV()
        async let avgCals     = fetchWeeklyAvgActiveCalories()

        todaySteps          = await steps
        todayActiveCalories = await calories
        todayExerciseMinutes = await exerciseMins
        restingHeartRate    = await rhr
        hrv                 = await hrvVal
        sleepHoursLast      = await sleep
        recentWorkouts      = await workouts
        vo2Max              = await vo2
        respiratoryRate     = await resp
        weight              = await bw
        mindfulMinutes      = await mindful
        weeklyAvgSleep      = await avgSleep
        weeklyAvgHRV        = await avgHRV
        weeklyAvgActiveCalories = await avgCals

        let fetched = await workouts
        weeklyWorkoutCount = fetched.filter {
            $0.startDate >= Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }.count

        if let s = await summary {
            moveGoal    = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
            exerciseGoal = s.appleExerciseTimeGoal.doubleValue(for: .minute())
            standGoal   = Int(s.appleStandHoursGoal.doubleValue(for: .count()))
            todayStandHours = Int(s.appleStandHours.doubleValue(for: .count()))
        }
    }

    // MARK: - Steps

    func fetchTodaySteps() async -> Int {
        await fetchQuantity(
            type: .stepCount,
            unit: .count(),
            options: .cumulativeSum,
            from: Calendar.current.startOfDay(for: Date())
        ).map(Int.init) ?? 0
    }

    // MARK: - Active Calories

    func fetchTodayActiveCalories() async -> Double {
        await fetchQuantity(
            type: .activeEnergyBurned,
            unit: .kilocalorie(),
            options: .cumulativeSum,
            from: Calendar.current.startOfDay(for: Date())
        ) ?? 0
    }

    // MARK: - Exercise Minutes

    func fetchTodayExerciseMinutes() async -> Double {
        await fetchQuantity(
            type: .appleExerciseTime,
            unit: .minute(),
            options: .cumulativeSum,
            from: Calendar.current.startOfDay(for: Date())
        ) ?? 0
    }

    // MARK: - Stand Hours

    func fetchTodayStandHours() async -> Int {
        await withCheckedContinuation { continuation in
            let type = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
            let predicate = HKQuery.predicateForSamples(
                withStart: Calendar.current.startOfDay(for: Date()),
                end: Date()
            )
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let standSamples = samples as? [HKCategorySample] ?? []
                let hours = standSamples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count
                continuation.resume(returning: hours)
            }
            store.execute(query)
        }
    }

    // MARK: - Resting Heart Rate

    func fetchRestingHeartRate() async -> Double {
        await fetchQuantity(
            type: .restingHeartRate,
            unit: HKUnit(from: "count/min"),
            options: .discreteMostRecent,
            from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        ) ?? 0
    }

    // MARK: - HRV

    func fetchHRV() async -> Double {
        await fetchQuantity(
            type: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            options: .discreteMostRecent,
            from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        ) ?? 0
    }

    // MARK: - Sleep

    func fetchLastNightSleep() async -> Double {
        await withCheckedContinuation { continuation in
            let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: Date())
            // Yesterday 8PM → today noon: captures exactly one night's sleep
            let windowStart = cal.date(byAdding: .hour, value: -4,  to: startOfToday)!
            let windowEnd   = cal.date(byAdding: .hour, value: +12, to: startOfToday)!
            let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let sleepSamples = samples as? [HKCategorySample] ?? []
                let asleepSeconds = sleepSamples
                    .filter { [
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    ].contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: asleepSeconds / 3600)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    func fetchRecentWorkouts(days: Int = 14) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Activity Summary

    func fetchActivitySummary() async -> HKActivitySummary? {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            var today = calendar.dateComponents([.year, .month, .day], from: Date())
            today.calendar = calendar
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: today, end: today)
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                continuation.resume(returning: summaries?.first)
            }
            store.execute(query)
        }
    }

    // MARK: - Generic Quantity Fetcher

    private func fetchQuantity(
        type identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        from start: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: options) { _, result, _ in
                if options == .cumulativeSum {
                    continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: result?.mostRecentQuantity()?.doubleValue(for: unit))
                }
            }
            self.store.execute(query)
        }
    }

    // MARK: - Extended Metrics

    func fetchVO2Max() async -> Double {
        let vo2Unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
        return await fetchQuantity(
            type: .vo2Max,
            unit: vo2Unit,
            options: .discreteMostRecent,
            from: Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        ) ?? 0
    }

    func fetchRespiratoryRate() async -> Double {
        let breathsPerMin = HKUnit.count().unitDivided(by: HKUnit.minute())
        return await fetchQuantity(
            type: .respiratoryRate,
            unit: breathsPerMin,
            options: .discreteMostRecent,
            from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        ) ?? 0
    }

    func fetchWeight() async -> Double {
        await fetchQuantity(
            type: .bodyMass,
            unit: .gramUnit(with: .kilo),
            options: .discreteMostRecent,
            from: Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        ) ?? 0
    }

    func fetchMindfulMinutes() async -> Double {
        await withCheckedContinuation { continuation in
            guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
                continuation.resume(returning: 0); return
            }
            let predicate = HKQuery.predicateForSamples(
                withStart: Calendar.current.startOfDay(for: Date()), end: Date()
            )
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let mins = (samples as? [HKCategorySample] ?? [])
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
                continuation.resume(returning: mins)
            }
            self.store.execute(query)
        }
    }

    // MARK: - 7-Day Trends

    func fetchWeeklyAvgSleep() async -> Double {
        await withCheckedContinuation { continuation in
            let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let total = (samples as? [HKCategorySample] ?? [])
                    .filter { [
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    ].contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: total / 3600 / 7)
            }
            self.store.execute(query)
        }
    }

    func fetchWeeklyAvgHRV() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return 0 }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)) ?? 0)
            }
            self.store.execute(query)
        }
    }

    func fetchWeeklyAvgActiveCalories() async -> Double {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let total = await fetchQuantity(type: .activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, from: start) ?? 0
        return total / 7.0
    }

    // MARK: - Watch Workout Import

    func buildWorkoutSession(from hkWorkout: HKWorkout) async -> WorkoutSession {
        let avgHR = await fetchAverageHeartRate(during: hkWorkout)
        let calories = Int(hkWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)
        let duration = Int(hkWorkout.duration / 60)
        let type = Self.workoutType(from: hkWorkout.workoutActivityType)

        return WorkoutSession(
            date: hkWorkout.startDate,
            type: type,
            durationMinutes: max(duration, 1),
            averageHeartRate: avgHR,
            caloriesBurned: calories,
            importedFromHealthKit: true,
            healthKitUUID: hkWorkout.uuid.uuidString as String?
        )
    }

    func fetchAverageHeartRate(during workout: HKWorkout) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                let bpm = result?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
                continuation.resume(returning: Int(bpm))
            }
            store.execute(query)
        }
    }

    static func workoutType(from hkType: HKWorkoutActivityType) -> WorkoutType {
        switch hkType {
        case .tennis:
            return .tennis
        case .traditionalStrengthTraining, .functionalStrengthTraining,
             .crossTraining, .highIntensityIntervalTraining, .mixedCardio,
             .coreTraining, .flexibility:
            return .gym
        case .running, .walking, .cycling, .swimBikeRun:
            return .run
        default:
            return .other
        }
    }

    // MARK: - Ring Progress Helpers

    var moveProgress: Double {
        guard moveGoal > 0 else { return 0 }
        return min(todayActiveCalories / moveGoal, 1.0)
    }

    var exerciseProgress: Double {
        guard exerciseGoal > 0 else { return 0 }
        return min(todayExerciseMinutes / exerciseGoal, 1.0)
    }

    var standProgress: Double {
        guard standGoal > 0 else { return 0 }
        return min(Double(todayStandHours) / Double(standGoal), 1.0)
    }
}
