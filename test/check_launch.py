"""Read-only checks for launch data that Foundry's file permissions do not expose.

Run with Python 3.9+ and the project's installed forge: python3 test/check_launch.py
No packages, RPC, FFI, environment changes, or configuration edits are required.
"""

import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate manifest key: " + key)
        result[key] = value
    return result


class LaunchBriefTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.launch = json.loads(
            (ROOT / "launch.json").read_text(), object_pairs_hook=unique_object
        )

    def test_exact_top_level_schema_and_no_app_contracts(self):
        self.assertEqual(
            set(self.launch),
            {"kind", "token", "contracts", "pool", "economics", "notes"},
        )
        self.assertEqual(self.launch["kind"], "custom_token")
        self.assertEqual(self.launch["contracts"], [])
        self.assertIsInstance(self.launch["notes"], str)

    def test_token_identity_supply_and_no_constructor_parameters(self):
        self.assertEqual(self.launch["token"], {
            "contract": "PROOFToken",
            "name": "Proof Network",
            "symbol": "PROOF",
            "decimals": 18,
            "constructorArgs": [],
            "totalSupply": "1000000000000000000000000000",
        })
        self.assertTrue((ROOT / "src" / "PROOFToken.sol").is_file())

    def test_pool_and_economics_match_order_exactly(self):
        self.assertEqual(self.launch["pool"], {
            "pairedCurrency": "0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7",
            "fee": 12500,
            "tickSpacing": 60,
            "initialPrice": "125270724187523965593206900",
        })
        self.assertEqual(self.launch["economics"], {
            "poolBps": 9000,
            "initialMarketCapWei": "2500000000000000000000",
            "remainderTo": "0x000000000000000000000000000000000000dead",
        })

    def test_effective_build_is_reproducible(self):
        config = json.loads(subprocess.check_output(
            ["forge", "config", "--json"], cwd=ROOT, text=True
        ))
        for key, expected in {
            "solc": "0.8.26", "evm_version": "cancun", "optimizer": True,
            "bytecode_hash": "none", "src": "src", "test": "test",
        }.items():
            with self.subTest(key=key):
                self.assertEqual(config[key], expected)

    def test_all_solidity_imports_resolve_without_scratch_or_network(self):
        files = sorted((ROOT / "src").rglob("*.sol")) + sorted((ROOT / "test").rglob("*.sol"))
        imports = re.compile(r'import\s+(?:[^;]*?\s+from\s+)?["\']([^"\']+)["\']\s*;')
        for source in files:
            if "scratch" in source.relative_to(ROOT).parts:
                continue
            for imported in imports.findall(source.read_text()):
                with self.subTest(source=str(source.relative_to(ROOT)), imported=imported):
                    self.assertTrue(imported.startswith("."), "imports must be local and relative")
                    resolved = (source.parent / imported).resolve()
                    self.assertTrue(resolved.is_file(), "dependency is missing")
                    relative = resolved.relative_to(ROOT)
                    self.assertNotIn("scratch", relative.parts)
                    self.assertIn(relative.parts[0], {"src", "test"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
