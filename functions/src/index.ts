import { setGlobalOptions } from "firebase-functions/v2";

import "./firebase/admin";
export {
  assignOrganizationAdmin,
  assignOrganizationModerator,
  removeOrganizationAdmin,
  removeOrganizationModerator,
} from "./organizations/roleManagement";

setGlobalOptions({
  region: "europe-west3",
  maxInstances: 10,
});
