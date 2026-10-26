import {onDocumentDeleted, onDocumentUpdated} from "firebase-functions/v2/firestore";
import {adminStorage, db} from "../firebase/admin";
import {deleteUnreferencedBannerAsset, featuredBannerAssetPath, referencedFeaturedBannerAssets} from "./featuredBannerAssets";

/** Retain every asset still used by a duplicate, even when its source banner is gone. */
export const cleanupFeaturedBannerImagesOnDelete = onDocumentDeleted(
  {document:"featuredBanners/{bannerId}",region:"europe-west3",retry:true},
  async event => {
    const bucket=adminStorage.bucket(), referenced=await referencedFeaturedBannerAssets();
    let pageToken: string | undefined;
    do {
      const [files,next]=await bucket.getFiles({prefix:`featuredBanners/${event.params.bannerId}/`,maxResults:200,autoPaginate:false,pageToken});
      for (const file of files) if (!referenced.has(file.name)) {
        await deleteUnreferencedBannerAsset(file.name);
      }
      pageToken=next?.pageToken;
    } while(pageToken);
    const shared=featuredBannerAssetPath(event.data?.get("imageURL"),bucket.name);
    if (shared) await deleteUnreferencedBannerAsset(shared);
    // Also covers legacy clients that delete directly rather than using the callable.
    await db.collection("featuredBannerPresentations").doc(event.params.bannerId).delete();
  }
);

export const cleanupReplacedFeaturedBannerImage = onDocumentUpdated(
  {document:"featuredBanners/{bannerId}",region:"europe-west3",retry:true},
  async event => {
    const before=event.data?.before.get("imageURL"),after=event.data?.after.get("imageURL");
    if(before===after) return;
    const path=featuredBannerAssetPath(before,adminStorage.bucket().name);
    if(path) await deleteUnreferencedBannerAsset(path);
  }
);
