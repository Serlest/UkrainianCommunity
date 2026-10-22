import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("localizations", Path(__file__).with_name("validate_localizations.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CatalogTablesTests(unittest.TestCase):
    def write(self, root, name, strings, language="de"):
        (root / name).write_text(json.dumps({"sourceLanguage": language, "strings": strings}))

    def test_feature_table_is_validated_alongside_primary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write(root, "Localizable.xcstrings", {"main.key": {}})
            self.write(root, "Feature.xcstrings", {"feature.key": {}})
            strings, failures = module.load_catalogs(root)
            self.assertEqual(set(strings), {"main.key", "feature.key"})
            self.assertEqual(failures, [])

    def test_ambiguous_key_and_invalid_feature_source_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write(root, "Localizable.xcstrings", {"same.key": {}})
            self.write(root, "Feature.xcstrings", {"same.key": {}}, language="fr")
            _, failures = module.load_catalogs(root)
            self.assertEqual(len(failures), 2)

    def test_primary_and_valid_json_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write(root, "Feature.xcstrings", {})
            with self.assertRaises(ValueError): module.load_catalogs(root)
            (root / "Localizable.xcstrings").write_text('{"strings":{},"strings":{}}')
            with self.assertRaises(ValueError): module.load_catalogs(root)

if __name__ == "__main__": unittest.main()
