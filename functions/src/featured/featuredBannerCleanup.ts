import {onDocumentDeleted} from "firebase-functions/v2/firestore";

import {adminStorage} from "../firebase/admin";

/**
 * Firestore remains the publishing source of truth. Once a banner document is
 * gone, this backend cleanup removes every legacy or versioned image below its
 * Storage prefix, including assets left by an interrupted client save.
 */
export const cleanupFeaturedBannerImagesOnDelete = onDocumentDeleted(
  {
    document: "featuredBanners/{bannerId}",
    region: "europe-west3",
  },
  async (event) => {
    const bannerId = event.params.bannerId;
    await adminStorage.bucket().deleteFiles({
      prefix: `featuredBanners/${bannerId}/`,
      force: true,
    });
  }
);
