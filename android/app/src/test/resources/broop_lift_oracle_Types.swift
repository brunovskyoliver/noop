import Foundation
enum WhoopStore { static let maxProgramNoteLength = 120; static let maxExerciseNoteLength = 200 }
enum XlsxSheet { struct Sheet { var headerKeys:Set<String>; var rows:[[String:String]] }; static func sheets(from:Data) throws -> [Sheet] { [] } }
