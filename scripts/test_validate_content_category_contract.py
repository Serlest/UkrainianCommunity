import unittest
import validate_content_category_contract as contract


class RulesCategoryExtractionTests(unittest.TestCase):
    def extract(self, body):
        return contract.rules_categories('    function validEventDocument(data, id) {\n' + body + '\n    }', 'validEventDocument', 'additionalCategories')

    def test_direct_field_remains_supported(self):
        self.assertEqual(self.extract("return data.additionalCategories.hasOnly(['music', 'other']);"), {'music', 'other'})

    def test_cached_field_is_bound_to_the_original_document_field(self):
        self.assertEqual(self.extract("let categories = data.get('additionalCategories', []);\nreturn categories.hasOnly(['music']);"), {'music'})

    def test_unrelated_alias_cannot_satisfy_the_contract(self):
        with self.assertRaises(ValueError):
            self.extract("let categories = data.get('tags', []);\nreturn categories.hasOnly(['music']);")

    def test_missing_or_ambiguous_allowlist_fails_closed(self):
        for body in ["return true;", "return data.additionalCategories.hasOnly(['one']) && data.additionalCategories.hasOnly(['two']);"]:
            with self.subTest(body=body), self.assertRaises(ValueError):
                self.extract(body)

    def test_named_validators_do_not_depend_on_file_order(self):
        source = """    function validEventDocument(data, id) {
      let additionalCategories = data.get('additionalCategories', []);
      return additionalCategories.hasOnly(['music']);
    }
    function validNewsDocument(data, id) {
      return data.additionalCategories.hasOnly(['health']);
    }"""
        self.assertEqual(contract.rules_categories(source, 'validNewsDocument', 'additionalCategories'), {'health'})
        self.assertEqual(contract.rules_categories(source, 'validEventDocument', 'additionalCategories'), {'music'})


if __name__ == '__main__':
    unittest.main()
