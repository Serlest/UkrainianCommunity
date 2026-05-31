import { setGlobalOptions } from "firebase-functions/v2";

import "./firebase/admin";
export {
  aggregateEventCommentCounterOnCreate,
  aggregateEventCommentCounterOnDelete,
  aggregateEventViewCounterOnCreate,
  aggregateLikeCounterOnCreate,
  aggregateLikeCounterOnDelete,
  aggregateNewsCommentCounterOnCreate,
  aggregateNewsCommentCounterOnDelete,
  aggregateNewsViewCounterOnCreate,
  aggregateRegistrationCounterOnCreate,
  aggregateRegistrationCounterOnDelete,
} from "./counters/aggregation";
export {
  approveGuideArticle,
  archiveGuideArticle,
  publishGuideArticle,
  submitGuideArticleForReview,
} from "./guide/workflow";
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
