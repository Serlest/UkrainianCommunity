import { setGlobalOptions } from "firebase-functions/v2";

import "./firebase/admin";

setGlobalOptions({
  region: "europe-west3",
  maxInstances: 10,
});

// Foundation pass only. Business logic exports will be added in later migration phases.
