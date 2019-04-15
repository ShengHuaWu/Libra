import Foundation

enum Endpoint {
    case signUp
    case login
}

extension Endpoint {
    var url: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "Base URL") as? String,
            let baseURL = URL(string: urlString) else {
                preconditionFailure("Unable to load base url from info.plist")
        }
        
        switch self {
        case .signUp: return baseURL.appendingPathComponent("users/signup")
        case .login: return  baseURL.appendingPathComponent("users/login")
        }
    }
}