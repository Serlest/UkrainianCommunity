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
  acceptLegalDocument,
} from "./legal/legalDocuments";
export {
  createSystemAnnouncement,
  notifyEventCancelledOnDelete,
  notifyEventUpdatedOnUpdate,
  notifyFeedbackReplyOnCreate,
} from "./notifications/backendWriters";
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
export {
  banUser,
  deactivateUser,
  restoreExpiredTemporarySuspensions,
  restoreUser,
  suspendUser,
  warnUser,
} from "./users/accountStatusManagement";
export {
  assignAppAdmin,
  assignAppModerator,
  assignGuideEditor,
  removeAppAdmin,
  removeAppModerator,
  removeGuideEditor,
} from "./users/platformRoleManagement";

setGlobalOptions({
  region: "europe-west3",
  maxInstances: 10,
});
