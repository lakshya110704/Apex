import Foundation

struct ExerciseInfo: Identifiable {
    let id = UUID()
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: String
    let videoURL: String  // YouTube search URL — always fresh results

    static func searchURL(_ exercise: String) -> String {
        let query = "\(exercise) proper form technique tutorial"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://www.youtube.com/results?search_query=\(query)"
    }
}

// MARK: - Database

enum ExerciseDatabase {

    static let all: [ExerciseInfo] = chest + back + legs + shoulders + biceps + triceps + core

    // MARK: Chest
    static let chest: [ExerciseInfo] = [
        ExerciseInfo(name: "Barbell Bench Press",  muscleGroup: .chest,     equipment: "Barbell",    videoURL: searchURL("barbell bench press")),
        ExerciseInfo(name: "Incline Bench Press",  muscleGroup: .chest,     equipment: "Barbell",    videoURL: searchURL("incline bench press")),
        ExerciseInfo(name: "Dumbbell Fly",          muscleGroup: .chest,     equipment: "Dumbbells",  videoURL: searchURL("dumbbell fly")),
        ExerciseInfo(name: "Cable Fly",             muscleGroup: .chest,     equipment: "Cable",      videoURL: searchURL("cable fly chest")),
        ExerciseInfo(name: "Push-Up",               muscleGroup: .chest,     equipment: "Bodyweight", videoURL: searchURL("push up form")),
        ExerciseInfo(name: "Dips",                  muscleGroup: .chest,     equipment: "Bodyweight", videoURL: searchURL("chest dips form")),
        ExerciseInfo(name: "Pec Deck Machine",      muscleGroup: .chest,     equipment: "Machine",    videoURL: searchURL("pec deck machine")),
    ]

    // MARK: Back
    static let back: [ExerciseInfo] = [
        ExerciseInfo(name: "Pull-Up",               muscleGroup: .back,      equipment: "Bodyweight", videoURL: searchURL("pull up form")),
        ExerciseInfo(name: "Barbell Row",            muscleGroup: .back,      equipment: "Barbell",    videoURL: searchURL("barbell row form")),
        ExerciseInfo(name: "Lat Pulldown",           muscleGroup: .back,      equipment: "Cable",      videoURL: searchURL("lat pulldown form")),
        ExerciseInfo(name: "Seated Cable Row",       muscleGroup: .back,      equipment: "Cable",      videoURL: searchURL("seated cable row")),
        ExerciseInfo(name: "Deadlift",               muscleGroup: .back,      equipment: "Barbell",    videoURL: searchURL("deadlift form technique")),
        ExerciseInfo(name: "Single Arm Dumbbell Row",muscleGroup: .back,      equipment: "Dumbbell",   videoURL: searchURL("single arm dumbbell row")),
        ExerciseInfo(name: "Face Pull",              muscleGroup: .back,      equipment: "Cable",      videoURL: searchURL("face pull rear delt")),
        ExerciseInfo(name: "T-Bar Row",              muscleGroup: .back,      equipment: "Barbell",    videoURL: searchURL("t bar row form")),
    ]

    // MARK: Legs
    static let legs: [ExerciseInfo] = [
        ExerciseInfo(name: "Barbell Back Squat",     muscleGroup: .legs,      equipment: "Barbell",    videoURL: searchURL("barbell squat form")),
        ExerciseInfo(name: "Romanian Deadlift",      muscleGroup: .legs,      equipment: "Barbell",    videoURL: searchURL("romanian deadlift form")),
        ExerciseInfo(name: "Leg Press",              muscleGroup: .legs,      equipment: "Machine",    videoURL: searchURL("leg press form")),
        ExerciseInfo(name: "Lunges",                 muscleGroup: .legs,      equipment: "Bodyweight", videoURL: searchURL("lunges form")),
        ExerciseInfo(name: "Leg Curl",               muscleGroup: .legs,      equipment: "Machine",    videoURL: searchURL("leg curl hamstring")),
        ExerciseInfo(name: "Leg Extension",          muscleGroup: .legs,      equipment: "Machine",    videoURL: searchURL("leg extension form")),
        ExerciseInfo(name: "Hip Thrust",             muscleGroup: .legs,      equipment: "Barbell",    videoURL: searchURL("barbell hip thrust form")),
        ExerciseInfo(name: "Calf Raise",             muscleGroup: .legs,      equipment: "Machine",    videoURL: searchURL("calf raise form")),
        ExerciseInfo(name: "Bulgarian Split Squat",  muscleGroup: .legs,      equipment: "Dumbbells",  videoURL: searchURL("bulgarian split squat")),
    ]

    // MARK: Shoulders
    static let shoulders: [ExerciseInfo] = [
        ExerciseInfo(name: "Overhead Press",         muscleGroup: .shoulders, equipment: "Barbell",    videoURL: searchURL("overhead press form")),
        ExerciseInfo(name: "Dumbbell Lateral Raise", muscleGroup: .shoulders, equipment: "Dumbbells",  videoURL: searchURL("lateral raise form")),
        ExerciseInfo(name: "Front Raise",            muscleGroup: .shoulders, equipment: "Dumbbells",  videoURL: searchURL("front raise shoulders")),
        ExerciseInfo(name: "Arnold Press",           muscleGroup: .shoulders, equipment: "Dumbbells",  videoURL: searchURL("arnold press form")),
        ExerciseInfo(name: "Rear Delt Fly",          muscleGroup: .shoulders, equipment: "Dumbbells",  videoURL: searchURL("rear delt fly form")),
        ExerciseInfo(name: "Upright Row",            muscleGroup: .shoulders, equipment: "Barbell",    videoURL: searchURL("upright row form")),
    ]

    // MARK: Biceps
    static let biceps: [ExerciseInfo] = [
        ExerciseInfo(name: "Barbell Curl",           muscleGroup: .biceps,    equipment: "Barbell",    videoURL: searchURL("barbell curl form")),
        ExerciseInfo(name: "Hammer Curl",            muscleGroup: .biceps,    equipment: "Dumbbells",  videoURL: searchURL("hammer curl form")),
        ExerciseInfo(name: "Incline Dumbbell Curl",  muscleGroup: .biceps,    equipment: "Dumbbells",  videoURL: searchURL("incline dumbbell curl")),
        ExerciseInfo(name: "Cable Curl",             muscleGroup: .biceps,    equipment: "Cable",      videoURL: searchURL("cable curl bicep")),
        ExerciseInfo(name: "Concentration Curl",     muscleGroup: .biceps,    equipment: "Dumbbell",   videoURL: searchURL("concentration curl form")),
        ExerciseInfo(name: "Chin-Up",                muscleGroup: .biceps,    equipment: "Bodyweight", videoURL: searchURL("chin up form")),
    ]

    // MARK: Triceps
    static let triceps: [ExerciseInfo] = [
        ExerciseInfo(name: "Tricep Pushdown",        muscleGroup: .triceps,   equipment: "Cable",      videoURL: searchURL("tricep pushdown form")),
        ExerciseInfo(name: "Skull Crusher",          muscleGroup: .triceps,   equipment: "Barbell",    videoURL: searchURL("skull crusher form")),
        ExerciseInfo(name: "Overhead Tricep Extension", muscleGroup: .triceps, equipment: "Dumbbell",  videoURL: searchURL("overhead tricep extension")),
        ExerciseInfo(name: "Close-Grip Bench Press", muscleGroup: .triceps,   equipment: "Barbell",    videoURL: searchURL("close grip bench press")),
        ExerciseInfo(name: "Tricep Dips",            muscleGroup: .triceps,   equipment: "Bodyweight", videoURL: searchURL("tricep dips form")),
        ExerciseInfo(name: "Rope Pushdown",          muscleGroup: .triceps,   equipment: "Cable",      videoURL: searchURL("rope pushdown tricep")),
    ]

    // MARK: Core
    static let core: [ExerciseInfo] = [
        ExerciseInfo(name: "Plank",                  muscleGroup: .core,      equipment: "Bodyweight", videoURL: searchURL("plank form core")),
        ExerciseInfo(name: "Hanging Leg Raise",      muscleGroup: .core,      equipment: "Bodyweight", videoURL: searchURL("hanging leg raise form")),
        ExerciseInfo(name: "Cable Crunch",           muscleGroup: .core,      equipment: "Cable",      videoURL: searchURL("cable crunch abs")),
        ExerciseInfo(name: "Russian Twist",          muscleGroup: .core,      equipment: "Bodyweight", videoURL: searchURL("russian twist core")),
        ExerciseInfo(name: "Ab Rollout",             muscleGroup: .core,      equipment: "Ab Wheel",   videoURL: searchURL("ab rollout wheel form")),
        ExerciseInfo(name: "Dead Bug",               muscleGroup: .core,      equipment: "Bodyweight", videoURL: searchURL("dead bug exercise form")),
    ]

    // MARK: Helpers

    static func byMuscleGroup(_ group: MuscleGroup) -> [ExerciseInfo] {
        all.filter { $0.muscleGroup == group }
    }

    static func search(_ query: String) -> [ExerciseInfo] {
        guard query.isNotEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private static func searchURL(_ terms: String) -> String {
        ExerciseInfo.searchURL(terms)
    }
}

// MARK: - Tennis Drills Database

enum TennisDrillDatabase {
    static let all: [String] = [
        "Serve practice",
        "Forehand groundstrokes",
        "Backhand groundstrokes",
        "Cross-court rallies",
        "Down-the-line shots",
        "Volley practice",
        "Overhead smash",
        "Return of serve",
        "Approach shots",
        "Drop shots",
        "Lobs",
        "Mini tennis (short court)",
        "Footwork ladder drills",
        "Multi-ball feeding",
        "Match play",
        "Slice backhand",
        "Topspin forehand",
        "Serve and volley",
        "Half volley",
        "Net play",
    ]
}
