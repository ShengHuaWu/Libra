// Use this type to persist friends (people)
struct FriendsStorage {
    var save = { try saveEntity($0, as: .friends) }
    var fetch = { try fetchEntity(as: .friends) }
    var delete = { try deleteEntity(as: .friends) }
    // TODO: Save, fetch, and delete changing actions
}