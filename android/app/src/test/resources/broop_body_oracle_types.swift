// Type scaffolding for standalone compilation of the unmodified Swift engines.
// Calendar/zone helpers are copied from the repository; tested engines remain original files.
import Foundation
public enum StressMonitor {
 public static let epochSeconds = 300
 public static let highFloor = 2.0
 public static let mediumFloor = 1.0
 public static let sleepTypicalLevel = 0.4
 public enum EpochState { case sleep, waking, activity, noData }
 public struct Epoch { public let startTs:Int; public let state:EpochState; public let level:Double?; public let meanHR:Double?; public let rmssd:Double?; public let inMainSleep:Bool }
 public struct Reference { public let personal:Bool }
 public struct DayResult { public let day:String; public let epochs:[Epoch]; public let wake:Reference?; public let sleep:Reference? }
}
public enum VitalityEngine {
    static func epochDay(_ s: String) -> Int? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y0 = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
public enum StrainScorer {
 static let edwardsZones:[(Double,Int)] = [(90,5),(80,4),(70,3),(60,2),(50,1)]
    static func zoneWeight(_ bpm: Double, restingHR: Double, hrReserve: Double) -> Int {
        let pct = (bpm - restingHR) / hrReserve * 100.0
        for (threshold, weight) in edwardsZones where pct >= threshold { return weight }
        return 0
    }
}
public enum StrainTarget { public static func edwardsTrimpPerMinute(bpm:Double, restingHR:Double,maxHR:Double)->Double { guard maxHR > restingHR else { return 0 }; return Double(StrainScorer.zoneWeight(bpm,restingHR:restingHR,hrReserve:maxHR-restingHR)) } }
