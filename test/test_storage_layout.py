import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("storage_check", Path(__file__).parents[1] / "script/check_storage_layout.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class StorageCompatibilityTest(unittest.TestCase):
    def setUp(self):
        self.before = {"dependencies": {"openzeppelin": "pinned"}, "contracts": {"Vault": [
            {"label": "balance", "slot": "0", "offset": 0, "type": {"bytes": 32}},
            {"label": "rules", "slot": "1", "offset": 0, "type": {"members": [{"label": "tax", "slot": "0"}]}},
        ]}}

    def test_append_is_compatible_but_old_slots_remain_fixed(self):
        after = copy.deepcopy(self.before)
        after["contracts"]["Vault"].append({"label": "newState", "slot": "2"})
        checker.compatible(self.before, after)
        for field, value in [("label", "renamed"), ("slot", "1"), ("offset", 1), ("type", {"bytes": 16})]:
            invalid = copy.deepcopy(self.before)
            invalid["contracts"]["Vault"][0][field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                checker.compatible(self.before, invalid)

    def test_removal_reordering_and_nested_struct_changes_are_rejected(self):
        for mutate in [lambda fields: fields.pop(), lambda fields: fields.reverse(),
                       lambda fields: fields[1]["type"]["members"][0].update(slot="1")]:
            invalid = copy.deepcopy(self.before)
            mutate(invalid["contracts"]["Vault"])
            with self.assertRaises(RuntimeError):
                checker.compatible(self.before, invalid)

    def test_dependency_change_requires_separate_namespaced_storage_review(self):
        invalid = copy.deepcopy(self.before)
        invalid["dependencies"]["openzeppelin"] = "changed"
        with self.assertRaises(RuntimeError):
            checker.compatible(self.before, invalid)


if __name__ == "__main__":
    unittest.main()
