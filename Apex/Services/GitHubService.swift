import Foundation
import Observation

@Observable
final class GitHubService {
    var todayCommits: Int = 0
    var activeRepos: [String] = []
    var isLoading = false

    func fetchActivity(username: String) async {
        guard !username.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "https://api.github.com/users/\(username)/events/public?per_page=100") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ApexApp/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let todayStart = Calendar.current.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()

        var commits = 0
        var repos: Set<String> = []

        for event in events {
            guard event["type"] as? String == "PushEvent",
                  let createdAt = event["created_at"] as? String,
                  let date = formatter.date(from: createdAt),
                  date >= todayStart,
                  let repoDict = event["repo"] as? [String: Any],
                  let repoName = repoDict["name"] as? String,
                  let payload = event["payload"] as? [String: Any],
                  let commitList = payload["commits"] as? [[String: Any]]
            else { continue }

            commits += commitList.count
            repos.insert(repoName.components(separatedBy: "/").last ?? repoName)
        }

        todayCommits = commits
        activeRepos = Array(repos)
    }
}
