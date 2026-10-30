"""Compile current production Swift engine and extracted pure controller methods, then emit Kotlin literals."""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[5]
controller=(root/'Strand/Data/LiftSessionController.swift').read_text()
def block(text, token):
 start=text.index(token); begin=text.index('{',start); depth=1; end=begin+1
 while depth:
  if text[end]=='{':depth+=1
  if text[end]=='}':depth-=1
  end+=1
 return text[start:end]
with tempfile.TemporaryDirectory(prefix='broop-lift-oracle-',dir=os.environ.get('TMPDIR','/tmp')) as temporary:
 folder=Path(temporary)
 engine=(root/'Strand/Data/LiftSessionEngine.swift').read_text().replace('import WhoopStore','')
 muscle=(root/'Packages/WhoopStore/Sources/WhoopStore/LiftMuscle.swift').read_text()
 row=block((root/'Packages/WhoopStore/Sources/WhoopStore/LiftLogStore.swift').read_text(),'public struct LiftProgramItemRow:')
 row=row.replace(block(row,'static func decode('),'')
 methods=['struct PendingSetValues:','struct FinishedSet:','struct SetCountChange:',
  'func values(of slot:','private func lastSessionSets(for slot:', 'func carry(for slot:',
  'func setsToSave(completingUnfinished:', 'static func anyPerformed(', 'static func setCountChanges(',
  'static func applyingHeaviestSets(', 'private static func isHeavier(', 'static func programAfterSession(',
  'static func applying(', 'static func isKnock(', 'static func restEventTimes(']
 scaffold='class LiftSessionController { var engine: LiftSessionEngine?; var pendingValues: [LiftSlot:PendingSetValues] = [:]; var pendingWarmups: Set<LiftSlot> = []; var lastSession: [String:[Int:LiftSetCarry]] = [:]; static let strapKnockWindowSec=5; static let restWarningLeadSec=5;\n'
 scaffold+='\n'.join(block(controller,method) for method in methods)+'\n}'
 metrics=(root/'Packages/StrandAnalytics/Sources/StrandAnalytics/LiftMetrics.swift').read_text()
 scaffold+='\nenum LiftMetrics {'+block(metrics,'public static func isPerformed(')+'}'
 (folder/'Types.swift').write_text('import Foundation\n'+muscle+'\n'+row+'\n'+scaffold)
 (folder/'Engine.swift').write_text(engine)
 (folder/'main.swift').write_text((Path(__file__).parent/'broop_lift_session_oracle_main.swift').read_text())
 subprocess.run(['swiftc','-O',str(folder/'Types.swift'),str(folder/'Engine.swift'),str(folder/'main.swift'),'-o',str(folder/'oracle')],check=True)
 subprocess.run([str(folder/'oracle')],check=True)
