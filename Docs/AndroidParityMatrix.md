# Реестр функционального паритета UAC

## ALL FINAL LOCAL CHECKS PASS — 2026-09-03 21:52 UTC / 23:52 Vienna

User-requested regression repair completed. **Unit1821/1821,94XML,0fail/error/skip; target16/16each; componentUI243/243each; Main38/38each.** All final native runners exited0 and per-AVD locks released. API26:target16.687s,UI195.321s,Main203.852s. API37:target185.713s,UI377.645s,Main358.327s. Machine audit outputs/final98-audit.json validates exactJUnit counts/no failures/skips,0 cleanup reconciliation warnings in final logs,550source hashes,512protected iOS/Rules/server hashes and bothAPK hashes. Lint0errors/33existingwarnings, format/diffchecksPASS. Actual installed hashes independently verified both apps/both AVDs.

Fixes ONLY in Android test code + scratch runner: HistoryJourney waits actual rendered readiness at deletion point after recreation; HistoryUi regression covers ready/loading/ready and no early destructive action. DsaStatementJourney waits actual READ receipt+nonmutating/nonloading inbox and enabled Open before one click; existing InboxUi pending-read regression proves intended blocked click behavior. Scoped history fixture cleanup verifies exact absence after a single delete, never retries; failed read/present doc fails, emptyGET200 cannot mean absence. Six new helper negative/positive/cancellation tests. One isolated emulatorHTTP500 cause remains unreproduced; do NOT claim transport itself repaired. Final logs have no reconciliation warnings. No product code or safeguards changed.

ProductAPK unchanged d7c814e2da35f6835620db10664dc6346f137f6d47055d935378cf161cba5a94; final95testAPK757baf6ec53fc57fad23e32d755a78acbbbd736f7c5418c56a4b8128ef9bbb1e. Sources/APKs frozen work/dsa95-final. Five changed/new Android-test files only. All historical90/92/93 failures retained, not renamed successful. Interrupted92 exact124docs+1syntheticAuth account removed and absence verified, document copy preserved. Old85/86d unknown cleanup remains separately recorded, not claimed repaired.

Original FirestorePID89335 and recoveryPID43450 remain online; no reset/restart/import of Firestore, no cloud/production/credentials/iOS/Rules/backend/deploy/release changes. After all tests closed, new local snapshots: work/final98-firestore-preserved (~1MiB), work/final98-services-preserved(40KiB), exports returned success. API37font1/API26font2; no instrumentation/build jobs active. Heartbeat staysPAUSED; no ongoing work promised after completion. Final user-facing report outputs/UAC-ANDROID-TEST-FIX-2026-09-03.md. This closes the local regression request, not cloud/device/release parity; resume existing migration plan boundaries without repeating completed local packages.


## Recovery complete, final verification — 2026-09-03 21:16 UTC

Restored local services remain online: recovery86e PID43450, original Firestore PID89335 unchanged. **Main88 API37 PASS38/38 (369.197s); API26 FAIL37/38 (224.183s)** solely HistoryJourneyUiTest after Activity.recreate: deletion button absent while history.loading=true/page=null. This is not a service outage. Unmodified isolated API26 History89 PASS1/1 (6.318s), NOT retroactive full-suite PASS or a proven race root cause. No test/product source edit was made. API26 Cover87 PASS1/1 (10.325s). All test sessions closed; runtime session17069 intentionally remains online. Next Android task: investigate History recreation/readiness in full-suite context, then full regression; no blind retry/mutation/weakening assertion.

Preservation: latest512 tracked iOS/Rules/server hashes PASS; full549 Android source matches frozen84. No cloud/credentials/deployment/iOS/Rules/source changes; scratch recovery harness only. Local Firestore never reset/restarted/imported. Pre-recovery snapshot904KiB retained; post-run local Firestore export936KiB at task work/recovery88-firestore-preserved and Auth/Storage export20KiB at work/recovery88-services-preserved both returned success, taken after tests closed. These backups were NOT restored into live DB and do not prove old85/86d unknown cleanup; old86d blob archive retained separately. No original crash root-cause claim.

User-facing outputs/UAC-ANDROID-RECOVERY-2026-09-03.md is current final report. Previous evening/continuation outputs updated. Existing heartbeat PAUSED, no new recurring job or autonomous scope extension beyond approved restoration inferred. User authorization for restoration after23 is recorded; phone/shared production database safety remains strict.


## Recovery86e, safe continuation approved — 2026-09-03 21:12 UTC

User explicitly approved continuing restoration after23:00, with iPhone/shared production database preservation as priority. No new cloud/credential/backend/iOS/release authority. Live Firestore PID89335:8088 preserved, never stopped/reset/imported. Local demo backup exported to task work/recovery86-firestore-preserved (904KiB, output-0 SHA ea9298c92ce1c4439e1481c4f9756559f9949ad5107cc56dc0f8c55beca6b326). 512 tracked Swift/iOS/Rules/server source hashes unchanged; 549 Android source hashes match frozen84.

Missing services now recovery86e PID43450, session17069, task work/recovery86-runtime-... (see outputs/recovery86e-runtime.log). Launcher onlyauth/storage/functions, demo-uac-android, clean allowlisted environment/XDG config, macOS sandbox external-egress deny + repository-write deny. Uses existing functions/android-local callable-only harness, no background triggers. Scratch-only adapter gives Functions env + Storage registry.getInfo the surviving Firestore address, WITHOUT registering lifecycle ownership. Five adapter isolation assertions PASS. Other8098 emulator untouched.

Recovery86d failed (API26 2/3, API37 1/3): Storage Rules needed registry Firestore address; exact stack Cannot determine host and port of firestore killed common CLI. This is proven recovery failure, NOT proof original85 root cause. Fixed only scratch connection adapter; API26 standalone cover87 PASS1/1 10.325s including exact cleanup. 86d blobs preserved as work/recovery86-failed-storage-preserved.tgz; do not delete/claim cleaned. Old85 and86d Auth/Storage memory not recovered; unresolved uploads/cleanup retained, no replay or broad deletion. Initial86 attempts (Java17, path, missing Functions env) historical failures.

Full38 Main88 on unchanged frozen84 apps now pending both: API37/font1 session34894, API26/font2 session65868. Logs outputs/recovery88-main-api{37,26}.log. Finish checks and update evidence; don't assume complete until realJUnit results and service/source checks. Heartbeat remains PAUSED; direct current turn recovery only. User report outputs/UAC-ANDROID-RECOVERY-2026-09-03.md. Preserve all current local runtime state; no blind restart/reset at handoff.


## Recovery approval and preservation check — 2026-09-03 20:59 UTC

User approved local restoration without database clearing or cloud/credential access ("hfphtif." = разрешаю). This supersedes the earlier need for initial recovery permission, not the 23:00 Vienna deadline. Firestore PID89335 still listens on8088; Auth9098/Storage9198/Functions5008/Hub4408 absent. No restarts, kills, reset, credential access or cloud calls performed. Installed firebase-tools source confirms Auth state is created in memory; Storage maps are in memory and default persistence is os.tmpdir()/firebase/storage/blobs. That directory and /tmp/firebase/storage/blobs are absent; absence does NOT prove all possible custom persistence/export locations absent. Config firebase.android-functions-local.json verified local ports and functions/android-local source. Separate demo-uac-cancellation-rules on8098 must remain untouched.

Recovery remains incomplete. Next: locate original launch/export/custom temp-path evidence without credentials; preserve surviving Firestore and any discovered storage artifacts; recover missing services only with understood state boundaries. A fresh empty Auth/Storage must not be called restored old state or successful orphan cleanup. Main85 remains FAIL, unchanged source/build/test evidence. Heartbeat remains PAUSED; no integration jobs running. Continued work past23:00 needs renewed time authorization.


## Final pause22:54Vienna — 2026-09-03 20:54UTC

Heartbeat uac-android-3-12-00 PAUSED viaautomationtool; matchingid/kind/target/status readbackverified. Stop before23dueactualmissinglocalservices requiringpreservation/recovery decision, notschedulerwaiting. Latest85FAIL/partialcleanup details immediatelybelow; no runs/buildsactive, allcode/docs/logs preserved. Userfacingfinal outputs/UAC-ANDROID-EVENING-2026-09-03.md and UAC-ANDROID-CONTINUATION.md nowshowoutage. Do not resumeauto/restartservices/clearorphanstate withoutnewdirection. Firstnextaction is localruntime preservation/recovery plan withoutcloud/credentials/datareset, then exactcleanup +freshfullregression.


## BLOCKED: Main85 service outage — 2026-09-03 20:53 UTC

**LatestMain85 FAIL:API26 17/38PASS+21FAIL;API37 15/38PASS+23FAIL.** EnhancedDSAreview first PASSboth incl offlineSDK restore/lifecycle/newfixturecleanup; severalfollowingtestsPASS. Firstfail37AuthoringcleanupAuth9098;26ContentCoveractualuploadUNCONFIRMED/EOF +Storage9198read/cleanupfailure, then many9098setup failures. No proofnewtestcausedoutage. Independenthostchecks20:48/20:52: Hub4408/Auth9098/Storage9198/Functions5008 no listeners/HTTP000; Firestore8088stillHTTP200 PID89335PPID1. Exactcausewhylauncher/servicesstoppedunknown. No restart/clear/kill/defaultcloud/wrongdemofallback. Allnative/buildsessionsclosed,fonts37=1/26=2.

Source/app unchanged:1821unit94XML/0failure-error-skip,lint0errors33warnings; mainSHAd7c814e2da35f6835620db10664dc6346f137f6d47055d935378cf161cba5a94;test84SHA8aa82aae88fe971638e6fc700b4b23cf798ec0dceb865af14c30052ed7a34a50, actualinstalledfourhashesreadbackPASS. Frozen84full549source/config/unit/lint/APKs;finalformat/diff/source549checksPASS. PriorMain79PASS38/38each,broad81PASS242/242each,isolated84PASS1/1each10.491s37/5.944s26 stayhistorical, doNOTclaimfinal85green.

**Cleanup unresolved** at leastAuthoring37Auth andCover26Storage/Auth; uploadunknownno replay. Some laterpartialcreationsrequireaccounting. NewDSAcleanupdoesNOTprovewholeMainclean. Redactedlogs lackallexactIDs; no guessing/broaddelete/newemptyserver-as-oldcleanproof. Detailedledger work/A05-runtime85-failure.md. Need separatelyauthorized localruntime preservation/recovery WITHOUTclearingliveFirestore/cloud/credentials, then exactfixture reconciliation+freshfullregression. Untildecision no more integration runs/newmutations; pauseexistingheartbeat uac-android-3-12-00 instead of repeatedfailedjobs. Timeauthority23Vienna doesnotoverrideboundary. A04serverfixunapproved,A05mutations/portalclosed,A06preflightonly. Update eveningoutput toshowlatestoutage and requestdirection.



## Broad81 и lifecycle83 PASS; offline84 идёт — 2026-09-03 20:45 UTC

**Broad81 PASS242/242each font200:375.574s37/203.439s26.** PriorMain79PASS38/38each remains valid currentruntime proof.83 test-only extends actual ownreview Mainjourney with background(CREATED) immediateVMcleared assertions, changedownsyntheticdecision beforeRESUMED, changedownsyntheticdecision beforeActivityrecreate, freshread/newwindowFLAG_SECURE/logoutclear. **83PASS1/1each10.129s37/5.712s26**, no process-death/cloud proof.1821unit/94XML/0failure-error-skip,83APKs/lint22s; runtimeSHAstilld7c814e2da35f6835620db10664dc6346f137f6d47055d935378cf161cba5a94. Archive83 full549source/config/unit/lint/APKs.

84 ONLY adds offlineSERVERread afterrealprofile/decisioncache into samejourney. disableNetwork/enableNetwork only namedlocalSDK client, neverAVDradio/server/wholeDB; enable in finally, require freshsuccessfulread afterward. No productchanges.84build21sPASS, runtimeSHAunchanged;testSHA8aa82aae88fe971638e6fc700b4b23cf798ec0dceb865af14c30052ed7a34a50. Frozen work/android-a05-offline84-final549-sourcemanifest/archive/config/unit/lint/APKs. Bothinstalled/font2. **84target1each pending** sessions82249(API37)/52955(API26),outputs/android-a05-offline84-api{37,26}.log. Afterpass finalMain38 with this enhancedjourneyfirst thenallother37 canverifySDKrestoration doesn'tcontaminate latercases; oldcompletedbroad45classes do not needrepetition (no sourcechanges).

Authority ends21UTC/23Vienna. Finishrunningtest/exactcleanup, verifycurrentruntime/nativeSHA/source, restore37font1 afterownrun, finaldocs+outputs/UAC-ANDROID-EVENING-2026-09-03.md, PAUSE existingheartbeat uac-android-3-12-00. No new package/mutation/cloud/credentials/backend/Rules/iOS/phones/cost/release/commit/push/agents. Eveningoutputcurrentlydraft22:44, don'tcallfinalbeforeupdated. A04approvalabsent, A05mutations/portalclosed, A06preflightonly.



## Main79 PASS; version82 PASS; broad81 идёт — 2026-09-03 20:38 UTC

**Main79 frozen78 PASS38/38both:353.195s API37/font100%,218.235s API26/font200%.** This supersedes pending79, not historical70FAIL. Same main/testAPKs d7c814e2da35f6835620db10664dc6346f137f6d47055d935378cf161cba5a94 /2ada830b31d7253baaef7c74bbbd1b299b04e889cfda579d011945287ccf1250. NewDSA target17/17each alreadyPASS, no needduplicate. HistoricalPhotoPicker70/72intermittency remainsnotroot-caused even though latestfullPASS.

82 ONLY adds4unit tests to DsaAppealReviewTest: per-field9reporter/13decision change matrix, nanoseconds/falseflags, Unicode and fieldboundary separation, explicitnotfullparent/notreceipt invariant. **1821unit/94XML/0failure-error-skip,build/lint17s,0lintErrors/33warnings. BothAPKs byte-identical78.548other sourcefiles checked unchanged**, includingallruntime/nativefiles. Unit-onlyarchive work/android-a05-version82-final; frozen78sourcearchive remainsnative baseline. No runtime/newpackage/endpoint edits82.

Additional remaining-component81 **242native checks each pending**: prior55remaining229 minusalreadytestedFeedback3 +FeedbackInbox9 +DsaStatement7. API26font2session14833,API37font2session45093, logs outputs/android-a05-regression81-ui-api{37,26}.log. ExactAVDs only; do notinstall/restart/changefont untilownruncomplete. Main79sessionsclosed. Next finishbroad,review failuresifany,restore37font1,verify source/binaries and checkpoint23Vienna/21UTC; pause existingheartbeat atdeadline.

A06 read-onlypreflight80 in work/A06-readonly-evidence-preflight80.md: completebackend414lines+iOSmodel/repo/VM/UI+parser tests, Rulespartials. Evidencecallablesowner-only andcurrentlydisabledAndroid. ExistingcursorDate/ISOmilliseconds canlose submsordering; pureNode6assertion reproduction PASS outputs/android-a06-cursor-preflight.log, **NOTactualSDK/emulator/cloud proof**. Per-userreceiptqueriesunorderedcap500each/no completenessflag; max1503projectedevents mayexceedcurrentresponsebudget. No A06implementation/backendchange/dataaccess. Decision for reliablepagination/completeness required before enablingfullhistory claims. A04BulkWriterfixstillunapproved; A05appealdispatch/decisions/portalclosed; nocloud/credentials/iOS/phone/cost/publish/commit/push/agents.



## A05 review78 PASS; Main79 идёт — 2026-09-03 20:29 UTC

Read-only reporter decision UI/VM/Main route готовы:1817unit/94XML/0failure-error-skip,16newpure;77APKs/lint41s,78test-only14s. Newclosed OWN feedback hint opens independently validated SERVER review; fullfacts/bases/territory/duration/redress/automation/humanflags/decisiondate/deadline, explicit no-send/no-receipt. Lifetime/privacy/account/selection/expiryguard+WindowSecurity; no drafts/appealdispatch/journal. ActualMain ownitem→review→back clears→serverchangedownfixture→reopenfresh→logoutscrubsprivatehistory, FLAG_SECURE/restoration, noappeal/nochild writes, exactparent/user/publicprofile/Authcleanup/readback. **Targeted78 17/17each PASS32.794s37/12.840s26, bothfont200** =reviewUI5+Main1+SDK3+existingFeedback3+context5.77prior12/13eachFAIL was assertion expecting substring as whole text; observedexactexpiredlabelandcleareddata,78assertsexactwholelabel (no productchange).76 interruptedtest harness recorded separately,77unitPASS.

Frozen78 work/android-a05-review78-final:549sourcefiles/fullmanifest/archive/config/unit/lint/APKs,549/549checksPASS. MainSHA d7c814e2da35f6835620db10664dc6346f137f6d47055d935378cf161cba5a94 (same77);testSHA2ada830b31d7253baaef7c74bbbd1b299b04e889cfda579d011945287ccf1250. Installedboth. FullMain79 **38tests pending** (37previous+reviewMain), start20:28:54UTC;API37/font1 session84510,API26/font2 session47857;outputs/android-a05-regression79-main-api{37,26}.log. Do not change/install/restart AVDs during tests. Read-only audit/docs may run concurrently. HistoricalMain70 failures not retroactivelygreen; picker intermittent cause stillopen. Deadline21UTC/23Vienna:finishsafely+exactcleanup/checkpoint thenPAUSE existingautomation uac-android-3-12-00. No arbitrary15minute wait. No new backend/cloud/credentials/iOS/device/release/agent authority.



## A05 read75b PASS; review77 проверяется — 2026-09-03 20:24 UTC

74 завершён1792unit/92XML.75b actualSDK own feedback SERVER query+noncache/nonpending checks, same compiled Firebase identity, fresh ownprofile+actualtoken, strictTOTP privilege, AuthStore NonCancellable gate; no callable/dsaCases/write.1801unit/93XML/0failure-error-skip; APK/lint18s. Native read3+ICU5 **8/8both PASS (6.252s37/0.684s26)**: ownquery/foreignabsence+directDENIED, actualsavedSDK123456000ns vs input123456789ns, changeddecision fingerprintSTALE, no child writes, strictactualTOTP, exactownparents/users/publicProfiles/Auth cleanup/readback. Initial75 testcompileFAIL used instance fixture method as static; source/log preserved,75b fixed constructor only. Archive work/android-a05-read75b-final fullsource/config/unit/lint/APKs;mainSHA6bb61598947fca89af224b25f455eff30b2a5ee44ca82a329b995b9640d66d3e/test66af8c502e2ca5f632a7330decf8ea25bd170afc0ccd4f3c5c759b557c1edd58. Installed75b both/fonts1/2; no native sessions.

76/77 adds read-only review VM/state, account/selection/expiry visibility fences, localdeadline timer, fresh reopen, no automaticnetworkreload. First76 test harness failed to cancel periodic ViewModel timer before runTest cleanup (fixedclock caused busy scheduler); exact owned Gradle test executor terminated, originalsource/log retained. New checked{} test wrapper clears models within test finally, no producttimer disabled.77 also DE/UK read-only screen+Mainfactory+profile/dsa-review/{id}+own closed/decided/noappeal Feedback hint, independentfreshSDKvalidation, sharedWindowSecurity lease, lifecyclehide, explicitno-send/no-receipt notice.14VMtests+2hint/navigationtests+5newUItests; build session36988 pending, no 77native proof yet. Next actual Main journey and full final regression; do not conflate75b SDK proof with new77. No appeal dispatch/draft/journal/allowlist; fingerprint NOTserverCAS. Continue active until23Вена/21UTC, no15minute gaps. All cloud/credentials/backend/Rules/iOS/phone/publish/cost/commit/push/agent limits unchanged;A04 fix unapproved.



## A05 review73b готов, read74 проверяется — 2026-09-03 20:03 UTC

72native: API26 PASS12/12 44.670s;API37 FAIL11/12 217.494s, теперь Avatar exactalbum открыт, но nativePhotoPicker показывает No photos yet. ContentCover/status/ICU5 PASSeach; не выдавать отдельные повторы за полный72PASS.73b adds isolated actual picker(no explicit Auth/Main/backend operations): directownphoto +cancel/reopen/newownalbum, boundedactualPNG equality, exactprocessfixture cleanup. **Probe2+Avatar1=3/3each PASS (54.705s/12.341s)**; причина исторических70/72 picker сбоев всё ещё не доказана. Не отключали защиту/не перезапускали/не очищали устройства. Main70 остаётся36/37FAILboth; следующий полный прогон требуется для окончательного runtime snapshot.

73b inert reporter review models/contract: strictOWN uid, knownclosed/archive+decided+noappeal, exactdecisiontypes/currentfields, deadline nanos and equality, unknownschema/outcome failclosed, honest automation/human flags. Bounded ownedcopy beforeprojection/hash; fingerprint exact selected review fields incl reportID/UID/status/updatedAt/fullknowncase, optionalmissing≠null,metadata/nanos; notfullparent/messages/serverCAS. No rawcontact/token retention or persistence.17newunit/full1780unit92XML/0failure-error-skip, APKs/lint38s. Archive work/android-a05-review73b-final;mainSHA6512dd07c2c4f8c4ebaad48d70f25a5c4d5e53b7c09ef04059204553546db525;test6cfee5f3c5555dd826b65eeebbcbd1d8bf9db589da5c64c6cba97a34b51eab7a. Installed73b both/fonts1/2; no active native sessions.

74 adds only read-only coordinator +12controlledtests: scope/account/revision/backend/readiness, selection before/aftergate, fresh versioncomparison, postgate deadline, actualcaller cancellation throughNonCancellable gate, lateerrorsdiscard, redactedOFFLINE/MISSING distinction, no retry/cache/journal/send. Build session94375 pending; no actualSDKsource/UI yet. Next75 adapter requires fresh actualSDK/Auth/profile+SERVER/nonpending ownquery metadata; ordinary reporter not owner-only, no full dsaCases/callable/mutations. Until23Вена/21UTC continuously, all cloud/backend/Rules/credentials/iOS/phone/publish/cost/commit/push/agents restrictions remain.


## A05 text71b готов, диагностика72 native pending — 2026-09-03 19:44 UTC

71b:1763unit/91XML/0failure-error-skip,20newpure; APKs/lint39s.4newsource и531старых69b файлов побайтно неизменны до72, manifest check сохранён. JS whitespace25 exact locally compared, normalized-preview marker, malformedUnicode/controls rejected, UTF16max5000, ICU logical minimum20; exact request2fields/response4fields+canonicalmillis, privacy diagnostics. Это inert contract без SDK/journal/UI/dispatch; nativeICU5 ещё pending. Первый71compileFAIL wrong guard name id исправлен на существующий validId, исходник/лог сохранён. Archive71b mainSHA58492b4a8410b22e6c5eeeae6b017db52b22a3546a03462f5f94472c9069a491/test10c6506d4b9018ace09e084a27d0919b7d6f05f788af6492d6ab1ae90d00fa07.

Main70 на frozen69b завершён **36/37each FAIL**,37=959.128s/26=210.010s.37 ContentCover в nativePicker BEFORE anyupload: exact own album missing/No photos yet; это НЕ прежний67remove-scroll сбой.26 AccountStatus 10s home tab visibility timeout; unchanged isolated2/2 PASS11.506s, причина полного сбоя не доказана. Новые statement/contextMain PASSeach. Никакой ретроактивной зелёной полной регрессии.72 test-only: publish updateCount==1 for exactgallery, read-only exactrow metadata diagnostic; ContentCover cancellation now uses existing verified-focused-window single-native-Back helper already used by Avatar, no retry/result injection. AccountStatus only adds privacy-safe geometry/IME/ready diagnostics, unchanged10s wait/actions. Does NOT claim cause/fix of historical70 failures. Actual screenshots progressed, no process/device kill/restart.

72 APKs/lint14s, runtimeSHA matches71b; testSHAa41a4a288c80c093eb51f06aab0d0685276c93703aec934e7cf4d7a019dd508f. Frozen work/android-a05-diagnostics72-final has535-source fullmanifest/archive,unit+config,APKs. Both installed; **native12 pending**=ICU5+all4photo journeys+status2+contextMain1. API37/font1 session76451,API26/font2 session36095; logs outputs/android-a05-diagnostics72-api{37,26}.log. Do not install/alter fonts while active. Source-only independent73 permitted, results72 belong only frozeninstalled72.

Следом73 read-only reporter review of exactdecision/deadline/version, no send. Fresh sources and boundaries in work/A05-appeal71-preflight.md; server no expectedDecisionVersion/idempotency/CAS. Unknown read state or matchingtext never own response proof. Existing A04 server fix unapproved; all3DSAmutations/portal closed. Continue immediately/no15minute scheduler pause until23Вена/21UTC. No cloud/credentials/backend/Rules/iOS/phones/cost/publish/commit/push/agents.


## A05 message69b PASS, полный Main70 идёт — 2026-09-03 19:28 UTC

1743unit/90XML/0failure-error-skip,5newunit, APKs/lint15s,format/diffPASS.69 первая полная сборка сохранила1устаревший отрицательный тест user/system; он заменён настоящим unknown role=system negative, server user/system positive и receipt-conflict остаются. Исходный69FAIL/XML/источник архивирован. Native11/11 обеAPI/font200 (25.762s/12.339s):5contextUI+contextMain+3oldFeedbackUI+2oldSDK. Server-shaped user/system fixture отображается без повышения роли, invalid0; точный новый parent/foreign/child/Auth cleanup/readback PASS. Старый FeedbackDevice cleanup не переобъявлять полностью доказанным.

Frozen69b work/android-a05-message69b-final:531 app/src+pushprobe/src files manifest/archive, build-config archive,unitarchive,APKs. MainSHA2fbe84b22c0e3d417b1104bec5279cb4b469a9b1ae751c09e6b1dd933a63ec16;testSHAa4f6f34338031fd63c5375f662f86c9a64b2a7900babf45516c9d420b9128ff0. Установлены обе. **Main70 pending37tests=35legacy+statementMain+reporterContextMain**, API37/font1 session48634, API26/font2 session31908, logs outputs/android-a05-regression70-main-api{37,26}.log. Ни новых установок, ни font/state changes до окончания. Разрешена отдельная source-only работа над71, но результаты70 относятся ТОЛЬКО immutable installed69b, не новой71. Не повторять только что завершённые68/69 тесты без причины.

Следом71 bounded appeal text/request/receipt contract, пока без SDK/allowlist/journal/UI/send: точная серверная JS whitespace normalization,UTF16max5000 и Android ICU logical character minimum20 после normalization; показать различие с iOS вместо silenttruncate. Отдельные nativeAPI26/37 границы grapheme, независимые от JVM. Primary API reference https://developer.android.com/reference/kotlin/android/icu/text/BreakIterator прочитан публично (не cloud credential/API). Review/version/uncertain-outcome ещё отдельная работа; existing submitDsaAppeal не имеет expectedDecisionVersion/idempotency key, matching read-back не own receipt. До23Вена/21UTC без15минутных пауз и новых внешних разрешений.


## A05 context68c PASS; message69 в работе — 2026-09-03 19:23 UTC

Context68c actualMain+existingFeedback+statement =3/3 обеAPI/font200 (54.153s/10.320s). Exact own feedback/SDK projection, чужой parent denied и ownedquery absent, nanosecond components фактически сохранённого SDK timestamp, UI/read-only/back/logout/FLAG_SECURE, exact fixtures/Auth cleanup+readback PASS.68b ранее2/3eachFAIL: ожидался pre-write123456789ns, локальное хранилище возвращает123456000ns.68c отдельно проверяет SERVER SDK timestamp.seconds/nanoseconds и равенство проекции; decoderunit987654321ns сохранён. Runtime68 не менялся, APK324eb546042940b73eac0c266313ff1c6f893226dabb922f17defe78cc298b08;test68c9a343b22e3a459a16f924a164de8786cc9c3986cbeaca5b165f5a79483ac0061; archives68/68b/68c и исходныеFAIL logs сохранены. FullMain этой версии не выполнен.

69 fresh preflight work/A05-system-message-preflight69.md нашёл конкретный read mismatch: сервер submitDsaAppeal создаёт senderRole=user/isSystem=true, Android отвергал и исключал его из истории. Отдельная reproductionunit FAIL expected invalid0 actual1 архивирована. Убрана только эта неверная связка в read decoder; owner всё ещё определяется только role, client Rules/close/receipt checks не ослаблены.5newunit и exact server-shaped synthetic child в Main test; без actual appeal/callable mutation. Build session5465 pending, native69 ещё не запускался. Затем targeted, freeze и полный Main37perAPI (35legacy+2newDSA). Непрерывно до23Вена/21UTC, без новых внешних разрешений.


## A05 context68 готов; Main68b проверяется — 2026-09-03 19:17 UTC

Добавлен bounded typed feedback.dsaCase display projection и read-only DE/UK карточка в существующем FeedbackDetail: location/explanation/basis/evidence, appeal review reason, честный goodFaith Boolean. Unknown enum сохранены; лишние поля/контакты/token/decision не удерживаются; общийUTF8 limit65536, malformed Unicode/type/metadata дают отдельное предупреждение без потери переписки. Это не eligibility/version-lock/fullcase; author statement не расширен. Видимость только exact selected parent + ready actor + OWN uid или MANAGEMENT canManage, без loading/error; общийWindowSecurity lease защищает DSA detail. Не включены appeal/decision/delete/clear, обычное закрытие DSA запрещено.

1738unit/90XML/0failure-error-skip;14newunit; APKs/lint37s;5new+3existing UI =8/8 обеAPI/font200 (28.595s/5.091s), actual window secure/restoration проверены. Archive work/android-a05-context68-final, mainSHA324eb546042940b73eac0c266313ff1c6f893226dabb922f17defe78cc298b08;testSHAf662667ed7d9f07addb3258e818844cfdd2b8b72ec3ebbaed4c24e40d347f41c.68b добавляет только realMain/SDK journey; build session64826 pending, не объявлять nativeMainPASS.67b cover-only повтор прошёл1/1 обеAPI (59.055s/8.933s), runtimeAPK совпал66b; полныйMain67 исходный34/35API37 остаётсяFAIL. Полный integratedMain повтор после68b. No running native sessions сейчас. До23Вена/21UTC непрерывно, все прежние внешние запреты сохраняются.


## Main67: один наблюдаемый сбой, 67b проверяется — 2026-09-03 19:09 UTC

Frozen66b полный Main67: API26/font2 PASS35/35 194.281s; API37/font1 FAIL34/35 657.049s. ContentCoverJourney остановился ДО request tap: trace показывает loading/fresh переход во время scroll и нулевые visible bounds кнопки content-cover-remove после изменения высоты изображения. Это не доказательство отказа удаления сервером; отправки в этой фазе не было. Остальные34 завершены, не называть полный прогон PASS. Все516 исходников66b сверены до правки, исходный лог сохранён.67b меняет только этот test: bounded ожидание actual same target/session/canRemove + displayed geometry с повтором ТОЛЬКО read-only scroll. Единственные request/confirm pointer taps и итоговые object/doc assertions не изменены, retry mutation отсутствует. Сборка/проверки67b pending; runtime APK должен совпасть66b. После целевой проверки полный Main повтор. Пакет68 reporter context пока только preflight work/A05-reporter-preflight68.md. Продолжать без пауз до23Вена/21UTC, прежние внешние ограничения сохраняются.

## A05 Main66b готов, регрессия67 идёт — 2026-09-03 18:57 UTC

Main factory/state/observer и private route profile/dsa-statement/{id} подключены; оба alias уведомлений проходят строгую canonical ID проверку, planning остаётся недоступным. Read-only экран защищён общим WindowSecurity lease. **1724unit/89XML/0failure-error-skip; Main66b APKs/lint17s/format-diffPASS;11/11native обеAPI/font200 (40.364s/10.751s).** Реальный Main notification→statement→back→fresh reopen→logout, FLAG_SECURE, отсутствие старых данных и exact own fixture cleanup/readback проверены. Начальный66 unit FAIL был устаревшим ожиданием unavailable для теперь подключённого DSA alias; заменён положительной проверкой exact route, planning deny сохранён, исходныйFAIL/XML архивирован. Не выдавать это за облако/positiveTOTP/правовое решение.

Frozen work/android-a05-main66b-final:516-source full manifest/archive, unitarchive,APK. MainSHA8eadad9821ac5a59b7a0caed6b773ac66b6d1f9af15a1d5beed328af453e30b6; testSHA990a7c3a4037609cc371047255e7b2abd4bca7b01d5b147d8de96fa0538e5bec. Обе установлены, исходники после freeze не менять до завершения regression. Сейчас67 fullMain35 perAPI: API37/font1.0 session80844, API26/font2.0 session47874; logs outputs/android-a05-regression67-main-api{37,26}.log. Это pending, не PASS. Проверить actual finish/results перед следующей сборкой/установкой. No other active build/native sessions.

Пока идёт regression — свежий read-only preflight оставшейся A05 reporter appeal, не owner decision и не portal. Fresh iOS canAppeal/status/deadline и backend whole callable/sideeffects должны быть прочитаны перед выбором пакета68. Не копировать statement author authority в reporter mutation. A04 server-fix не разрешён; SDK/dispatch удаления закрыты.23Вена/21UTC срок, непрерывный переход без15минутных пауз; прежние ограничения сохраняются.


## A05 экран65b готов отдельно — 2026-09-03 18:50 UTC

Read-only ViewModel/DE-UK экран завершён без Main wiring:1720unit/89XML/0failure-error-skip,12newVM, APKs/lint65=37s;65b только уточнил2test expected strings, unitUP-TO-DATE. **10/10native обеAPI/font200:37=36.653s,26=5.098s (confirmed log).**7UI+3realSDK, exact own cleanupPASS. Scope/render masking, hide/cancel/route races, clearing on refresh/errors, unknown statuses/outcomes, no mutation controls. No new cloud/legal/positiveTOTP proof. Main65SHA b1b2e6a3f2abd00ca69fe2f458d719e391783a667afee7bac29f781ef2caba72; test65SHA99233e13932a028e8a999197e036ef0ac1451ffd81540a3acf82ed352594d471. Both installed hashes matched, both fonts2currently. Immutable work/android-a05-ui65b-final:12source manifest,source+unit archive/APKs. Runtime logs outputs/android-a05-ui65b-api37.log and android-a05-ui65b-api26-confirmed.log.

Original api26 log NOT accepted: runner was launched before install had finished, old64 APK lacked newUI class (4tests/1ClassNotFound). Own orchestration mistake retained. Exact pending install532579393 compiler dex2oatPID8095 showed futex wait, idle/no progress >1min. Sent TERM ONLY to verified compiler of this exact own package installation (su0 on named syntheticAPI26); install then returnedSuccess both APKs, active install sessions empty, package hashes verified before full10 repeat. No device/DB reset or user-data wipe, no compiler settings changed. Do not claim original failure was productUI bug or full optimizer readiness.

**Next66 immediately:** MainActivity ViewModel factory/state/auth observation + DSA route, strict BrowseNavigation/InboxNavigationTarget availability; unit routes, integrated native Main navigation/hide/account/secure flag tests. Full Main regression only after frozen integrated snapshot. SDK64b/65 source and unit archives remain versioned.23Вена/21UTC deadline, no15minute idle, original authority boundaries unchanged. A04 server-fix still unanswered.


## A05 SDK64b завершён — 2026-09-03 18:40 UTC

Чтение getMyDsaStatement подключено только к существующему локальному callable: actual Auth/db/gateway same-app binding, exact compiled backend scope, verified nonanonymous identity, свежий SERVER own profile, active/warned и strict activatedTOTP только для admin/owner; ordinary author не требует owner. Auth adapter использует withReadySession, сохраняет identity до actual Task, поздний account/cancel результат отбрасывается. Нет direct dsaCases/public token portal/мутаций, три decision/appeal endpoints закрыты. UI/навигация пока не подключены.

**1708unit/88XML/0failure-error-skip, APKs/lint34s; native3/3 на обеих API (9.280s/1.843s), шрифты1/2.** Реальный named local Auth/Firestore +local callable протокол: synthetic author получает очищенное своё statement, чужое/отсутствующее NOT_FOUND, full case Rules DENIED, forged owner-ready без actualTOTP DENIED. Все точные собственные cases/user/publicProfile удалены и readbackabsent, Authreload USER_NOT_FOUND. Никаких правовых решений/облака/positiveTOTP/physical device proof. Новая63+64 unit часть11тестов; начальные64 три mapping-теста упали из-за Kotlin shared enum table и Android SparseArray initialization. Исправлено firestore code.name mapping, проверки не ослаблены; native error-code mapping добавлен. Первоначальный FAIL/исходники/XML сохранены work/android-a05-sdk64-failed и outputs/android-a05-sdk64-build.log.

Immutable work/android-a05-sdk64b-final:8-source manifest,source+unit archive,APKs. MainSHA2c9bde167593b130a6d2ac7d9d3990fd5512fcfae18058725b89415ed808c0c5; testSHA9da6e93d43daf0e336e7f516dedf05750a5bc8ce3e43e3bf4a72435e1431027e. Обе установлены; логи outputs/android-a05-sdk64b-{build,api37,api26,format-check}.log. Build/native сессии завершены, полный Main этой версии не заявляется.

**Сразу далее65 без ожидания расписания:** read-only ViewModel/экран DE-UK и route из DSA notification. Сначала изолированные state/host tests: hide/account/revision/selection masking, no stale data during reload/error, explicit retry only, no legal-action controls. Затем Main factory/state/route +InboxNavigation/BrowseNavigation bounds и nativeUI на двухAVD/font200; полная регрессия после frozen integrated snapshot. Срок23Вена/21UTC, heartbeat1минута только страховка; не заканчивать ход ради таймера. A04 server-fix без разрешения; прежние cloud/backend/credentials/iOS/phone/cost/commit/push/agents ограничения сохранены.



## Новое поручение — 2026-09-03 18:32 UTC

Пользователь прямо продлил работу до23:00 Europe/Vienna (21:00 UTC) и отменил15-минутные паузы между заданиями. Переходить сразу к следующему безопасному пакету, не завершать ход ради ожидания расписания. Существующий heartbeat uac-android-3-12-00 обновлён на23:00/страховочный интервал1минута, ACTIVE/target текущей задачи подтверждены. Старые сроки21Вена/19UTC ниже исторические и заменены этим поручением. Облако, credentials, production, backend/Rules fix, телефоны, публикация, расходы, commit/push и новые агенты не разрешены. В23:00 безопасный checkpoint и pause этого же heartbeat.

## A05 statement63b — 2026-09-03 18:31 UTC / 20:31 Вена

Готов отдельный блок безопасного чтения обоснования решения: точный формат запроса/ответа и координатор без отправки изменений. **30 новых проверок, весь набор 1697 unit / 87 XML / 0 failure-error-skip; обе APK, lint и format/diff PASS.** Первая63 сборка34s/26new, окончательная63b14s/30new; lint0errors/33warnings/1hint. Не подключён к SDK/allowlist/Auth adapter/UI: это controlled-source proof, не работа экрана/облака/настоящего TOTP. На AVD остаётся61c, шрифты1/2 проверены; тестовые данные/устройства не изменялись. Прежний Main61c не приписывается новой63b.

Только3 новых файла: feature/dsastatement/DsaStatementContract.kt, DsaStatementRepository.kt и DsaStatementTest.kt. Все504 прежних исходника61c побайтово неизменны, проверено после сборки. Exact reportId, без нормализации/перенаправления; strict nullable decision/appeal и Boolean; неизвестные enum остаются UNKNOWN с исходным текстом, без выдуманных действий/сроков. Полевая схема fail-closed: неожиданные поля требуют отдельной проверки, raw map не сохраняется. Общий UTF8 budget65536 — локальная защитная граница, не юридический лимит; превышение отклоняется, тексты не обрезаются. Собственные модели/ошибки не печатают приватные данные и не сохраняют исходную SDK cause.

Repository имеет только read: exact account/revision/backend/readiness/selection до gate, после ожидания, после чтения/после gate; исходная отмена действует даже при NonCancellable. Offline/permission/missing/invalid/unknown различаются, поздний ответ/ошибка после потери контекста отбрасывается. Нет auto retry/cache/journal/mutation/direct case query. Автор контента не обязан быть owner; будущий adapter должен подтвердить actualSDK/активность/верификацию и существующую политику readyForActions. Все5 DSA endpoints включая read пока закрыты, положительный existing endpoint anchor проверен.

Immutable work/android-a05-statement63b-final/source-sha256.txt, source-and-unit.tgz с полными unit XML и APK. Main SHA a786e872d83b4404408cd7d29572db67e5b8567f3de2044ef9247b22b2d9e566; test SHA3efecf1f16f3b2b7cdbc83a4807929183093adeb59228272f625dbc04853b495 (неизменён61c). Логи outputs/android-a05-statement63{,b}-build.log,63b-format-check.log,63b-baseline-check.log. Все текущие build/format сессии завершены.

**Далее64:** небольшой Auth scope/adapter и read-only SDK source для getMyDsaStatement, сначала свежая проверка actualSDK/backend binding и existing AuthStore ready-session patterns; затем controlled/native-negative tests, без экрана/мутаций до доказательств. Можно разделить на inert adapter и последующий endpoint enablement при недостатке времени. Чтение отсутствующего/чужого case получает одинаковый NOT_FOUND, не искать другой UID; не использовать full dsaCases или public token portal. Fresh source pointers: SafetyIntegration.kt/FirebaseSafetySource.kt (прочитаны целиком), AuthStore.kt836–853 withReadySession, CallableGateway.kt, CompiledBackend.kt; source+gate обязаны сохранить identity и await actual Task. До SDK реализации прочитать полностью подходящие guards/backend APIs и тестовые fixtures; не копировать owner-only guard в обычный statement read. Полный A05/mutation/retention preflight не завершён. A04 server-fix разрешение по-прежнему отсутствует, удаления отключены. Cloud/credentials/production/iOS/phones/publish/cost/commit/push/agents не затронуты. Срок19UTC/21Вена и существующий heartbeat неизменны.



## Следующая точка62 — 2026-09-03 18:08 UTC / 20:08 Вена

Свежий read-only A05 preflight сохранён в work/A05-local-preflight62.md этой задачи. Выбран следующий63: изолированные модели и read-only coordinator очищенного DSA statement для автора контента, пока без SDK/allowlist/UI. Это не LegalEvidence учёта согласий (A06), не owner-only просмотр чужих дел и не подача апелляции: сервер разрешает её reporter, а statement — target author. Полные dsaCases клиентам закрыты; getMyDsaStatement возвращает ограниченную проекцию без контактов/доказательств/токенов. Android распознаёт уведомление DSA, но маршрут/endpoint пока не подключены. Свежие источники, точные поля/границы и дальнейшие проверки — в preflight62; весь mutation/retention preflight ещё не завершён. Никаких новых runtime/юридических/cloud доказательств не заявляется. Итог61c ниже окончательный, не повторять неизменённый прогон. До21:00 продолжается существующий heartbeat, ACTIVE/target текущей задачи проверены; A04 server-fix по-прежнему без разрешения.


## Итог61c — 2026-09-03 18:07 UTC / 20:07 Вена

Этот итог заменяет прежние записи «Main61 идёт». **На окончательной паре APK: Main35/35 и targeted21/21 на каждой API —56 успешных выполнений на каждом эмуляторе.** API37 Main340.578s/font100%, targeted21.797s/font200%; API26 Main204.359s/targeted13.397s/font200%. Все сессии завершены. Основной шрифт возвращён1.0, совместимый оставлен2.0; installed test37 SHA подтверждён.1667unit/86XML/0failure-error-skip — свежий результат60c, задача unit в61c UP-TO-DATE; APK/lint61c13s, format/diff PASS, lint0errors/33warnings/1hint.

61c меняет только ожидания готовности в двух тестах: merged visible primary tabs в PersonalJourney и актуальная не загружающаяся страница перед read-only scroll в AttendeesJourney. Проверки доступа/количества и действия не ослаблены. Первые Main61 дали34/35 каждый; изолированный неизменённый повтор2/2 каждый сохранён как диагностика, не ретроактивный PASS. Для attendees наблюдалась refresh/loading race; точная причина отсутствия merged tab в исходном Personal сбое не доказана. Финальный полный повтор35/35 оба подтверждён отдельно.

Immutable work/android-a04-regression61c-final: полные504 исходника/manifest/archive,13 affected manifest, APK и unit XML.504/504 текущих SHA проверены после тестов. Main SHA48162b74684148ab54de6d2c71afd76852eaa722f2442087db8ba20da4ba4258 (неизменённый60c); test SHA3efecf1f16f3b2b7cdbc83a4807929183093adeb59228272f625dbc04853b495. Logs outputs/android-a04-regression61c-{main,targeted}-api{37,26}.log; исходные61/isolated и60/60b сохранены. Это локальные AVD-доказательства, не cloud/physical device/positiveTOTP/release. Точная очистка собственных journal fixtures проверена; не заявлять полную очистку всех старых Main-auth fixtures.

Дополнительная сверка iOS UserProfileService.swift467/849: поиск owner inbox также по загруженному окну100; Android явно сообщает о загруженной части50+loadmore. iOS read/listen сообщений не делает auto mark-read; флаги меняют reply/close. Не выдумывать global full-text или auto-read-receipt как подтверждённые обязательные функции паритета.

**Далее62: свежая read-only проверка A05 case/statement/decision/appeal, доступа и существующих iOS/backend контрактов.** Никаких юридических решений/новых privileged endpoint/серверных изменений без отдельного обоснования и разрешённого объёма. A04 удаление/SDK/dispatch/UI и global-clear остаются закрыты; отдельное разрешение на server BulkWriter helper/tests не получено. Cloud/credentials/production/iOS changes/phones/publishing/cost/commit/push/agents не затронуты. Поручение до19UTC/21Вена и существующий heartbeat сохраняются; по сроку сохранить точку и приостановить его.



### Актуализация A04 inbox60c, 2026-09-03 17:50UTC

Management inbox получил поиск token-AND/DE-UK, status groups/ALL/UNKNOWN, activity sort и counts **только загруженных строк**, с явной partial-подписью и Load More при0результатов. Это не глобальный поиск/сортировка всей базы и не полный iOS parity. Legacy statuses и exact lastMessageAt/fallback поддержаны.1667unit/APKs/lintPASS;21native обеAPI/font200PASS после доказанного исправления IME unchanged callback. Main61 regression идёт. Deletion/source/dispatch/global-clear/legal case workflow/realTOTP/cloud gates остаются открыты.

### Актуализация A04 read-only58, 2026-09-03 17:19UTC

Проверка свежей версии и read-only восстановление незавершённой операции готовы локально:26new/full1642unit/APKs/lintPASS. Нет actualSDK/send/UI/write/clear; server gate без ответа, fullA04 не закрыт.58неустановлена, runtime остаётся57b/54f по конкретной версии. Следом59 свежий preflight inbox filter/search/sort с явными границами пагинации, не удаление и не mark-read mutation.

### Актуализация A04 recovery57b, 2026-09-03 16:57UTC

Raw-parent version/recovery и durable journal готовы локально:1616unit/APKs/lintPASS,9native на каждойAPI,57binstalled. No private text persisted, explicit unknown/read-absence, no auto-retry/clear; actual count1 never proves full cascade. SDK/dispatch/UI удаления по-прежнему отсутствуют, server gate без ответа, fullA04 не закрыт. Далее независимая read-only часть58; предыдущие Main/regression результаты остаются привязаны54f, не57b.

### Актуализация A04 preflight56b, 2026-09-03 16:22UTC

Начат недостающий owner-only single-feedback delete: pure policy/wire21tests/full1586unit/APKs/lintPASS, без UI/dispatch. Existing reply/close не переписаны. Выявлен source+fault-model server gate: индивидуальная ошибка BulkWriter не передаётся helper, который ждёт только close; запрос на локальное исправление/тесты ещё без ответа. Пока отправку удаления не включать; далее независимые raw-version/journal/recovery или read-only функции. Global-clear/positiveTOTP/cloud/fullA04 не закрыты. Не считать новый56 проверенным55runtime: обаAVD остаются54f.

### Актуализация A03 regression55, 2026-09-03 15:52UTC

A03 локально реализован и прошёл запланированную регрессию:1565unit/APKs/lintPASS;56integration+35Main+229remaining UI на каждойAPI,320 executions/319unique methods, без FAIL/SKIP. Immutable54f, source491/491, exact hashes/checkpoint сохранены. Это не positive realTOTP/cloud proof и не release readiness. Следующий незавершённый пункт — A04 support owner delete/clear с обязательным свежим preflight; reply/close уже имеются, глобальная очистка общей базы не разрешена.

### Актуализация A03 Main54f, 2026-09-03

Роли интегрированы в общий экран и Main: host/privacy/owner loss, собственный результат, unknown recovery и совместимость со статусами проверены. Final1565unit/APKs/lintPASS; **56/56 обеAPI/font200**. Исправлена воспроизводимая потеря обновления UI при одинаковом raw reread, без ослабления version/access gates. Полная регрессия55 ещё идёт; trueTOTP/cloud не доказаны. A03 local integration готова, полное закрытие этапа пока не объявляется.

Baseline 2026-09-02, `c9c2a69`. Это полный реестр обнаруженных продуктовых областей, а не заявление о переносе. Детальный машинный индекс: `Contracts/Android/source-catalog.json` (каждая операция, тип, wire mapping, endpoint и путь Rules со строкой исходника). Список экранов охватывает `Views/`, `Features/SystemLogs`, сервисы auth, notifications, drafts, analytics; старый удалённый Guide не возвращаем.

### Актуализация A03 protected UI53, 2026-09-03

Owner-only DE/UK Compose panel готов: exact role transition/reason, assignment metadata eligibility, Auth-independent removal, protected window/pending/outcome. Full1557unit/APKs/lintPASS; final53e25/25 на обеихAPI/font200, включаяUI15, journal8, actualSDKnegative2. Начальные scrollFAIL сохранены; итоговый test-only viewport readiness не устанавливает точную причину исторического сбоя. Main роли ещё не подключены; далее54 integration/lifecycle/sibling checks и полная регрессия. PositiveTOTP/cloud не доказаны, A03 ещё не закрыт.

### Предыдущая точка A03 ViewModel52, 2026-09-03

Готова owner-only модель экрана/восстановления и защищённое чтение Auth metadata для назначения.45VM+6repository new tests/159A03targeted/full1557unit, обаAPK/lint PASS. Сам Compose UI и Main wiring ещё не добавлены; native evidence остаётся51/47/44 по версии. Следующий шаг53 — защищённый DE/UK UI и native проверки, затем интеграция/регрессия. PositiveTOTP/cloud не доказан; A03 целиком не закрыт.

### Предыдущая точка A03 SDK51, 2026-09-03

Firebase adapter и exact2 bounded/nonIdempotent role calls реализованы. Full1506unit и actualSDKnegative2+journal8 на каждойAPI PASS;42ACCESS denials/0gateway-reference creations. PositiveTOTP/cloud и MainUI пока не доказаны; далее52 protectedVM/UI/integration и регрессия. Нельзя считать A03 завершённым по одному SDKnegative.

### Предыдущая точка repository50

Добавлено управление операциями/восстановлением:44pure repository tests и full1488unit PASS. Firebase adapter и UI пока отсутствуют, callable allowlist ещё закрыт. Native8journal принадлежит49, не50. Следующий шаг — реальный локальный SDK adapter с owner/TOTP negative tests, затемUI; облачная пауза сохраняется.

### Предыдущая точка recovery49

Main regression47 закрыта35/35 на обеAPI, исходные44FAIL сохранены. A03 начат локально: contract48+raw-version/durable-journal49, full1444unit и nativeJournal8/8 на каждойAPI прошли. Repository/SDK/source/UI ещё не подключены; целикомA03 не завершён. Ниже recovery44 — историческая точка, актуальная очередь вверху overnight checkpoint. Cloud/credential pause остаётся обязательной.

### Историческая проверка recovery44

A02-A: пять действий со статусом пользователя локально реализованы, включая подтверждение выбранного пользователя, сохранение результата попытки и явный отказ слишком длинной вставки. Recovery44:1398/1398unit, обаAPK/lintPASS; actual targeted42/42 и broadUI247/247 на каждойAPI26/37/системныйшрифт200%; MainAPI26 35/35PASS, MainAPI37 33/35 с двумя timeout (отменаPhotoPicker/inbox→feedback). Изолированный повтор2/2PASS не доказывает причину или исправление; диагностика передA03 остаётся открытой. Подробности — верх `AndroidOvernightCheckpoint-2026-09-02.md`. SDK-negative не подтверждает positiveTOTP; cloud/credential pause сохраняется.

A03 platform roles: есть локальный preflight и прежний server-local probe44cases/2539checks; Androidsource/UI/realTOTPpositive ещё не реализованы/не доказаны. Maincloud/FCM, оставшиесяadmin/planning и releasegates открыты. Исторические записи ниже о том, что A02mutations отсутствуют, больше не описывают текущие исходники.

### Итоговая локальная проверка, 2026-09-03 09:56 UTC

Snapshot39: обаAPK/lintPASS12s, unchanged1280unit from full36, main identical36–39. Полный Main API37/snapshot37/font100 **35/35 PASS334.797s** и API26/snapshot39/font200 **35/35 PASS198.263s** (каждый28Main+7cleanup-policy). Component235/235 на обеихAPI приfont200:26/snapshot36 и37/snapshot37. Targeted39 API37 management+registrations+policy9/9PASS18.757s. Compact/adaptive navigation и guest moderation checks пройдены; старые pending36 ниже теперь исторические.

API26 failed37 AVD guard и failed38 LinkedHashSet cleanup linkage сохранены и исправлены только в test harness; полный39 подтверждает повтор. Exact38 six docs+twoAuth очищены root и независимо подтверждены отсутствующими. Known local Registration DELETE500/read404 warning не выдаётся за исправленный транспорт. Границы A01-C, реальногоTOTP/cloud/MainFCM/admin/planning/legal/signing/OEM остаются такими же. Следующий этап: отдельный test-cloud Main provider; конкретные критерии сохранены в outputs текущей задачи `ANDROID-NEXT-STEP-TEST-CLOUD.md`.

### Историческое уточнение ночной карты, 2026-09-03 09:23 UTC

**Snapshot36: 1 280/1 280 unit, оба APK и lint PASS за 35s; failures/errors/skips — 0, Kotlin compiler warnings — 0.** Лог `android-adaptive-navigation-cleanup-build-36.log`; результаты сборки не являются результатами ещё выполняющихся native-проверок. Новая адаптивная навигация, повтор регистраций и guest Main36 на момент обновления **не отмечены PASS**. Checkpoint/Status ведутся root отдельно.

- **A01-C локально реализован и проверен, не только preflight.** Три действия заявки (approve/request revision/reject) подключены отдельной моделью к Main moderation; 38/38 pure, UI9/9 + Device7/7 на каждой API26/API37 при настоящем OS font200%. Device7 проверяет native durable journal/faults, named gateway и реальные непривилегированные/no-TOTP отказы; это не положительный привилегированный вызов. Snapshot35 API37 batch21/21 PASS25.915s; API26 A01-C16 + shared ModerationUI4 PASS, один guest Main below-fold wait оставлен отдельным повтором36. Подробности: `ANDROID-A01C-ORGANIZATION-REVIEW-RESULT.md` и `android-a01c-api{26,37}-runtime-35.log` в outputs текущей задачи.
- **Граница A01-C остаётся явной:** displayed fingerprint — клиентская предварительная сверка, не server CAS. Backend не имеет expected-version/idempotency key, response updatedAt не commit server timestamp, notificationId не гарантирует inbox для отсутствующего/ограниченного submitter. Durable pending и read-only reconciliation исключают автоматическое повторное отправление; real Android TOTP-positive/cloud review ещё не доказан.
- **Старые записи ниже — история.** U19 exact-version SDK/Main, API26 startup/locale/picker, A01-B, O06 recovery/create-only scheduling и target-scoped scheduler уже имеют поздние локальные доказательства. Ошибка первого compile34 и focus matcher34 устранены и перепроверены35; не переносить их в текущие blockers. Полная совокупная регрессия, весь TalkBack/OEM/performance и signed-in visual matrix от этого не становятся завершёнными.
- **Открытые релизные gates:** основной app остаётся local-only, без test-cloud/release provider и Main FCM lifecycle; real privileged TOTP, оставшиеся A02/A03/admin/owner-planning функции, Android legal/Data Safety, signing/Play и физические/OEM проверки. Локальные Rules изменения не были production deployment. U19 future-ACK finding уточнён как own timestamp integrity-hardening: canonical status mutation сбрасывает ACK; обход роли/блокировки или подавление всех последующих notices не установлен.

**Следующий конкретный этап:** получить итог текущих36 тестов → отдельно согласованный test-cloud provider и реальные сервисные read-back → real TOTP/privileged A01-C и Main FCM account ownership/delivery → оставшиеся admin/planning пакеты по выбранному релизному scope → privacy/legal/подпись/Play по отдельному решению. Полный паритет build65 и готовность к выпуску пока не заявляются.

### Историческое уточнение ночной карты, 2026-09-03 09:10 UTC

Snapshot33:1233/1233 unit, обаAPK/lintPASS. Main26/27; один DELETE500 в тестовой очистке регистраций исследуется. API26 native Gallery/picker теперь полныйPASS, Cover остаётся повторить после узкой совместимости harness. Broad component snapshot32 API37 226/226, API26 225/226; Foundation scroll assertion correction pending. A01-C organization-review source independently reviewed/promoted but build34 first compile failed, not yet completed or privileged-positive verified. Compact guest auth header source only exact3 routes awaits actual visual checks. Release gaps below remain: local-only Main, no integrated MainFCM/cloud variant, incomplete admin/planning, OEM/accessibility/signing/legal gates. Current exact continuation: AndroidOvernightCheckpoint-2026-09-02.md 09:10.

### Историческое уточнение ночной карты, 2026-09-03 08:37 UTC

Snapshot30:1227/1227 unit,обаAPK/lintPASS. Более ранняя таблица06:48 ниже сохранена как историческая, не текущее завершение. U19 exact-version own-status ACK теперь имеет SDK2/Main2 и API26 Main/UI proof; legal/MFA priority сохраняется. U06 причинно исправляет наблюдавшийся−107ms pre-dispatch clock skew строго ограниченным cancellable wait,9pure+6Main+native timer2/2 на каждойAPI26/37. AppLock настоящий PIN/lifecycle полныйPASS на обоих эмуляторах; PIN очищены/SID0. Gallery реальный API37 IME pan исправлен/пройден; API26 native picker ещё требует test-only DocumentsUI harness. EXIF tinyJPEG API26all8 orientation/metadata теперьPASS после узкого parserfix. A01-B atomic content decisions/receipt/pending local proof завершён, real privileged TOTP positive не подтверждён; A02 read-only user catalog есть, user mutations нет. A01-C org review только текущая ограниченная разработка, без claimCAS/idempotency. Основной Main regression25/28; runnerfont corrected1/1, authoring/cover intermittent confirmation diagnostic остаётся. Main cloud variant/FCM, часть admin/planning, physical/OEM, signing/Android legal/DataSafety и релизные gates открыты. Следующий шаг: source31 actual26 picker/confirmation trace → reviewed A01-C → итоговый аудит.

## Роли: не смешивать уровни

Все write-возможности дополнительно проверяются сервером: подтверждённый email, активный аккаунт (`active`/`warned`), требуемый TOTP, область конкретной организации. Видимая кнопка не является разрешением.

| Роль/состояние | Контракт |
| --- | --- |
| Гость | Публичный approved-контент, legal, donation config, публичные медиа согласно Rules; нет личных записей/действий |
| Неподтверждённый email | Auth/profile/onboarding; не считать обычным verified user для protected mutations |
| Пользователь | Собственные профиль, лайки, bookmarks, subscriptions, регистрации, комментарии, feedback, блокировки; заявки организации |
| Член/подписчик | `communityMemberships.member` не даёт elevated прав. Подписка хранится отдельно. Не выводить права из membership cache |
| Модератор организации | `organizations/{id}.moderatorIds`: контент/модерация/фото этой организации; не команда и не произвольная другая организация |
| Администратор организации | `adminIds`: дополнительно профиль организации; не передача владения/управление командой по одному admin-флагу |
| Владелец организации | `ownerId`: команда и допустимые операции своей организации; transfer ownership в фактическом текущем callable доступен только app owner, не org owner |
| App Admin | `users/{uid}.globalRole=admin`: заявки, платформенная модерация, reports/feedback, допустимые user targets; нет автоматического org override и назначения app admin |
| App Owner | `globalRole=owner`: платформенные owner tools и org override; ownership arrays не переписываются от самого override |
| Legacy `role=moderator/admin/owner`, `topAdmin`, `moderatorSections` | Декодируются для совместимости, не дают глобальную авторизацию. `topAdmin` нормализуется к user |
| Suspended/banned/deactivated | Не выполнять активные пользовательские действия; status notice, восстановление/поддержка в пределах существующих правил |
| Защищённый owner/admin | Backend требует `firebase.sign_in_second_factor=totp`, если `requiresMultiFactorAuth=true`; iOS дополнительно ведёт через enrollment/активацию до открытия protected UI |

Источники: `Services/PermissionService.swift`, `Models/UserModels.swift`, `functions/src/permissions/`, `functions/src/auth/context.ts`, Firestore/Storage Rules. Ограничения конкретных targets и system organizations обязательны.

## Функции и этапы

Ниже сохранён baseline-реестр и исторический результат пакета 2. Текущее ночное состояние обновляется в AndroidMigrationStatus.md и AndroidOvernightCheckpoint-2026-09-02.md; отсутствие отметки в исходной таблице не означает, что позднейшая реализация не начата. Emulator-проверка не равна cloud/production-паритету.

### Ночная функциональная карта, 2026-09-03 06:48 UTC

| Область | Подтверждено локально / текущий пакет | Существенный остаток |
| --- | --- | --- |
| U01/U02/U19/U20 | Email/session restore/legal receipts и account-state gates, unit/UI/SDK journeys | Cloud email/action links, native push cleanup, статусные углы и финальная регрессия |
| U03 | Native TOTP UI/domain и local negative activation verified | Real cloud enrollment/privileged positive session; irreversible test Identity Platform upgrade требует отдельного согласия |
| U04/U06 | AppLock pure/UI6/Window5 + full native PIN Journey1 PASS657; U06 cascade/Main/cold2 PASS | Physical biometrics/OEM; intermittent restricted RECENT_AUTH_REQUIRED repeated PASS560 but root cause not conclusively proved |
| U05/U07/U08 | Profile + private/public avatar upload + dirty draft + markers/lists, actual avatar Journey PASS; orphan target SDK regression PASS803. Subscriber SDK3 PASS866, UI6/Main1 PASS945 including55-row paging/live membership/back/logout | Broader cloud/device regression; original cleanup500 cause unknown, exact fixtures confirmed absent |
| U09/U10 | Register/cancel/comments actual callable + Rules/read-back; own-registration list unit14/UI3/MainJourney1 PASS на snapshot350 | Scope/counts/past/upcoming/foreign isolation проверены локально; attendees отдельный privileged пакет, cloud не доказан |
| U12–U14 | Reports/blocking/fail-closed projection и actual Safety Journey PASS | Personal regression выявила transient Safety OFFLINE; visible retry proof в работе, guard не отключён |
| U15–U17 | Inbox/preferences/Main/popup PASS; isolated FCM probe24unit + actual foreground/background/cold/tap/opt-out404. Full native reminder839 PASS169.237s including clean host destruction; cold positive845 system-created process/private notification1/receipt1/cleanup PASS; cold Doze866 real system dispatch in deepIDLE, terminal suppression, no replay after registration restoration and cleanup PASS | Main FCM token ownership and cloud/OEM delivery remain separate; no physical phone tests |
| U18/A04 | Own Feedback create/reply/retry/notifications/scope actual PASS; management reply/close implemented | Privileged positive TOTP/session; owner delete/clear и полный A04 |
| O01/O02 | Own application + organization-rules proof + native logo picker + review/resubmit/discard actual Journey PASS | Platform review/approve UI и privileged positive cloud paths |
| O03/O04 | Editor/team/role source integrated, unit42/UI8/Device2/Main1 PASS | Transfer только app owner, positive Android cloud TOTP proof не подменять backend fixtures |
| O05–O10 | C1 real text authoring Device2/Main1+UI11 PASS1048; O10 attendee Device2/UI5/fullMain1 PASS; C2 cover Device2/UI7/raster1 and three fresh Main journeys PASS; O09 actual Main/SDK/Rules DENIED PASS. O06A encrypted recovery39pure/UI7/SDK1/full cold Main PASS1004, native7 PASS1048. O06B27pure/UI8/actualSDK2/Main1 PASS1048, exact create-only scheduled receipt. O08 SDK2/journal4/cold3 PASS949/UI7 PASS1004, actual managementMain PASS19.187s1004/publicMain PASS15.183s1036; strict binary overwrite protection/all Rules165 PASS | Target-scoped scheduler worker proof in preparation; schedule change/cancel and owner planning not ported. Earlier C2 MISSING_ASSET cause unproven; no cloud Rules deploy |
| B01–C09, visual | Original assets/theme/four-tab histories/startup5/native video1 PASS; Chrome200%/landscape/IME/draft PASS; compact cards4/hero6. Fullscreen legal/Main actual system100%2/2 PASS25.347s and200%2/2 PASS23.373s1048; light system-icon contrast visually fixed. Public grid/pager Main verified above. Pinned source formatting applied22 with377 normalized lexical payload matches and full1036→1048 build/unit proof | Old Auth/Browse tests require actual new reader/gallery navigation; source24 corrections and actual-density/long-title repeat pending. API26 compatibility underway, not yet blanket PASS. Full TalkBack/performance/signed-in visual audit and picker locale runtime remain |
| U11 | Own recent/activity + immutable view markers/confirmed action callbacks integrated; UI5 PASS745; Device2/fullMain1 PASS757 including capped missing/private targets | Broader final regression/cloud proof remain; local capped-target defect closed |
| A01–A12/X03 and remaining O slices | A01 read-only queue/preview30pure/UI4/SDK-negative2/guestMain1 PASS1036 with actual TOTP gate. Isolated atomic moderation Rules63/63 PASS,155 exact fixtures cleaned; bounded Android A01-B source24 in progress, Main integration unbuilt | Privileged actual MFA remains blocked externally; synthetic Rules claims are not native proof. Organization moderation and A02–A12 remaining tools/release/cloud/device gates not complete; do not consider release-ready |

Указанные actual результаты относятся только к вымышленным данным локального тестового сервера и Mac AVD. Production, публикация и рабочий телефон не изменялись.

| Строки | Локальный результат пакета 2 | Остаточная граница |
| --- | --- | --- |
| B01–B02 | Публичная навигация, detail/back, сохранение route/фильтров/числа страниц, Activity recreation | Auth startup/session — пакет 3; tablet/physical UI — пакет 5 |
| B03 | uk/de, fallback, мгновенная смена текста, system/light/dark, проверки на AVD при 200% шрифта, semantics/alt/heading | Полный ручной TalkBack-аудит и реальные устройства — пакет 5 |
| C01 | Главная собирает последние элементы трёх публичных списков, единый регион, переходы к полным спискам/деталям | Только synthetic/demo; нет персональной аналитики |
| C02 | Порядок priority/updatedAt/ID, сроки/секция/регион, локализация, внутренние actions, проверенные внешние ссылки; ручная карусель и включаемый таймер | Cloud-медиа не загружаются; управление — пакет 4. Отдельного role-audience-поля в текущей схеме нет |
| C03–C04 | Новости: поиск по тексту/тегам через backend-страницы, категории, регион, cursor, рекомендации; детали/источник/alt/credit/внешнее действие | Все account actions — пакет 3 |
| C05–C06 | Upcoming/past, endDate cursor, категории/аудитория/регион/поиск, рекомендации; даты/occurrences/all-day/cancelled, цена/вместимость/контакты/внешние tickets | Регистрация — пакет 3; persisted timezone редактора не выдумывается |
| C07–C08 | Каталог/детали, профиль/миссия/услуги/часы/предложение, контакты/карта с подтверждением, галерея, связанные news/events | Реальные внешние приложения не запускались тестами; upload/editor — пакет 4 |
| C09 | Только публичные displayName/city команды из publicProfiles, не users | Идентичности подписчиков требуют auth; пакет 3 |
| U21 | Публичный donation config, показ/копирование/переход по валидному URL | Настройки owner — пакет 4; деньги не собирались, .invalid links не открываются |
| X02 | Публичный диск-cache с TTL/лимитом и отметкой времени, denial/deletion не маскируются cache, cancellation/retry, отсутствие скрытых записей | Account-switch/deferred writes/background sync — пакеты 3–5 |

Доказательства: unit `ContentReadTest`/`BrowseStateTest`, device `BrowseUiTest`/`ContentDeviceTest`/`MediaUiTest`, 33 новых query/Rules assertions поверх 9 foundation assertions. Финальные журналы и runtime-снимки перечислены в AndroidMigrationStatus.md.

| ID | Сценарий, включая скрытые состояния | Доступ | Источник/контракт | Пакет |
| --- | --- | --- | --- | --- |
| B01 | Startup gate, splash, сохранённая сессия, background/foreground; не останавливать музыку | Все | AppContainer, AppStartupGate, SplashVideoBackground | 2/3 |
| B02 | Навигация главная/новости/події/организации/профиль, back/detail restoration, большие экраны | Все | ContentView, ProfileRootDestinationViews | 2 |
| B03 | Украинский/немецкий, мгновенное обновление баннеров; system/light/dark; font scale/TalkBack | Все | LocalizationStore, UserSettings, FeaturedBanner | 2–5 |
| C01 | Главная: подборки/последнее/регион/переходы | Все | HomeView, HomeViewModel | 2 |
| C02 | Featured carousel: порядок, активность, сроки, аудитория/регион, локализованный текст/изображение/action | Все/owner management | FeaturedBannerRepository, FeaturedBanner | 2/4 |
| C03 | Новости: список, регион, категории/теги, поиск, рекомендации, page cursor | Все | NewsViewModel, FirestoreNewsRepository | 2 |
| C04 | News detail: источник/организация, текст, media metadata/alt/credit, внешнее действие, loading/not-found/denied | Все | NewsDetailView, ContentDetailLoadState | 2 |
| C05 | События: upcoming/recent past, фильтры/поиск/категории/audience, регион, рекомендации | Все | EventsViewModel, FirestoreEventRepository | 2 |
| C06 | Event detail: occurrences/all-day/cancelled, цена/диапазон/валюта, вместимость, адрес/контакты/внешние билеты | Все | EventDetailView, EventMetadataSections | 2 |
| C07 | Организации: каталог, поиск, регион/категории, карточки, пагинация | Все | OrganizationsViewModel, FirestoreOrganizationRepository | 2 |
| C08 | Org detail: profileKind, mission, услуги/режимы/часы/предложение, карта-переход/контакты, галерея, связанный контент | Все по Rules | OrganizationReadOnlyDetailContent, OrganizationDirectoryProfile | 2 |
| C09 | Публичные профили/команда и список подписчиков (санитизированные данные) | Verified active для subscriber identities | publicProfiles, subscriber cursor | 2/3 |
| U01 | Email registration/login/logout/reset/verification/resend, password policy и правовые согласия | Гость/свой аккаунт | AuthService, UserProfileService, LegalCompliance | 3 |
| U02 | Сессия после перезапуска, refresh claims, account switching и удаление именно текущей push-регистрации | Свой аккаунт | AuthState, NotificationPushTokenOwnershipCoordinator | 3 |
| U03 | TOTP enrollment/QR/manual secret/challenge/retry/reauth/unenroll; сохранение challenge при переходе в authenticator | Protected roles | AuthMultiFactorService, activatePrivilegedMFAProtection | 3 |
| U04 | Локальная биометрическая блокировка отдельно от серверного MFA | Свой аккаунт | AppLockService, BiometricLockViews | 3 |
| U05 | Редактирование имени/displayName/city/bio/Telegram/региона/avatar, восстановление public profile | Свой аккаунт | EditableUserProfileDraft, UserProfileService | 3 |
| U06 | Удаление аккаунта: reauth, owned-org gate, каскады/анонимизация и sign-out | Свой аккаунт | deleteOwnAccount, accountDeletionPolicy | 3 |
| U07 | Лайки news/event/org; bookmarks; сохранённый контент | Verified active | likes, user bookmarks, ProfileSavedContent | 3 |
| U08 | Подписка/отписка org, community subscriber page, account race isolation | Verified active | likes/organization_follow_{orgId}_{uid}, subscribedOrganizationId, publicProfiles | 3 |
| U09 | Регистрация/отмена: full/past/cancelled/not-required, transactional count; мои регистрации | Verified active | registerForEvent/unregisterFromEvent, MyRegistrations | 3 |
| U10 | Комментарии: realtime/add, автор/блокировки, scoped moderation/delete; self-edit недоступен в фактическом build65 | Verified active/scoped moderation | saveComment только CREATE; Swift update методы permissionDenied; delete по canModerate*Comment Rules | 3/4 |
| U11 | Просмотры/recent views/activity history, дедупликация, очистка доступной истории | Пользователь | users/{uid}/newsViews,eventViews,recentViews,activityLog | 3 |
| U12 | Жалоба на news/event/org/comment, причины/urgent/SLA и результат | Verified active | submitContentReport, ContentSafetyModels | 3 |
| U13 | Блок/разблок пользователя; фильтрация связанных материалов | Пользователь | setUserBlocked, UserBlockingRepository | 3 |
| U14 | Блок/разблок конкретной организации, не всех org владельца | Пользователь | setOrganizationBlocked/getBlockedOrganizations | 3 |
| U15 | Настройки уведомлений, permission denied/system settings, test local, reminder lead/reconcile | Пользователь | NotificationPreferences, LocalEventReminderService | 3 |
| U16 | Inbox/list/detail/popup, unread/read/all-read, archive/delete/clear, badge invariant | Свой аккаунт | NotificationInboxRepository | 3 |
| U17 | Push foreground/background/cold start, channel/permission, token rotation/account cleanup, все маршруты | Свой аккаунт | RemoteNotificationRoute, inboxPushDelivery | 3; cloud gate |
| U18 | Feedback: вопрос/идея/bug, conversation/messages/reply/status/unread; self delete/clear запрещены в фактическом build65 | Пользователь | FeedbackViews, FirestoreFeedbackRepository в UserProfileService; deleteMyFeedback/clearMyFeedback всегда permission-denied | 3 |
| U19 | Account status/warnings/reason/acknowledgement; legal update gate | Пользователь | AccountStatusMonitorService, LegalComplianceMonitorService | 3 |
| U20 | Legal reader: terms/privacy/org rules, версии/согласие/receipt; внешние support/imprint links | Все/свой аккаунт | LegalDocumentRepository, acceptLegalDocument, acceptOrganizationRules | 3 |
| U21 | Donation display/copy/link и owner-настройки | Все/owner | DonationConfig, DonationSettingsView | 2/4 |
| O01 | Заявка org: создание/согласие с правилами/logo → review → revision/reject → resubmit → approve | Пользователь + app admin/owner | approvalWorkflow, OrganizationManagementHub | 4 |
| O02 | Незавершённая заявка: discard, предупреждение и expiry; недоступный target уведомления | Автор + backend | organizationRequestRetention, OrganizationRequestNotificationDestination | 4 |
| O03 | Редактирование профиля/контактов/каталога org, pending constraints, system-org distinction | Org owner/admin, app owner | OrganizationEditor, PermissionService | 4 |
| O04 | Назначить/удалить org admin/moderator; transfer ownership; повторный вызов/смена прав | Org owner/app owner | roleManagement, OrganizationTeamViewModel | 4 |
| O05 | Создание/редактирование news и event: source org, uk/de, категории, media, validation | Org team/app owner | NewsEditor/EventEditor, publishing models | 4 |
| O06 | Draft recovery локально, pending/approved, расписание публикации/отмена/архив | По scoped permissions | LocalDraftRecoveryService, scheduledPublishing | 4 |
| O07 | Обложки: crop/orientation/JPEG/лимиты, upload state/retry, canonical paths | По scoped permissions | ImageUploadService, uploadOrganizationContentCover | 4 |
| O08 | Org photos: gallery/upload + caption/metadata, лимит 30, delete/rollback | Org team/app owner | OrganizationPhotoRepository, photo mutations | 4 |
| O09 | Удаление news; отмена event и уведомления; удаление org при допустимых зависимостях | Org owner/app owner по callable | contentDeletion, cancelEvent | 4 |
| O10 | Просмотр регистраций/attendees для управляемого события | Scoped authoring permissions | fetchEventRegistrations, registration Rules | 4 |
| A01 | Платформенная модерация news/events/org/comments: pending/approve/reject, reports | App admin/owner | ModerationTools, Rules + moderation callables | 4 |
| A02 | User search/security metadata, warn/suspend/ban/deactivate/restore, запрет self/owner targets | App admin/owner с target gates | userManagementQueries, accountStatusManagement | 4 |
| A03 | Назначить/удалить app admin; не добавлять legacy moderator | App owner | platformRoleManagement | 4 |
| A04 | Support inbox, ответы, закрытие/удаление/очистка; unread и уведомления | App admin/owner | FeedbackInboxViewModel, feedback Rules | 4 |
| A05 | DSA case/statement/decision/appeal, human review, сроки/retention; public web portal не переносить в privileged client | Case party / app reviewers | dsaCases, LegalEvidence | 3/4 |
| A06 | Legal drafts/publish, evidence/accounts/user receipts, organization rules | По legal permissions, owner management | LegalDocumentManagement, legalEvidence | 4 |
| A07 | Featured management: create/edit/upload/activate/sort/delete, action validation | App owner | featuredBannerMutations | 4 |
| A08 | Content Planning: drafts/attention/scheduled/history, source checks, missing fields, lease begin/finalize/fail, retry/archive/delete | App owner | OwnerContentPlanning, ownerContentDrafts | 4 |
| A09 | Analytics consent on/off, action proofs/dedupe, owner periods/regions/top content/users/details, timezone/empty/errors | Consent owner / app owner | analyticsConsent, trackAnalyticsEvent, OwnerAnalytics | 3/4 |
| A10 | Presence online/last-seen и managed presence | Свой update / permitted manager read | UserPresenceService, getManagedUserPresence | 3/4 |
| A11 | System logs: filtering/detail/review/delete/clear/metrics, visibility и retention; client diagnostics sanitization | Scoped org/platform roles | Features/SystemLogs, systemLogManagement | 4 |
| A12 | Owner push diagnostic и system announcements, если доступно текущим UI; server-only endpoints не создавать как новые экраны | App owner | sendTestPushNotification, createSystemAnnouncement | 4 |
| X01 | Каскады/retention/orphan cleanup/идемпотентность: использовать сервер, не удалять локально наполовину | Backend | AndroidBackendCompatibility lifecycle table | 3/4 |
| X02 | Offline/cache/stale permissions, deferred writes, reconnect, duplicate taps, cancellation; negative tests | Все | Каждая строка выше | 2–5 |
| X03 | Реальное Android-устройство, Play Integrity, TOTP, FCM, background/Doze, weak network, release privacy/signing | Отдельное согласование | AndroidMigrationPlan | 5 |

## Критерий доказательства для продуктовой строки

Зафиксировать позитивный и негативный сценарий, начальную роль/статус, fixture, итоговый document/read-back, побочное уведомление/его отсутствие, retry/offline/account switch, uk/de + large text + TalkBack. При server-only функции указать зависимость и не создавать лишний клиентский UI. Обнаруженная несовместимость оформляется отдельно; не портировать заведомо неверное поведение ради буквального совпадения.
