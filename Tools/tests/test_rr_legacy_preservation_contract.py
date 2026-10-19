"""Source contracts for cross-platform legacy WHOOP 5 score preservation."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SWIFT_ENGINE = ROOT / "Strand/Data/IntelligenceEngine.swift"
SWIFT_HEALTHSPAN = ROOT / "Strand/Data/IntelligenceEngine+Healthspan.swift"
SWIFT_HEALTHSPAN_REPOSITORY = ROOT / "Strand/Data/Repository+Healthspan.swift"
ANDROID_PERSISTENCE = (
    ROOT
    / "android/app/src/main/java/com/noop/analytics/IntelligencePersistence.kt"
)


class LegacyScorePreservationContractTests(unittest.TestCase):
    def test_swift_protects_only_the_persisted_and_displayed_copy(self) -> None:
        source = SWIFT_ENGINE.read_text()
        protection_start = source.index("// Apply the exact snapshot only after")
        persistence_end = source.index("markPostLoopPhase(\"persist\")", protection_start)
        persistence = source[protection_start:persistence_end]

        self.assertIn("var persistedDailies = dailies", persistence)
        self.assertIn("for index in persistedDailies.indices", persistence)
        self.assertIn("let fresh = persistedDailies[index]", persistence)
        self.assertIn("persistedDailies[index] = fresh.with(avgHrv: snapshot.avgHrv", persistence)
        self.assertIn("recovery: snapshot.recovery", persistence)
        self.assertIn("respRateBpm: snapshot.respRateBpm", persistence)
        self.assertIn("avgSdnn: snapshot.avgSdnn", persistence)
        self.assertIn("for daily in persistedDailies", persistence)
        # Persistence may window the protected copy per day (preserveUnscoredHistory) or write it
        # whole. Pin that BOTH branches still read only persistedDailies, not the raw `dailies`.
        self.assertIn("let dailiesByDay = Dictionary(grouping: persistedDailies, by: \\.day)", persistence)
        self.assertIn("? dailiesByDay[from, default: []] : persistedDailies", persistence)
        self.assertNotIn("dailies[index] = fresh.with(avgHrv:", persistence)

        derivations = source[persistence_end:]
        self.assertIn("for d in dailies { faGateByDay[d.day] = d }", derivations)
        self.assertIn("let faGate7 = Array(faGateByDay.values.sorted", derivations)
        self.assertIn("gateDays: faGate7", derivations)
        self.assertRegex(
            derivations,
            r"await Self\.writeWeeklyHealthspan\([^)]*\bfresh:\s*dailies\)",
        )
        self.assertNotIn("persistedDailies", derivations)

        healthspan = SWIFT_HEALTHSPAN.read_text()
        self.assertRegex(
            healthspan,
            r"await repo\.healthspan\([^)]*\bfresh:\s*fresh\)",
        )
        repository = SWIFT_HEALTHSPAN_REPOSITORY.read_text()
        self.assertRegex(
            repository,
            r"await healthspanHistory\([\s\S]*?\bfresh:\s*fresh\)",
        )
        self.assertIn(
            "for d in fresh where d.day >= from && d.day <= to { byDay[d.day] = d }",
            repository,
        )

    def test_android_also_protects_a_separate_persistence_copy(self) -> None:
        source = ANDROID_PERSISTENCE.read_text()
        preparation_start = source.index("suspend fun prepareComputedWindow")
        preparation_end = source.index("fun scoreProvenance", preparation_start)
        preparation = source[preparation_start:preparation_end]

        self.assertIn("val mutableDailies = dailies.toMutableList()", preparation)
        self.assertIn(
            "repo, computedId, from, to, mutableDailies, ownerByDay,",
            preparation,
        )
        self.assertIn("dailies = mutableDailies", preparation)
        self.assertIn("respRateBpm = existing.respRateBpm", source)
        self.assertIn("avgSdnn = existing.avgSdnn", source)


if __name__ == "__main__":
    unittest.main()
