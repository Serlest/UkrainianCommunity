# Firebase and Compose publish consumer rules. Keep only serialized model field names that are
# resolved reflectively by Firestore; application code otherwise remains shrinkable.
-keepattributes Signature,*Annotation*
-keepclassmembers class at.uac.android.** {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}
