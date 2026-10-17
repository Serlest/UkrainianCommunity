// Diagnostic APKs only, never a Play artifact. No Firebase data writes or App Check bypass.
import {execFileSync,spawnSync} from 'node:child_process';
const config=JSON.parse(execFileSync('firebase',['apps:sdkconfig','ANDROID','1:919042658790:android:c3e9447ac6f2a120ac4627','--project','ukrainiancommunity-dbd5f'],{encoding:'utf8',stdio:['ignore','pipe','inherit']}));
const client=config.client?.[0];
if(config.client?.length!==1||client?.client_info?.android_client_info?.package_name!=='at.serlest.ukrainiancommunity')throw Error('Cloud package mismatch');
const env={...process.env,UAC_PRODUCTION_FIREBASE_PROJECT_ID:config.project_info.project_id,UAC_PRODUCTION_FIREBASE_APPLICATION_ID:client.client_info.mobilesdk_app_id,UAC_PRODUCTION_FIREBASE_API_KEY:client.api_key[0].current_key,UAC_PRODUCTION_FIREBASE_BUCKET:config.project_info.storage_bucket,UAC_PRODUCTION_APPLE_SIGN_IN_ENABLED:'true',UAC_PRODUCTION_PASSKEY_ENABLED:'true'};
const result=spawnSync('./gradlew',[':app:assembleProductionDebug',':app:assembleProductionDebugAndroidTest','-Puac.production.sdkSmoke=true','--console=plain'],{cwd:new URL('..',import.meta.url),env,stdio:'inherit'});
process.exit(result.status??1);
