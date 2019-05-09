import Foundation
@testable import libra_ios

extension DataTaskResponseHandler {
    static let mock = DataTaskResponseHandler(unwrapData: { _, _, _ in
        return try JSONEncoder().encode(ErrorResponse(error: true, reason: "This is an error response"))
    })
}

extension WebService {
    static let mock = WebService(users: .mock, records: .mock, friends: .mock)
}

extension UsersWebService {
    static let mock = UsersWebService(
        signUp: { _ in return .empty },
        logIn: { _ in return .empty },
        getUser: { _ in return .empty },
        updateUser: { _ in return .empty },
        searchUsers: { _ in return .empty})
}

extension RecordsWebService {
    static let mock = RecordsWebService(
        getRecords: { return .empty },
        getRecord: { _ in return .empty },
        createRecord: { _ in return .empty },
        updateRecord: { _ in return .empty },
        deleteRecord: { _ in return .empty })
}

extension FriendsWebService {
    static let mock = FriendsWebService(
        getAllFriends: { _ in return .empty },
        addFriendship: { _ in return .empty },
        getFriend: { _ in return .empty },
        removeFriendship: { _ in return .empty })
}

extension Storage {
    static let mock = Storage(
        saveToken: { _ in throw PersistingError.noEntity },
        fetchToken: { throw PersistingError.noEntity },
        deleteToken: { throw PersistingError.noEntity })
}

extension Environment {
    static let mock = Environment(
        urlSession: { return MockURLSessionInterface() },
        dataTaskResponseHandler: .mock,
        webService: .mock,
        storage: .mock)
}
