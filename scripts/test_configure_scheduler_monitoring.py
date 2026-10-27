import copy
import unittest
from configure_scheduler_monitoring import ADDITIONAL_GROUPS, desired_conditions, semantic

class SchedulerMonitoringTests(unittest.TestCase):
    def test_preserves_original_conditions_and_adds_only_enabled_services(self):
        original = {"conditions": [{"displayName": "Existing", "name": "old", "conditionThreshold": {"duration": "60s"}}]}
        jobs = [{"name": "firebase-schedule-" + n + "-europe-west3", "state": "ENABLED"} for _, names, _, _ in ADDITIONAL_GROUPS for n in names]
        jobs.append({"name": "firebase-schedule-cleanupOrganizationPhotoLifecycle-europe-west3", "state": "PAUSED"})
        before = copy.deepcopy(original); conditions = desired_conditions(original, jobs)
        self.assertEqual(original, before); self.assertEqual(conditions[0], original["conditions"][0])
        self.assertEqual(len(conditions), 3)
        self.assertNotIn("cleanuporganizationphotolifecycle", str(conditions))
        self.assertEqual(semantic(desired_conditions({"conditions": conditions}, jobs)), semantic(conditions))
        for c in conditions[1:]:
            self.assertEqual(c["conditionThreshold"]["evaluationMissingData"], "EVALUATION_MISSING_DATA_ACTIVE")
            self.assertLessEqual(int(c["conditionThreshold"]["aggregations"][0]["alignmentPeriod"][:-1]), 90000)
    def test_pausing_a_known_job_does_not_change_schedules_or_monitor_disabled_job(self):
        jobs = [{"name": "firebase-schedule-rollupBannerMeasurementReports-europe-west3", "state": "PAUSED"}]
        self.assertEqual(desired_conditions({"conditions": []}, jobs), [])
    def test_retains_server_condition_identity(self):
        jobs=[{"name": "firebase-schedule-rollupBannerMeasurementReports-europe-west3", "state":"ENABLED"}]
        condition=desired_conditions({"conditions":[]},jobs)[0];condition["name"]="existing-five-minute-id"
        self.assertEqual(desired_conditions({"conditions":[condition]},jobs)[0]["name"],condition["name"])

if __name__ == "__main__": unittest.main()
