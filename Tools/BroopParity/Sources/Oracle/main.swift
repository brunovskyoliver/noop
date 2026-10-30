import Foundation
import StrandAnalytics
import WhoopProtocol
func f(_ x: Double?) -> String { x.map { String(format: "%.9f", $0) } ?? "nil" }
for delta in [-40.0,-15,-1,0,7.5,15,30,80] { print("wake \(delta) \(f(StressMonitor.wakeLevel(meanHR:60+delta, floorHR:60)))") }
let night = StressMonitor.NightAggregate(hr:52,hrSpread:2,lnRMSSD:log(60),lnRMSSDSpread:0.2)
for z in [-8.0,-2,0,0.5,1,2,3,8] { print("sleep \(z) \(f(StressMonitor.sleepLevel(z:z)))") }
for hr in [48.0,52,56,70] { for rr: Double? in [nil,30,60,90] { print("z \(hr) \(f(rr)) \(f(StressMonitor.sleepZ(meanHR:hr,rmssd:rr,ref:night)))") } }
for count in [0,3,4,14,18] {
 let floors = (0..<count).map { Optional(Double(50+$0)) }
 let ref=StressMonitor.wakeReference(priorFloors:floors,todayFloor:70)
 print("ref \(count) \(f(ref?.floorHR)) \(ref?.personal == true) \(ref?.days ?? -1)")
}
let day0=1700006400
for bpm in [52,60,68,75,90] {
 let samples=(0..<10800).map { HRSample(ts:day0+$0,bpm:($0 < 3600 ? 52 : bpm)) }
 let main=StressMonitor.Interval(start:day0,end:day0+3600)
 let activity=StressMonitor.Interval(start:day0+7200,end:day0+7500)
 let input=StressMonitor.DayInput(day:"2023-11-15",dayStart:day0,dayEnd:day0+10800,tzOffsetSeconds:0,hr:samples,rr:[],gravity:[],sleepWindows:[main],mainSleep:main,activityWindows:[activity])
 let result=StressMonitor.analyzeDay(input,priorFloors:Array(repeating:60,count:14),priorNights:Array(repeating:night,count:14))
 let summary=result.summary
 let states=result.epochs.map { $0.state.rawValue }.joined(separator:",")
 print("day \(bpm) \(f(summary.meanLevel)) \(summary.highMin) \(summary.medMin) \(summary.lowMin) \(summary.scoredMin) \(f(summary.sleepStressPct)) \(states)")
}
for hours in [0.0,5.5,8,10] { for c: Double? in [nil,0.25,0.8,1] { for stress: Double? in [nil,0,5,30,100] {
 let p=AnalyticsEngine.RestV2.parts(tstSeconds:hours*3600,efficiency:0.9,needHours:8,consistency:c,sleepStressPct:stress)
 print("rest \(hours) \(f(c)) \(f(stress)) \(f(AnalyticsEngine.RestV2.composite(p)))")
} } }
