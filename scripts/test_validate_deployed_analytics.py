import unittest
from validate_deployed_analytics import consent_contracts

class DeployedAnalyticsContractTests(unittest.TestCase):
    def test_detects_the_actual_2026_22_deployment_gap(self):
        deployed = 'const compatibleConsentVersions = new Set(["2026.21|2026-08-25.1"]);'
        current = 'const compatibleConsentVersions = new Set(["2026.21|2026-08-25.1", "2026.22|2026-08-25.1"]);'
        self.assertEqual(consent_contracts(current) - consent_contracts(deployed), {"2026.22|2026-08-25.1"})
    def test_a_version_in_a_comment_is_not_a_supported_contract(self):
        source = '// "2026.22|2026-08-25.1"\nconst compatibleConsentVersions = new Set(["2026.21|2026-08-25.1"]);'
        self.assertNotIn("2026.22|2026-08-25.1", consent_contracts(source))
    def test_missing_or_empty_contract_fails_closed(self):
        for source in ["", "const compatibleConsentVersions = new Set([]);"]:
            with self.assertRaises(ValueError):consent_contracts(source)

if __name__ == '__main__':unittest.main()
