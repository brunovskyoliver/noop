"""Sleep need has one resolver: no app screen or pass may estimate it for itself."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class SleepNeedSingleResolverTest(unittest.TestCase):
    def test_only_the_resolver_calls_the_estimator(self):
        callers = set()
        for folder in ("Strand", "StrandiOS", "StrandiOSShared", "StrandiOSWidgets"):
            for path in (ROOT / folder).rglob("*.swift"):
                if "personalizedNeedHours(" in path.read_text(encoding="utf-8"):
                    callers.add(path.relative_to(ROOT).as_posix())
        self.assertEqual(callers, {"Strand/Data/SleepRules.swift"})


if __name__ == "__main__":
    unittest.main()
