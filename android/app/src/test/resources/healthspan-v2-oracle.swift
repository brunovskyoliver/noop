// Reproduce: copy this driver to main.swift; swiftc -O VitalityEngine.swift VitalityWindow.swift main.swift -o oracle; ./oracle
import Foundation
enum HRVStatus {
    static func dayString(_ z0: Int) -> String {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

import Foundation
func f(_ x: Double) -> String { String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), x == 0 ? 0 : x) }
func digest(_ s: String) -> String {
    var h: UInt64 = 14695981039346656037
    for u in s.utf16 { h = (h ^ UInt64(u)) &* 1099511628211 }
    return String(h, radix: 16)
}
let ages: [Double] = [18, 20, 29.5, 30, 40, 55, 60, 72.25, 100]
let sexes = ["male", "female", "", "nonbinary", "MALE"]
let samples: [[Double]] = [
    [0,3.9,4,5.5,6.999,7,8,9,10,14],
    [-1,0,59.9,60,65,70,75.1,80.9,85.25,90,100,140],
    [-2,0,7,9.5,10,15,53.6,100,150,300,600,900],
    [-2,0,7,9.5,10,15,53.6,100,150,300,600,900],
    [-2,0,7,9.5,10,15,40,53.6,60,100,120,300],
    [0,1999,2000,3553,5801,7842,8000,10901,15000],
    [0,10,18,35,45,70,100],
    [0,39,40,55,60,64,85,100,110],
    [0,39,40,50,67,70,80,90,97,100]
]
for (idx, factor) in VitalityEngine.Factor.allCases.enumerated() {
    var lines: [String] = []
    for age in ages { for sex in sexes { for value in samples[idx] {
        lines.append([f(age),sex,f(value),f(VitalityEngine.target(factor, age: age, sex: sex)),f(VitalityEngine.lnHazard(factor, value: value, age: age, sex: sex))].joined(separator: "|"))
    } } }
    print("curve|\(factor.rawValue)|\(lines.count)|\(digest(lines.joined(separator: "\n")))")
}
var neutral = VitalityEngine.Inputs(chronoAge: 40, sex: "male")
for factor in VitalityEngine.Factor.allCases { neutral.set(factor, VitalityEngine.target(factor, age: 40, sex: "male")) }
let scenarios: [VitalityEngine.Inputs] = [
    neutral,
    .init(chronoAge: 40, sex: "male", sleepHours:8, sleepConsistency:90, zone13MinPerWeek:400, zone45MinPerWeek:60, strengthMinPerWeek:120, steps:11000, vo2max:55, restingHR:50, leanMassPct:85),
    .init(chronoAge:65,sex:"female",sleepHours:4,sleepConsistency:55,zone13MinPerWeek:0,zone45MinPerWeek:0,strengthMinPerWeek:0,steps:1500,vo2max:10,restingHR:110,leanMassPct:35),
    .init(chronoAge:40,sex:"male",sleepHours:7,steps:8000,restingHR:60),
    .init(chronoAge:0,sleepHours:7,steps:8000,restingHR:60),
    .init(chronoAge:40,sleepHours:7,steps:8000),
    .init(chronoAge:18,sex:"male",sleepHours:9,sleepConsistency:100,zone13MinPerWeek:900,zone45MinPerWeek:100,strengthMinPerWeek:300,steps:30000,vo2max:100,restingHR:30,leanMassPct:100),
    .init(chronoAge:100,sex:"female",sleepHours:2,sleepConsistency:0,zone13MinPerWeek:0,zone45MinPerWeek:0,strengthMinPerWeek:0,steps:0,vo2max:0,restingHR:150,leanMassPct:0)
]
for (index,input) in scenarios.enumerated() {
    guard let r = VitalityEngine.compute(input) else { print("result|\(index)|nil"); continue }
    print("result|\(index)|\(f(r.bodyAge))|\(f(r.ageDelta))|\(f(r.vitality))|\(r.factorsUsed)")
    print("impacts|\(index)|"+r.impacts.map { "\($0.factor.rawValue):\(f($0.years)):\(f($0.adjustment)):\($0.isMissing ? 1 : 0)" }.joined(separator:","))
}
let end=VitalityEngine.epochDay("2026-10-18")!
func history(_ count:Int=200)->[VitalityEngine.Day] {
    (0..<count).compactMap { i in
        if i % 17 == 5 { return nil }
        return VitalityEngine.Day(day:HRVStatus.dayString(end-count+1+i),restingHR:Double(55+i%9),sleepHours:6.2+Double(i%13)/7,sleepConsistency:Double(60+i%35),steps:Double(6000+(i*347)%5100),vo2max:i%7==0 ? 45+Double(i%5):nil,measuredVO2max:i==150 ? 41:nil,zone13Min:i%3==0 ? 32:0,zone45Min:i%5==0 ? 6:0,strengthMin:i%8==0 ? 45:0,hasRecovery:true)
    }
}
func printWindow(_ label:String,_ days:[VitalityEngine.Day],_ lean:[VitalityEngine.LeanMassPoint]=[]) {
    guard let h=VitalityEngine.healthspan(days:days,leanMass:lean,asOf:"2026-10-18",chronoAge:38,sex:"female") else {print("window|\(label)|nil");return}
    print("window|\(label)|\(f(h.current.bodyAge))|\(f(h.current.vitality))|\(f(h.projected.bodyAge))|\(f(h.paceOfAging))|\(h.recoveriesLast31)|\(h.coveredDays)")
    for (name,input) in [("long",h.longInputs),("recent",h.recentInputs)] {
        print("inputs|\(label)|\(name)|"+VitalityEngine.Factor.allCases.map {input.value($0).map(f) ?? "nil"}.joined(separator:","))
    }
}
printWindow("base",history())
printWindow("lean",history(),[.init(day:HRVStatus.dayString(end-300),pct:78),.init(day:HRVStatus.dayString(end-100),pct:72),.init(day:HRVStatus.dayString(end-20),pct:74),.init(day:HRVStatus.dayString(end+1),pct:90)])
printWindow("carry",history(),[.init(day:HRVStatus.dayString(end-300),pct:78)])
printWindow("staleLean",history(),[.init(day:HRVStatus.dayString(end-365),pct:78)])
for count in [20,21,31] { printWindow("gate\(count)",(0..<count).map {i in .init(day:HRVStatus.dayString(end-i),restingHR:60,sleepHours:7,steps:8000,hasRecovery:true)}) }
for day in ["1970-01-01","1969-12-31","2000-03-01","2026-10-18","2026-10-19","2026-10-24","2026-10-25","garbage"] {print("sunday|\(day)|\(VitalityEngine.sundayKey(onOrBefore:day) ?? "nil")")}
print("sundays|"+VitalityEngine.sundays(from:"2026-09-19",to:"2026-10-19").joined(separator:","))
for sport in ["Strength Training","Barre-3","F45 Training","baby/toddler wearing","BABY WEARING","Running","Core training"] { print("sport|\(sport)|\(VitalityEngine.isStrengthSport(sport) ? 1:0)") }
for json in ["{\"z1\":12.5,\"z2\":30.1,\"z3\":20,\"z4\":7.3,\"z5\":1.1}","{\"z1\":true,\"zone4\":50}","{\"z1\":\"12\"}","not json"] { let value=VitalityEngine.zoneMinutes(zonesJSON:json,durationS:2873);print("zones|"+(value.map{f($0.z13)+","+f($0.z45)} ?? "nil")) }
