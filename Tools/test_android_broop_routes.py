"""Keep the Android port's destination inventory tied to the iOS Broop router."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class BroopRouteParityTests(unittest.TestCase):
    def test_every_ios_destination_has_a_registered_android_route_and_device_case(self):
        swift = (ROOT / "StrandiOS/Broop/BroopRouter.swift").read_text()
        cases = swift.split("enum BroopScreen:", 1)[1].split("var id:", 1)[0]
        destinations = set()
        for line in cases.splitlines():
            if not line.strip().startswith("case "):
                continue
            line = re.sub(r"\([^)]*\)", "", line.strip()[5:])
            destinations.update(part.strip() for part in line.split(","))
        kotlin = (ROOT / "android/app/src/main/java/com/noop/ui/BroopAppRoot.kt").read_text()
        mapping = kotlin.split("val swiftDestinations = mapOf(", 1)[1].split("\n    )", 1)[0]
        entries = re.findall(r'"([^"]+)" to "([^"]+)"', mapping)
        self.assertEqual(len(entries), len(dict(entries)), "duplicate Swift destination")
        self.assertEqual(destinations, set(dict(entries)))
        smoke = (ROOT / "android/app/src/androidTest/java/com/noop/ui/BroopPortSmokeTest.kt").read_text()
        for source, route in entries:
            with self.subTest(source=source):
                self.assertIn(f'composable("{route}")', kotlin)
                concrete = route.replace("{key}", "hrv")
                self.assertIn(f'"{concrete}"', smoke)


if __name__ == "__main__":
    unittest.main()
