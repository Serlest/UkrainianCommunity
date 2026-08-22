import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

const app = getApps().length === 0 ? initializeApp() : getApps()[0];

export const adminAuth = getAuth(app);
export const db = getFirestore(app);
export const adminStorage = getStorage(app);
