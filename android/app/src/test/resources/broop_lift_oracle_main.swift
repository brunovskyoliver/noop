import Foundation
let csv = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let result = try! LiftProgramSheetImporter.parse(data:csv)
func n<T>(_ x:T?)->String { x.map{String(describing:$0)} ?? "nil" }
for p in result.programs { print("PROGRAM|"+p.name+"|"+n(p.note)); for l in p.lines { print([l.exercise,l.primaryMuscle?.rawValue ?? "nil",l.secondaryMuscles.map(\.rawValue).joined(separator:","),n(l.targetSets),n(l.targetReps),n(l.targetWeightKg),n(l.targetMaxRpe),n(l.restSec),n(l.note)].joined(separator:"|")) } }
for warning in result.warnings { print("WARNING|"+warning) }
