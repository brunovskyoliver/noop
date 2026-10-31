import Foundation
func f(_ x:Double?) -> String { x.map { String(format:"%.12f",$0) } ?? "nil" }
let heart = EnergyReservoir.HeartProfile(restingHR:50,maxHR:190)
for start in [0.0,30,50,99,100] {
 for (state,level,hr,run) in [(StressMonitor.EpochState.sleep,0.4,60.0,0),(.sleep,1.2,60.0,0),(.waking,0.5,60.0,2),(.waking,2.5,60.0,0),(.activity,0,148.0,0),(.noData,0,60.0,0)] {
  let ep=StressMonitor.Epoch(startTs:0,state:state,level:level,meanHR:hr,rmssd:nil,inMainSleep:false)
  let v=EnergyReservoir.step(level:start,epoch:ep,restRun:run,heart:heart)
  print([f(v.level),v.kind.rawValue,f(v.charge),f(v.stress),f(v.activity),f(v.baseline)].joined(separator:"|"))
 }
}
let eps=(0..<288).map { i -> StressMonitor.Epoch in
 let state:StressMonitor.EpochState = i < 96 ? .sleep : (i < 108 ? .activity : (i%17 == 0 ? .noData : .waking))
 return StressMonitor.Epoch(startTs:i*300,state:state,level:state == .sleep ? 0.6 : (i%3 == 0 ? 0.5 : 1.5),meanHR:148,rmssd:nil,inMainSleep:i<96)
}
let stress=StressMonitor.DayResult(day:"2026-10-19",epochs:eps,wake:.init(personal:true),sleep:.init(personal:true))
let result=EnergyReservoir.day(stress,startLevel:40,heart:heart)!
print("DAY|"+result.summary.storedPairs.map { $0.key+"="+f($0.value) }.joined(separator:"|"))
print("PROJECT|"+f(EnergyReservoir.projectNow(level:50,minutesSinceLastEpoch:100,liveLevel:2.5,heart:heart)))
var pss:[String]=[]
for a in 0...4 { for b in 0...4 { for c in 0...4 { for d in 0...4 { pss.append(String(MindCheckIn.score(.pss4,answers:[a,b,c,d])!)) } } } }
print("PSS|"+pss.joined(separator:","))
let days=(0..<40).map { i -> MindDay in
 let day=MindEngine.shift("2026-09-10",by:i)!
 return MindDay(day:day,highStressMin:Double(10+i*3),lowStressMin:Double(250-i*2),scoredMin:600,
   sleepStressPct:i%5 == 0 ? nil : Double(i%30),rest:Double(55+i%20),charge:Double(30+i%40))
}
for date in ["2026-09-15","2026-09-23","2026-10-01","2026-10-19"] {
 let r=ResilienceEngine.compute(days:days,asOf:date)
 let c=CumulativeStressEngine.compute(days:days,asOf:date)
 print("MIND|"+date+"|"+f(r?.score)+"|"+f(r?.highShare)+"|"+f(r?.lowShare)+"|"+f(r?.nightRecovery)+"|"+(r?.trend?.rawValue ?? "nil")+"|"+f(c?.score)+"|"+f(c?.daytimeLoad)+"|"+f(c?.sleepLoad)+"|"+f(c?.recoveryLoad)+"|"+(c?.trend?.rawValue ?? "nil"))
}
let scores=(0..<6).map { (day:MindEngine.shift("2026-03-01",by:$0*28)!,value:Double($0)) }
let signal=(0..<180).map { (day:MindEngine.shift("2026-02-01",by:$0)!,value:Double($0*2+13)) }
let correlation=MindCheckIn.correlate(scores:scores,signal:signal,windowDays:30)
print("CORR|"+f(correlation?.r)+"|"+String(correlation?.n ?? 0))
for (zone,date,offset) in [("Europe/Bratislava","2026-10-24",-240),("America/Los_Angeles","2026-07-01",120),("Pacific/Auckland","2026-10-19",-720)] {
 var cal=Calendar(identifier:.gregorian); cal.timeZone=TimeZone(identifier:zone)!
 let parts=date.split(separator:"-").map{Int($0)!}
 let instant=cal.date(from:DateComponents(year:parts[0],month:parts[1],day:parts[2]))!
 let trip=JetLagTrip(travelDate:instant,originTimeZone:zone,destinationOffsetMinutes:offset,bedMinute:1410,wakeMinute:450)
 guard let p=trip.resolve() else {print("TRIP|nil");continue}
 print("TRIP|"+p.direction.rawValue+"|"+p.days.map { day in
  let c=cal.dateComponents([.year,.month,.day],from:day.date)
  return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)+"|"+[day.timing.targetSleepHour,day.timing.targetWakeHour,day.timing.brightLightStartHour,day.timing.brightLightEndHour,day.timing.dimFromHour].map{f($0)}.joined(separator:"|")
 }.joined(separator:";"))
}
