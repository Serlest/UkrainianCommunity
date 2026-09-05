import json
import unittest
from unittest.mock import patch
import diagnose_privacy_hosting_2026_13 as diagnostic


class DiagnosticTests(unittest.TestCase):
    def test_transport_rejects_every_mutation_before_parent(self):
        transport = object.__new__(diagnostic.ReadOnlyTransport)
        with patch.object(diagnostic.hosting.Transport, "api") as request:
            for method in ("POST", "PATCH", "DELETE", "PUT"):
                with self.assertRaises(ValueError):
                    transport.api(method, diagnostic.hosting.SITE + "/versions", {})
            with self.assertRaises(ValueError):
                transport.api("GET", diagnostic.hosting.SITE + "/versions", {})
            with self.assertRaises(ValueError):
                transport.upload("unused")
            request.assert_not_called()

    def test_safe_error_preserves_missing_schema_key_without_secret(self):
        self.assertEqual(diagnostic.safe_error(KeyError("fileCount"))["missingKey"], "fileCount")
        output = json.dumps(diagnostic.safe_error(KeyError("secret-token-fixture")))
        self.assertNotIn("secret-token-fixture", output)
        output = json.dumps(diagnostic.safe_error(ValueError("secret-token-fixture")))
        self.assertNotIn("secret-token-fixture", output)

    def test_safe_http_error_retains_only_status(self):
        self.assertEqual(diagnostic.safe_error(diagnostic.SafeHTTPError(503))["httpStatus"], 503)

    def test_json_error_reports_position_not_response_text(self):
        output = diagnostic.safe_error(json.JSONDecodeError("secret-message", "secret-response", 2))
        self.assertEqual(output["exceptionType"], "JSONDecodeError")
        self.assertIn("jsonColumn", output)
        self.assertNotIn("secret", json.dumps(output))


if __name__ == "__main__":
    unittest.main()
