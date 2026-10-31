import Foundation
func n<T>(_ value: T?) -> String { value.map { String(describing: $0) } ?? "-" }
func sl(_ slot: LiftSlot?) -> String { slot.map { "\($0.exerciseIndex).\($0.setIndex)" } ?? "-" }
func stage(_ stage: LiftSessionEngine.Stage) -> String {
    switch stage { case .warmup: return "warmup"; case .finished: return "finished"
    case .working(let s): return "work:" + sl(s)
    case .resting(let s, let end): return "rest:" + sl(s) + ":\(end)" }
}
func emit(_ tag: String, _ e: LiftSessionEngine) {
    let sets = e.sets.map { "\(sl($0.slot)):\(n($0.weightKg)):\(n($0.reps)):\(n($0.rpe)):\($0.isWarmup ? 1 : 0):\($0.startTs):\($0.endTs):\(n($0.restSec))" }.joined(separator: ";")
    print("\(tag)|\(stage(e.stage))|\(e.stageStartedAt)|\(sl(e.nextPendingSlot))|\(sl(e.upcomingSlot))|\(e.plan.map { String($0.targetSets) }.joined(separator: ","))|\(sets)")
}
let plan = [LiftPlanItem(exercise: "Squat", targetSets: 2, restSec: 60, targetRepsLow: 10, targetRpe: 8, targetWeightKg: 50, programItemId: "a"),
            LiftPlanItem(exercise: "Row", targetSets: 2, restSec: 0, targetRepsLow: 8, targetWeightKg: 40, programItemId: "b")]
var e = LiftSessionEngine(plan: plan, startTs: 100)
emit("initial",e)
e.start(LiftSlot(exerciseIndex: 1,setIndex: 1),now:110); emit("skip",e)
e.advance(now:130); emit("done",e)
e.updateSet(LiftSlot(exerciseIndex:1,setIndex:1),weightKg:42.5,reps:9,rpe:7,isWarmup:false)
e.advance(now:131); emit("same-machine",e)
print("carry|\(n(e.carry(for:LiftSlot(exerciseIndex:1,setIndex:2),lastSession:[:]).weightKg))|\(n(e.carry(for:LiftSlot(exerciseIndex:1,setIndex:2),lastSession:[:]).reps))")
e.advance(now:150); e.advance(now:151); emit("return",e)
e.addSet(toExercise:0); emit("add",e)
e.removeSet(fromExercise:0); emit("remove",e)
e.undo(); emit("undo-count",e)
e.start(LiftSlot(exerciseIndex:1,setIndex:1),now:170); emit("redo",e)
e.undo(); emit("undo-redo",e)
e.advance(now:190); emit("rest",e)
print("remaining|\(n(e.restRemaining(now:200)))|\(n(e.restRemaining(now:300)))")
e.finish(now:205); emit("finish",e)
e.undo(); emit("undo-finish",e)
for elapsed in [-1,0,1,4,5,6] { for end in [90,100,101,200] {
 print("knock|\(elapsed)|\(end)|\(LiftSessionController.isKnock(secondsSinceLastStep:elapsed,stage:.resting(LiftSlot(exerciseIndex:0,setIndex:1),endsAt:end),now:100) ? 1 : 0)")
} }
for end in [0,100,101,104,105,120] { let t = LiftSessionController.restEventTimes(endsAt:end,now:100); print("times|\(end)|\(t.warning)|\(n(t.end))") }
let controller = LiftSessionController()
controller.engine = e
controller.pendingValues = [LiftSlot(exerciseIndex:0,setIndex:2):.init(weightKg:55,reps:12,rpe:nil)]
controller.pendingWarmups = [LiftSlot(exerciseIndex:0,setIndex:3)]
for complete in [false,true] {
 let sets = controller.setsToSave(completingUnfinished:complete)
 print("save|\(complete ? 1 : 0)|" + sets.map { "\(sl($0.slot)):\(n($0.weightKg)):\(n($0.reps)):\(n($0.rpe)):\($0.isWarmup ? 1 : 0):\(n($0.startTs)):\(n($0.endTs)):\(n($0.restSec))" }.joined(separator:";"))
 let items = [LiftProgramItemRow(id:"a",deviceId:"d",programId:"p",ord:0,exercise:"Squat",targetSets:2,targetRepsLow:10,targetRepsHigh:11,targetRpe:8,targetWeightKg:50,restSec:60,note:nil), LiftProgramItemRow(id:"b",deviceId:"d",programId:"p",ord:1,exercise:"Row",targetSets:2,targetRepsLow:8,targetRepsHigh:nil,targetRpe:nil,targetWeightKg:40,restSec:0,note:nil)]
 for keep in [false,true] {
  let out = LiftSessionController.programAfterSession(sets,plan:e.plan,program:items,keepingChanges:keep,programId:"p",deviceId:"d")
  print("program|\(complete ? 1 : 0)|\(keep ? 1 : 0)|" + out.map { "\($0.id):\(n($0.targetSets)):\(n($0.targetRepsLow)):\(n($0.targetRepsHigh)):\(n($0.targetWeightKg))" }.joined(separator:";"))
 }
}
