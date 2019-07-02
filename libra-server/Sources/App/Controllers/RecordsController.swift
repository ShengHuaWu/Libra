import Vapor

final class RecordsController: RouteCollection {
    func boot(router: Router) throws {
        let recordsGroup = router.grouped("records")
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        let guardMiddleware = User.guardAuthMiddleware()
        let tokenProtected = recordsGroup.grouped(tokenAuthMiddleware, guardMiddleware)
        tokenProtected.get(use: getAllFromUserHandler)
        tokenProtected.get(Record.parameter, use: getOneHandler)
        tokenProtected.post(use: createHandler)
        tokenProtected.put(Record.parameter, use: updateHandler)
        tokenProtected.delete(Record.parameter, use: deleteHandler)
        tokenProtected.post(Record.parameter, "attachments", use: uploadAttachmentHandler)
        tokenProtected.get(Record.parameter, "attachments", Attachment.parameter, use: downloadAttachmentHandler)
        tokenProtected.delete(Record.parameter, "attachments", Attachment.parameter, use: deleteAttachmentHandler)
    }
}

private extension RecordsController {
    func getAllFromUserHandler(_ req: Request) throws -> Future<[Record.Intact]> {
        return try req.requireAuthenticated(User.self).makeAllUndeletedRecordsFuture(on: req).makeIntacts(on: req)
    }
    
    func getOneHandler(_ req: Request) throws -> Future<Record.Intact> {
        let user = try req.requireAuthenticated(User.self)
        
        return try req.parameters.next(Record.self)
            .map { try authorize(user, hasAccessTo: $0) }
            .flatMap { try convert($0, toIntactOn: req) }
    }
    
    func createHandler(_ req: Request) throws -> Future<Record.Intact> {
        let user = try req.requireAuthenticated(User.self)
        let bodyFuture = try req.content.decode(json: Record.RequestBody.self, using: .custom(dates: .millisecondsSince1970))
        let recordFuture = try bodyFuture.makeRecord(for: user).save(on: req)
        let companionsFuture = bodyFuture.makeQueuyCompanions(on: req)
        
        return flatMap(to: Record.Intact.self, recordFuture, companionsFuture) { record, companions in
            return try record.makeAddCompanionsFuture(companions, on: req)
        }
    }
    
    func updateHandler(_ req: Request) throws -> Future<Record.Intact> {
        let user = try req.requireAuthenticated(User.self)
        let recordFuture = try req.parameters.next(Record.self)
            .map { try authorize(user, hasAccessTo: $0) }
        let bodyFuture = try req.content.decode(json: Record.RequestBody.self, using: .custom(dates: .millisecondsSince1970))
        
        return flatMap(to: Record.Intact.self, recordFuture, bodyFuture) { record, body in
            let updateRecordFuture = record.update(with: body).save(on: req).flatMap { removeAllCompanions(of: $0, on: req) }
            let companionsFuture = User.makeQueryFuture(using: body.companionIDs, on: req)
            
            return flatMap(to: Record.Intact.self, updateRecordFuture, companionsFuture) { _, companions in
                return try record.makeAddCompanionsFuture(companions, on: req)
            }
        }
    }
    
    func deleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        
        return try req.parameters.next(Record.self)
            .map { try authorize(user, hasAccessTo: $0) }
            .flatMap { mark($0, asDeletedOn: req) }
            .transform(to: .noContent)
    }
    
    func uploadAttachmentHandler(_ req: Request) throws -> Future<Asset> {
        let user = try req.requireAuthenticated(User.self)
        let recordFuture = try req.parameters.next(Record.self)
            .map { try authorize(user, hasAccessTo: $0) }
        let fileFuture = try req.content.decode(File.self) // There is a limitation of request size (1 MB by default)
        
        return flatMap(to: Asset.self, recordFuture, fileFuture) { record, file in
            return try record.makeAttachmentFuture(with: file, on: req).makeAsset()
        }
    }
    
    func downloadAttachmentHandler(_ req: Request) throws -> Future<HTTPResponse> {
        let user = try req.requireAuthenticated(User.self)
        let recordFuture = try req.parameters.next(Record.self)
            .map { try authorize(user, hasAccessTo: $0) }
        let attachmentFuture = recordFuture.flatMap(to: Attachment.self) { record in
            return try req.parameters.next(Attachment.self).isAttached(to: record)
        }
        
        return attachmentFuture.makeDownloadHTTPResponse()
    }
    
    func deleteAttachmentHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let recordFuture = try req.parameters.next(Record.self)
            .map { try authorize(user, hasAccessTo: $0) }
        let attachmentFuture = recordFuture.flatMap(to: Attachment.self) { record in
            return try req.parameters.next(Attachment.self).isAttached(to: record)
        }
        
        return attachmentFuture.deleteFile(on: req).delete(on: req).transform(to: .noContent)
    }
}
