import AirCodeClient
import Foundation

@main
struct AirCodeIntegrationSmoke {
    static func main() async throws {
        let settings = ConnectionSettings.developmentDefault
        guard let url = URL(string: settings.serverURL) else {
            throw AirCodeAPIError.invalidURL
        }
        _ = AirCodeAPI(baseURL: url, token: settings.token)
        print("AirCodeIntegrationSmoke: client bootstrapped")
    }
}
