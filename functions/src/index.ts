import { setGlobalOptions } from "firebase-functions/v2";

import "./firebase/admin";
export {
  approveOrganization,
  rejectOrganization,
  requestOrganizationRevision,
} from "./organizations/approvalWorkflow";
export {
  assignOrganizationAdmin,
  assignOrganizationModerator,
  removeOrganizationAdmin,
  removeOrganizationModerator,
  transferOrganizationOwnership,
} from "./organizations/roleManagement";

setGlobalOptions({
  region: "europe-west3",
  maxInstances: 10,
});
