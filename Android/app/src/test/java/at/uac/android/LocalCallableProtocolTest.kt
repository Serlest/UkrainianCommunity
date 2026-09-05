package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import org.junit.Assert.*
import org.junit.Test

class LocalCallableProtocolTest {
    private val coverName = "uploadOrganizationContentCover"

    private fun cover(
        image: Any? = "AAAA",
        kind: Any? = "news",
        id: Any? = "synthetic-content-01",
    ): Map<String, Any?> = mapOf("kind" to kind, "contentId" to id, "imageBase64" to image)

    private fun fails(code: LocalCallableFailure, block: () -> Unit) {
        try {
            block()
            fail("Expected $code")
        } catch (error: LocalCallableException) {
            assertEquals(code, error.code)
        }
    }

    @Test
    fun exactEndpointAndAllowlistRejectProductionAndPathInjectionBeforeNetwork() {
        assertEquals(
            "http://10.0.2.2:5008/demo-uac-android/europe-west3/saveComment",
            LocalCallableProtocol.endpoint("saveComment"),
        )
        val invalid =
            listOf<() -> Unit>(
                {
                    LocalCallableProtocol.endpoint(
                        "saveComment",
                        project = "uac-android-test-20260903",
                    )
                },
                { LocalCallableProtocol.endpoint("saveComment", host = "cloudfunctions.net") },
                { LocalCallableProtocol.endpoint("saveComment", host = "127.0.0.1") },
                { LocalCallableProtocol.endpoint("saveComment", port = 443) },
                { LocalCallableProtocol.endpoint("saveComment", region = "us-central1") },
                { LocalCallableProtocol.endpoint("../deleteOwnAccount") },
                { LocalCallableProtocol.endpoint("saveComment?target=production") },
                { LocalCallableProtocol.endpoint("deleteAnyAccount") },
                { LocalCallableProtocol.endpoint("sendTestPushNotification") },
            )
        for (action in invalid) try {
            action()
            fail("Unsafe endpoint")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun userManagementReadContractsStayNonMutatingAndUnknownOperationsRemainDenied() {
        for (name in listOf("searchManagedUsers", "getManagedUserSecurityMetadata")) {
            assertEquals(
                "http://10.0.2.2:5008/demo-uac-android/europe-west3/$name",
                LocalCallableProtocol.endpoint(name),
            )
            assertFalse(LocalCallableProtocol.nonIdempotent(name))
            assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(name))
            assertEquals(
                LocalCallableProtocol.MAX_REQUEST_BYTES,
                LocalCallableProtocol.maximumRequestBytes(name),
            )
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(
                    name,
                    "x".repeat(LocalCallableProtocol.MAX_REQUEST_BYTES + 1),
                )
            }
        }
        for (name in
            listOf(
                "blockUser",
                "unblockUser",
                "restrictUser",
                "changeUserRole",
                "getManagedUserSecurityMetadata/../warnUser",
            )) {
            try {
                LocalCallableProtocol.endpoint(name)
                fail("Unknown user management operation must remain unavailable")
            } catch (_: IllegalArgumentException) {}
        }
    }

    @Test
    fun organizationReviewUsesOnlyExactLocalNamesAndOrdinaryBudgets() {
        for (name in
            listOf("approveOrganization", "requestOrganizationRevision", "rejectOrganization")) {
            assertEquals(
                "http://10.0.2.2:5008/demo-uac-android/europe-west3/$name",
                LocalCallableProtocol.endpoint(name),
            )
            assertTrue(LocalCallableProtocol.nonIdempotent(name))
            assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(name))
            assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(name))
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(name, mapOf("message" to "x".repeat(65_536)))
            }
        }
    }

    @Test
    fun organizationReviewDoesNotAllowAdjacentOrInjectedEndpoints() {
        for (name in
            listOf(
                "approveOrganization/",
                "approveOrganization?retry=true",
                "../rejectOrganization",
                "approveAllOrganizations",
                "requestOrganizationRevisionV2",
            )) {
            assertTrue(
                runCatching { LocalCallableProtocol.endpoint(name) }.exceptionOrNull()
                    is IllegalArgumentException
            )
        }
        assertTrue(
            runCatching {
                LocalCallableProtocol.endpoint(
                    "approveOrganization",
                    project = "ukrainiancommunity-dbd5f",
                )
            }
                .exceptionOrNull() is IllegalArgumentException
        )
    }

    @Test
    fun organizationReviewLostResponseCannotBecomeAnOrdinaryRetryableFailure() {
        for (name in
            listOf("approveOrganization", "requestOrganizationRevision", "rejectOrganization")) {
            for (failure in
                listOf(
                    LocalCallableFailure.UNAVAILABLE,
                    LocalCallableFailure.DEADLINE_EXCEEDED,
                    LocalCallableFailure.INTERNAL,
                    LocalCallableFailure.DATA_LOSS,
                    LocalCallableFailure.UNKNOWN,
                )) {
                assertEquals(
                    LocalCallableFailure.UNCONFIRMED,
                    LocalCallableProtocol.transportFailure(name, true, failure),
                )
                assertEquals(failure, LocalCallableProtocol.transportFailure(name, false, failure))
            }
            assertEquals(
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableProtocol.transportFailure(
                    name,
                    true,
                    LocalCallableFailure.PERMISSION_DENIED,
                ),
            )
        }
    }

    @Test
    fun protocolRequestContainsOnlyDataAndEncodesInt64WithoutPrecisionLoss() {
        val encoded =
            LocalCallableProtocol.request(
                mapOf("count" to Long.MAX_VALUE, "text" to "Test", "nullable" to null)
            )
        assertEquals(setOf("data"), encoded.keys)
        val data = encoded["data"] as Map<*, *>
        assertEquals(
            mapOf(
                "@type" to "type.googleapis.com/google.protobuf.Int64Value",
                "value" to Long.MAX_VALUE.toString(),
            ),
            data["count"],
        )
        assertTrue(data.containsKey("nullable"))
        assertNull(data["nullable"])
    }

    @Test
    fun nonJsonValuesNonfiniteAndOversizedInputsFailBeforeTransport() {
        listOf<Any>(
                Double.NaN,
                Double.POSITIVE_INFINITY,
                Any(),
                mapOf("@type" to "forged"),
                mapOf(1 to "bad"),
                "x".repeat(LocalCallableProtocol.MAX_REQUEST_BYTES + 1),
                List(1025) { "a" },
            )
            .forEach {
                fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(it) }
            }
        var nested: Any = "leaf"
        repeat(22) { nested = listOf(nested) }
        fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(nested) }
    }

    @Test
    fun resultAndLegacyDataEnvelopesRetainNullAndTypedValues() {
        assertNull(LocalCallableProtocol.response(200, mapOf("result" to null)).data)
        assertEquals(
            mapOf("ok" to true),
            LocalCallableProtocol.response(200, mapOf("data" to mapOf("ok" to true))).data,
        )
        assertEquals(
            Long.MAX_VALUE,
            LocalCallableProtocol.response(
                    200,
                    mapOf(
                        "result" to
                            mapOf(
                                "@type" to "type.googleapis.com/google.protobuf.Int64Value",
                                "value" to Long.MAX_VALUE.toString(),
                            )
                    ),
                )
                .data,
        )
        val unknown = mapOf("@type" to "future-safe-struct", "x" to 1)
        assertEquals(unknown, LocalCallableProtocol.response(200, mapOf("result" to unknown)).data)
    }

    @Test
    fun errorAlwaysWinsPreservesReasonAndNeverTrustsInvalidStatus() {
        try {
            LocalCallableProtocol.response(
                200,
                mapOf(
                    "result" to true,
                    "error" to
                        mapOf(
                            "status" to "PERMISSION_DENIED",
                            "details" to mapOf("reason" to "test"),
                        ),
                ),
            )
            fail("Error wins")
        } catch (error: LocalCallableException) {
            assertEquals(LocalCallableFailure.PERMISSION_DENIED, error.code)
            assertEquals(mapOf("reason" to "test"), error.details)
        }
        for (status in listOf("OK", "FUTURE", "UNCONFIRMED", null)) fails(
            LocalCallableFailure.INTERNAL
        ) {
            LocalCallableProtocol.response(200, mapOf("error" to mapOf("status" to status)))
        }
    }

    @Test
    fun malformedAmbiguousAndFailedHttpResponsesCannotClaimSuccess() {
        for (data in listOf(emptyMap(), mapOf("result" to true, "data" to false))) fails(
            LocalCallableFailure.DATA_LOSS
        ) {
            LocalCallableProtocol.response(200, data)
        }
        fails(LocalCallableFailure.INTERNAL) {
            LocalCallableProtocol.response(302, mapOf("result" to true))
        }
        fails(LocalCallableFailure.PERMISSION_DENIED) {
            LocalCallableProtocol.response(403, mapOf("result" to true))
        }
        fails(LocalCallableFailure.INTERNAL) {
            LocalCallableProtocol.response(200, mapOf("error" to "not-an-object"))
        }
        fails(LocalCallableFailure.DATA_LOSS) {
            LocalCallableProtocol.response(
                200,
                mapOf(
                    "result" to
                        mapOf(
                            "@type" to "type.googleapis.com/google.protobuf.Int64Value",
                            "value" to "overflow",
                        )
                ),
            )
        }
    }

    @Test
    fun boundedRawBodyRejectsNestingAndTruncationButIgnoresQuotedBrackets() {
        LocalCallableProtocol.validateRawResponse("{\"result\":\"[[[{}\\\" ]\"}")
        fails(LocalCallableFailure.DATA_LOSS) {
            LocalCallableProtocol.validateRawResponse("[".repeat(25) + "]".repeat(25))
        }
        fails(LocalCallableFailure.DATA_LOSS) {
            LocalCallableProtocol.validateRawResponse("{\"result\":")
        }
        fails(LocalCallableFailure.DATA_LOSS) {
            LocalCallableProtocol.validateRawResponse("\"unterminated")
        }
        fails(LocalCallableFailure.DATA_LOSS) {
            LocalCallableProtocol.validateRawResponse(
                "x".repeat(LocalCallableProtocol.MAX_RESPONSE_BYTES + 1)
            )
        }
    }

    @Test
    fun nonIdempotentTransportFailureAfterBodyStartIsExplicitlyUnconfirmed() {
        for (name in
            listOf(
                "saveComment",
                "submitContentReport",
                "acceptLegalDocument",
                "deleteOwnAccount",
                "deleteNews",
                "cancelEvent",
                "assignOrganizationAdmin",
                "removeOrganizationAdmin",
                "assignOrganizationModerator",
                "removeOrganizationModerator",
                "transferOrganizationOwnership",
                "createOrganizationPhotoMetadata",
                "deleteOrganizationPhotoMetadata",
            )) {
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(
                    name,
                    true,
                    LocalCallableFailure.UNAVAILABLE,
                ),
            )
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(name, true, LocalCallableFailure.DATA_LOSS),
            )
            assertEquals(
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableProtocol.transportFailure(
                    name,
                    false,
                    LocalCallableFailure.UNAVAILABLE,
                ),
            )
            assertEquals(
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableProtocol.transportFailure(
                    name,
                    true,
                    LocalCallableFailure.PERMISSION_DENIED,
                ),
            )
        }
        assertEquals(
            LocalCallableFailure.UNAVAILABLE,
            LocalCallableProtocol.transportFailure(
                "registerForEvent",
                true,
                LocalCallableFailure.UNAVAILABLE,
            ),
        )
    }

    @Test
    fun onlyAccountAndNewsDeletionHaveTheExistingFiveMinuteCascadeDeadline() {
        assertEquals(
            "http://10.0.2.2:5008/demo-uac-android/europe-west3/deleteOwnAccount",
            LocalCallableProtocol.endpoint("deleteOwnAccount"),
        )
        assertEquals(300_000L, LocalCallableProtocol.maximumTimeoutMillis("deleteOwnAccount"))
        assertEquals(300_000L, LocalCallableProtocol.maximumTimeoutMillis("deleteNews"))
        assertEquals(
            "http://10.0.2.2:5008/demo-uac-android/europe-west3/cancelEvent",
            LocalCallableProtocol.endpoint("cancelEvent"),
        )
        for (name in
            listOf(
                "deleteOrganization",
                "cancelEvent",
                "transferOrganizationOwnership",
                "assignOrganizationAdmin",
                "saveComment",
                "unknown",
            )) assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(name))
    }

    @Test
    fun galleryMetadataUsesOnlyItsExistingLocalEndpointsAndOrdinaryBudgets() {
        for (name in listOf("createOrganizationPhotoMetadata", "deleteOrganizationPhotoMetadata")) {
            assertEquals(
                "http://10.0.2.2:5008/demo-uac-android/europe-west3/$name",
                LocalCallableProtocol.endpoint(name),
            )
            assertEquals(60_000L, LocalCallableProtocol.maximumTimeoutMillis(name))
            assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(name))
            assertEquals(
                mapOf("data" to mapOf("organizationId" to "org-1", "photoId" to "photo-1")),
                LocalCallableProtocol.request(
                    name,
                    mapOf("organizationId" to "org-1", "photoId" to "photo-1"),
                ),
            )
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name, project = "uac-other")
            }
        }
    }

    @Test
    fun coverAloneReceivesExactEndpointTwoMinuteTimeoutAndLargerRequestBudget() {
        assertEquals(
            "http://10.0.2.2:5008/demo-uac-android/europe-west3/$coverName",
            LocalCallableProtocol.endpoint(coverName),
        )
        assertEquals(120_000L, LocalCallableProtocol.maximumTimeoutMillis(coverName))
        assertEquals(4_194_304, LocalCallableProtocol.maximumRequestBytes(coverName))
        assertEquals(65_536, LocalCallableProtocol.MAX_REQUEST_BYTES)
        assertEquals(262_144, LocalCallableProtocol.MAX_RESPONSE_BYTES)
        for (name in
            listOf(
                "saveComment",
                "deleteOwnAccount",
                "uploadUserAvatar",
                "${coverName}/extra",
                "unknown",
            )) {
            assertEquals(65_536, LocalCallableProtocol.maximumRequestBytes(name))
        }
        for (name in
            listOf(
                "$coverName/extra",
                "../$coverName",
                "$coverName?admin=true",
                "uploadUserAvatar",
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.endpoint(name)
            }
            assertThrows(IllegalArgumentException::class.java) {
                LocalCallableProtocol.request(name, cover())
            }
        }
    }

    @Test
    fun coverUploadIsUnconfirmedAfterAnyUncertainSubmittedTransportFailure() {
        assertTrue(LocalCallableProtocol.nonIdempotent(coverName))
        for (failure in
            listOf(
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED,
                LocalCallableFailure.UNKNOWN,
                LocalCallableFailure.INTERNAL,
                LocalCallableFailure.DATA_LOSS,
            )) {
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(coverName, true, failure),
            )
            assertEquals(failure, LocalCallableProtocol.transportFailure(coverName, false, failure))
        }
        assertEquals(
            LocalCallableFailure.PERMISSION_DENIED,
            LocalCallableProtocol.transportFailure(
                coverName,
                true,
                LocalCallableFailure.PERMISSION_DENIED,
            ),
        )
    }

    @Test
    fun coverSchemaIsExactlyOneBase64FieldAndSupportedKind() {
        for (kind in listOf("news", "event")) {
            assertEquals(
                cover(kind = kind),
                LocalCallableProtocol.request(coverName, cover(kind = kind))["data"],
            )
        }
        for (value in
            listOf(
                null,
                "AAAA",
                listOf(cover()),
                emptyMap<String, String>(),
                cover() - "imageBase64",
                cover() + ("extra" to "x".repeat(70_000)),
                cover(kind = "events"),
                cover(kind = " news "),
                cover(kind = false),
                cover(image = listOf("AAAA", "AAAA")),
                cover(image = mapOf("data" to "AAAA")),
            )) {
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(coverName, value)
            }
        }
    }

    @Test
    fun coverContentIdCannotSmuggleAPathOrOversizedIdentifier() {
        for (id in
            listOf<Any?>(
                null,
                1,
                "",
                " ",
                ".",
                "..",
                "../news",
                "news/a",
                "a/cover.jpg",
                " a",
                "a ",
                "a\u0000b",
                "__reserved__",
                "a".repeat(513),
                "界".repeat(501),
            )) {
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(coverName, cover(id = id))
            }
        }
        LocalCallableProtocol.request(coverName, cover(id = "a".repeat(512)))
        LocalCallableProtocol.request(coverName, cover(id = "界".repeat(500)))
    }

    @Test
    fun base64AlphabetPaddingAndLengthAreBoundedWithoutDecodingJpegInTransport() {
        for (image in listOf("AAAA", "AAA=", "AA==", "/+AA")) LocalCallableProtocol.request(
            coverName,
            cover(image),
        )
        for (image in
            listOf(
                "",
                "AAA",
                "A===",
                "=AAA",
                "AA=A",
                "AA==AAAA",
                "====",
                "AAAA\n",
                "data:image/jpeg;base64,AAAA",
                "АААА",
            )) {
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(coverName, cover(image))
            }
        }
        // These are transport shape tests, not assertions that A-bytes are JPEG.
        LocalCallableProtocol.request(coverName, cover("A".repeat(4_000_000)))
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(coverName, cover("A".repeat(4_000_004)))
        }
    }

    @Test
    fun fourMiBJsonEnvelopeBoundaryIncludesEscapedBase64Slashes() {
        // Compact envelope with kind=news/contentId=x has57 bytes outside image.
        // Android JSONStringer escapes each '/', adding one byte per slash.
        val slashes = 4_194_304 - 57 - 4_000_000
        val exact = "/".repeat(slashes) + "A".repeat(4_000_000 - slashes)
        LocalCallableProtocol.request(coverName, cover(exact, id = "x"))
        val oneByteOver = "/".repeat(slashes + 1) + "A".repeat(4_000_000 - slashes - 1)
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(coverName, cover(oneByteOver, id = "x"))
        }
    }

    @Test
    fun mediaAllowanceNeverLeaksToOrdinaryCallsOrLegacyEntryPoint() {
        val input = cover("A".repeat(80_000))
        LocalCallableProtocol.request(coverName, input)
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request("saveComment", input)
        }
        fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(input) }
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(coverName, input + ("other" to "A".repeat(80_000)))
        }
    }

    @Test
    fun ordinaryUtf8LimitIncludesEnvelopeAndQuotesAtExactBoundary() {
        val exact = "a".repeat(65_536 - 11)
        LocalCallableProtocol.request("saveComment", exact)
        LocalCallableProtocol.request(exact)
        fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(exact + "a") }
    }

    @Test
    fun cumulativeBudgetAccountsForNestedContainerKeysAndSeparators() {
        val exact = mapOf("a" to listOf("x".repeat(65_536 - 19)))
        LocalCallableProtocol.request(exact)
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(mapOf("a" to listOf("x".repeat(65_536 - 18))))
        }
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(mapOf("x".repeat(65_536) to "a"))
        }
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(
                mapOf("a" to "x".repeat(33_000), "b" to "x".repeat(33_000))
            )
        }
    }

    @Test
    fun cumulativeBudgetStopsBeforeTraversingManyIndividuallyAllowedLargeValues() {
        var visited = 0
        val chunk = "x".repeat(65_536 - 20)
        val adversarial =
            object : AbstractList<String>() {
                override val size = 1_024

                override fun get(index: Int): String {
                    visited++
                    return chunk
                }
            }
        fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(adversarial) }
        assertEquals("Budget must stop before allocating/traversing the full aggregate", 2, visited)
    }

    @Test
    fun jsonEscapesCountEncodedBytesRatherThanUnescapedStringLength() {
        for ((character, cost) in
            listOf(
                "/" to 2,
                "\\" to 2,
                "\"" to 2,
                "\n" to 2,
                "\t" to 2,
                "\r" to 2,
                "\b" to 2,
                "\u000c" to 2,
                "\u0000" to 6,
                "\u001f" to 6,
            )) {
            val room = 65_536 - 11
            val exact = character.repeat(room / cost) + "a".repeat(room % cost)
            LocalCallableProtocol.request(exact)
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(exact + "a")
            }
        }
    }

    @Test
    fun utf8MultibyteAndSupplementaryCharactersHaveExactByteBudget() {
        for ((character, cost) in listOf("ä" to 2, "界" to 3, "\uD83D\uDE00" to 4)) {
            val room = 65_536 - 11
            val exact = character.repeat(room / cost) + "a".repeat(room % cost)
            LocalCallableProtocol.request(exact)
            fails(LocalCallableFailure.INVALID_ARGUMENT) {
                LocalCallableProtocol.request(exact + "a")
            }
        }
    }

    @Test
    fun malformedUtf16CannotBeSilentlyReplacedDuringUtf8Serialization() {
        for (input in listOf<Any>("\uD83D", "\uDE00", "a\uD83Dx", mapOf("\uD83D" to "value"))) {
            fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(input) }
        }
    }

    @Test
    fun cumulativeBudgetPreservesInt64WrappersAndBoundsTheirActualRepresentation() {
        val data =
            LocalCallableProtocol.request(listOf(Long.MIN_VALUE, Long.MAX_VALUE, 2, -0.0, 1.5))[
                    "data"]
                as List<*>
        assertEquals(Long.MIN_VALUE.toString(), (data[0] as Map<*, *>)["value"])
        assertEquals(Long.MAX_VALUE.toString(), (data[1] as Map<*, *>)["value"])
        assertEquals(2, data[2])
        assertEquals(-0.0, data[3])
        assertEquals(1.5, data[4])
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(List(1_024) { Long.MAX_VALUE })
        }
    }

    @Test
    fun nestedCyclesAndLargeSiblingBranchesRemainBounded() {
        val cycle = mutableListOf<Any?>()
        cycle.add(cycle)
        fails(LocalCallableFailure.INVALID_ARGUMENT) { LocalCallableProtocol.request(cycle) }
        val branch = List(64) { "x".repeat(512) }
        fails(LocalCallableFailure.INVALID_ARGUMENT) {
            LocalCallableProtocol.request(listOf(branch, branch, branch))
        }
    }

    @Test
    fun coverRequestsNeverRelaxResponseLimit() {
        LocalCallableProtocol.request(coverName, cover("A".repeat(80_000)))
        fails(LocalCallableFailure.DATA_LOSS) {
            LocalCallableProtocol.validateRawResponse("x".repeat(262_145))
        }
    }
}
