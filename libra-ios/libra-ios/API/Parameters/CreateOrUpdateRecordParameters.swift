import Foundation

struct CreateOrUpdateRecordParameters: Encodable {
    enum CodingKeys: String, CodingKey {
        case title
        case note
        case date
        case mood
        case amount
        case currency
        case companionIDs = "companion_ids"
    }
    
    let id: Int?
    let title: String
    let note: String
    let date: Date
    let mood: String
    let amount: Double
    let currency: String
    let companionIDs: [Int]
    
    init(id: Int?, title: String, note: String, date: Date, mood: Record.Mood, amount: Double, currency: Record.Currency, companions: [Companion]) {
        self.id = id
        self.title = title
        self.note = note
        self.date = date
        self.mood = mood.rawValue
        self.amount = amount
        self.currency = currency.rawValue
        self.companionIDs = companions.map { $0.id }
    }
}