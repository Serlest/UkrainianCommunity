import {strict as assert} from "node:assert";
import {test} from "node:test";
import {randomUUID} from "node:crypto";
import {adminStorage,db} from "../firebase/admin";
import {deleteUnreferencedBannerAsset,featuredBannerAssetPath} from "./featuredBannerAssets";

test("asset parsing rejects external buckets and arbitrary storage prefixes",()=>{
 assert.equal(featuredBannerAssetPath("https://firebasestorage.googleapis.com/v0/b/uac/o/featuredBanners%2Fa%2Fhero-x.jpg?alt=media","uac"),"featuredBanners/a/hero-x.jpg");
 for(const url of ["https://evil.example/v0/b/uac/o/featuredBanners%2Fa%2Fhero-x.jpg","https://firebasestorage.googleapis.com/v0/b/other/o/featuredBanners%2Fa%2Fhero-x.jpg","https://storage.googleapis.com/uac/users/a/photo.jpg"])assert.equal(featuredBannerAssetPath(url,"uac"),undefined);
});
test("shared image survives source replacement/deletion and is released after the final reference",{skip:!process.env.STORAGE_EMULATOR_HOST},async()=>{
 assert.match(process.env.GCLOUD_PROJECT??"",/^demo-/);
 const id=randomUUID(),bucket=adminStorage.bucket(),path=`featuredBanners/${id}/hero-test.jpg`,file=bucket.file(path);
 const url=`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=fixture`;
 const copy=db.doc(`featuredBanners/shared-${id}`);
 try {
  await file.save(Buffer.from("disposable image"),{metadata:{contentType:"image/jpeg"}});
  await copy.set({imageURL:url});
  await deleteUnreferencedBannerAsset(path);assert.equal((await file.exists())[0],true);
  await copy.delete();await deleteUnreferencedBannerAsset(path);assert.equal((await file.exists())[0],false);
 }finally{await copy.delete();await file.delete({ignoreNotFound:true});}
});
