import Vapor
import Crypto

final class UsersController: RouteCollection {
    func boot(router: Router) throws {
        // Not protected: signup
        // TODO: API key?
        let usersGroup = router.grouped("users")
        usersGroup.post("signup", use: signupHandler)
        
        // Basic protected: login
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardMiddleware = User.guardAuthMiddleware()
        let basicProtected = usersGroup.grouped(basicAuthMiddleware, guardMiddleware)
        basicProtected.post("login", use: loginHandler)
        
        // Token protected: get user, update user, avatars, search and friends group
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        let tokenProtected = usersGroup.grouped(tokenAuthMiddleware, guardMiddleware)
        tokenProtected.get(User.parameter, use: getOneHandler)
        tokenProtected.put(User.parameter, use: updateHandler)
        tokenProtected.post(User.parameter, "avatars", use: uploadAvatarHandler)
        tokenProtected.get(User.parameter, "avatars", Avatar.parameter, use: downloadAvatarHandler)
        tokenProtected.delete(User.parameter, "avatars", Avatar.parameter, use: deleteAvatarHandler)
        
        let searchGroup = tokenProtected.grouped("search")
        searchGroup.get(use: searchHandler)
        
        let friendsGroup = tokenProtected.grouped(User.parameter, "friends")
        friendsGroup.get(use: getAllFriendsHandler)
        friendsGroup.get(User.parameter, use: getOneFriendHandler)
        friendsGroup.post(use: addFriendHandler)
        friendsGroup.delete(User.parameter, use: removeFriendHandler)
    }
}

private extension UsersController {
    // TODO: Take a look at `makePublic` usage
    func getOneHandler(_ req: Request) throws -> Future<User.Public> {
        let authedUser = try req.requireAuthenticated(User.self)
        
        return try req.parameters.next(User.self).isAuthorized(by: authedUser).makePublic(on: req)
    }
    
    func updateHandler(_ req: Request) throws -> Future<User.Public> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        
        return try flatMap(to: User.Public.self, userFuture, req.content.decode(User.UpdateRequestBody.self)) { user, body in
            return user.update(with: body).save(on: req).makePublic(on: req)
        }
    }
    
    func signupHandler(_ req: Request) throws -> Future<User.Public> {
        return try req.content.decode(User.self).encryptPassword().save(on: req).flatMap(to: User.Public.self) { user in
            return try user.makeTokenFuture(on: req).save(on: req).makePublicUser(for: user, on: req)
        }
    }
    
    func loginHandler(_ req: Request) throws -> Future<User.Public> {
        let user = try req.requireAuthenticated(User.self)
        
        return try user.makeTokenFuture(on: req).save(on: req).makePublicUser(for: user, on: req)
    }
    
    // TODO: Logout handler?

    func searchHandler(_ req: Request) throws -> Future<[User.Public]> {
        let key = try req.query.get(String.self, at: "q")

        // Wildcards: https://www.tutorialspoint.com/postgresql/postgresql_like_clause.htm
        return User.makeSearchQueryFuture(using: "%\(key)%", on: req).makePublics(on: req)
    }
    
    func getAllFriendsHandler(_ req: Request) throws -> Future<[User.Public]> {
        let authedUser = try req.requireAuthenticated(User.self)
        
        return try req.parameters.next(User.self).isAuthorized(by: authedUser).makeAllFriends(on: req).makePublics(on: req)
    }
    
    func getOneFriendHandler(_ req: Request) throws -> Future<User.Public> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        let personFuture = try req.parameters.next(User.self)
        
        return flatMap(to: User.Public.self, userFuture, personFuture) { user, person in
            return user.makeHasFriendshipFuture(with: person, on: req).flatMap(to: User.Public.self) { isFriend in
                guard isFriend else { throw Abort(.notFound) }
                
                return try person.makePublicFuture(on: req)
            }
        }
    }
    
    func addFriendHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        let queryPersonFuture = try req.content.decode(AddFriendBody.self).flatMap(to: User?.self) { body in
            return User.makeSingleQueryFuture(using: body.personID, on: req)
        }
        
        return flatMap(to: HTTPStatus.self, userFuture, queryPersonFuture) { user, person in
            guard let unwrappedPerson = person else { throw Abort(.badRequest) }
            
            return user.makeHasFriendshipFuture(with: unwrappedPerson, on: req).flatMap(to: HTTPStatus.self) { isFriend in
                guard isFriend else { return user.makeAddFriendshipFuture(to: unwrappedPerson, on: req) }
                
                return Future.done(on: req).transform(to: .created)
            }
        }
    }
    
    func removeFriendHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        let personFuture = try req.parameters.next(User.self)
        
        return flatMap(to: HTTPStatus.self, userFuture, personFuture) { user, person in
            return user.makeHasFriendshipFuture(with: person, on: req).flatMap(to: HTTPStatus.self) { isFriend in
                guard isFriend else { return Future.done(on: req).transform(to: .noContent) }
                
                return user.makeRemoveFriendshipFuture(to: person, on: req)
            }
        }
    }
    
    func uploadAvatarHandler(_ req: Request) throws -> Future<Asset> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        let fileFuture = try req.content.decode(File.self) // There is a limitation of request size (1 MB by default)
        
        return flatMap(to: Asset.self, userFuture, fileFuture) { user, file in
            return try user.makeAvatarFuture(with: file, on: req).makeAsset()
        }
    }
    
    func downloadAvatarHandler(_ req: Request) throws -> Future<HTTPResponse> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        let avatarFuture = userFuture.flatMap(to: Avatar.self) { user in
            return try req.parameters.next(Avatar.self).isBelong(to: user)
        }
        
        return avatarFuture.makeDownloadHTTPResponse()
    }
    
    func deleteAvatarHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let authedUser = try req.requireAuthenticated(User.self)
        let userFuture = try req.parameters.next(User.self).isAuthorized(by: authedUser)
        let avatarFuture = userFuture.flatMap(to: Avatar.self) { user in
            return try req.parameters.next(Avatar.self).isBelong(to: user)
        }
        
        return avatarFuture.deleteFile(on: req).delete(on: req).transform(to: .noContent)
    }
}
