package at.uac.android.core

import at.uac.android.core.backend.BackendService
import at.uac.android.core.backend.CompiledBackend

/** Independent of the Functions SDK: status names come from the documented onCall protocol. */
enum class LocalCallableFailure {
    CANCELLED,
    UNKNOWN,
    INVALID_ARGUMENT,
    DEADLINE_EXCEEDED,
    NOT_FOUND,
    ALREADY_EXISTS,
    PERMISSION_DENIED,
    RESOURCE_EXHAUSTED,
    FAILED_PRECONDITION,
    ABORTED,
    OUT_OF_RANGE,
    UNIMPLEMENTED,
    INTERNAL,
    UNAVAILABLE,
    DATA_LOSS,
    UNAUTHENTICATED,
    UNCONFIRMED,
}

class LocalCallableException(
    val code: LocalCallableFailure,
    val details: Any? = null,
    cause: Throwable? = null,
) : Exception(code.name, cause)

data class LocalCallableResult(val data: Any?)

object LocalCallableProtocol {
    const val MAX_REQUEST_BYTES = 65_536
    const val MAX_COVER_REQUEST_BYTES = 4 * 1_024 * 1_024
    const val MAX_COVER_BASE64_CHARACTERS = 4_000_000
    const val MAX_RESPONSE_BYTES = 262_144
    private const val COVER_UPLOAD = "uploadOrganizationContentCover"
    private val allowed =
        setOf(
            "registerForEvent",
            "unregisterFromEvent",
            "saveComment",
            "submitContentReport",
            "setUserBlocked",
            "setOrganizationBlocked",
            "getBlockedOrganizations",
            "getMyDsaStatement",
            "acceptLegalDocument",
            "activatePrivilegedMFAProtection",
            "searchManagedUsers",
            "getManagedUserSecurityMetadata",
            "warnUser",
            "suspendUser",
            "banUser",
            "deactivateUser",
            "restoreUser",
            "assignAppAdmin",
            "removeAppAdmin",
            "acceptOrganizationRules",
            "approveOrganization",
            "requestOrganizationRevision",
            "rejectOrganization",
            "deleteOrganization",
            "assignOrganizationAdmin",
            "removeOrganizationAdmin",
            "assignOrganizationModerator",
            "removeOrganizationModerator",
            "transferOrganizationOwnership",
            "deleteOwnAccount",
            "deleteNews",
            "cancelEvent",
            "createOrganizationPhotoMetadata",
            "deleteOrganizationPhotoMetadata",
            COVER_UPLOAD,
        )
    private const val INT64 = "type.googleapis.com/google.protobuf.Int64Value"
    private const val UINT64 = "type.googleapis.com/google.protobuf.UInt64Value"

    fun endpoint(
        name: String,
        host: String = LocalEnvironment.HOST,
        project: String = LocalEnvironment.PROJECT_ID,
        port: Int = CompiledBackend.CALLABLE_PORT,
        region: String = CompiledBackend.CALLABLE_REGION,
    ): String {
        LocalEnvironment.requireSafe(project, host)
        CompiledBackend.configuration.requireEndpoint(BackendService.CALLABLES, host, port)
        CompiledBackend.configuration.requireCallableRegion(region)
        require(name in allowed)
        return "http://$host:$port/$project/$region/$name"
    }

    // Legal acceptance and role calls append audit/notification records even for an unchanged
    // desired value.
    fun nonIdempotent(name: String) =
        name in
            setOf(
                "saveComment",
                "submitContentReport",
                "acceptLegalDocument",
                "warnUser",
                "suspendUser",
                "banUser",
                "deactivateUser",
                "restoreUser",
                "assignAppAdmin",
                "removeAppAdmin",
                "approveOrganization",
                "requestOrganizationRevision",
                "rejectOrganization",
                "assignOrganizationAdmin",
                "removeOrganizationAdmin",
                "assignOrganizationModerator",
                "removeOrganizationModerator",
                "transferOrganizationOwnership",
                "deleteOwnAccount",
                "deleteNews",
                "cancelEvent",
                "createOrganizationPhotoMetadata",
                "deleteOrganizationPhotoMetadata",
                COVER_UPLOAD,
            )

    // Exact existing server deadlines. Cover upload overwrites Storage then updates Firestore.
    fun maximumTimeoutMillis(name: String): Long =
        when (name) {
            "deleteOwnAccount",
            "deleteNews" -> 300_000
            COVER_UPLOAD -> 120_000
            else -> 60_000
        }

    fun maximumRequestBytes(name: String): Int =
        if (name == COVER_UPLOAD) MAX_COVER_REQUEST_BYTES else MAX_REQUEST_BYTES

    /** Ordinary compatibility entry point; it never grants the larger media budget. */
    fun request(data: Any?): Map<String, Any?> = boundedRequest(data, MAX_REQUEST_BYTES)

    fun request(name: String, data: Any?): Map<String, Any?> {
        require(name in allowed)
        if (name == COVER_UPLOAD) validateCoverRequest(data)
        return boundedRequest(data, maximumRequestBytes(name))
    }

    private fun boundedRequest(data: Any?, maximum: Int): Map<String, Any?> {
        val budget = JsonBudget(maximum)
        budget.take(9) // {"data":...}, excluding the separately measured value.
        return mapOf("data" to encode(data, 0, budget))
    }

    private fun validateCoverRequest(value: Any?) {
        val data = value as? Map<*, *> ?: invalid()
        if (data.size != 3 || data.keys != setOf("kind", "contentId", "imageBase64")) invalid()
        if (data["kind"] !in setOf("news", "event")) invalid()
        val id = data["contentId"] as? String ?: invalid()
        if (
            id.isBlank() ||
                id != id.trim() ||
                id.length > 512 ||
                '/' in id ||
                id == "." ||
                id == ".." ||
                id.any(Char::isISOControl) ||
                id.startsWith("__") && id.endsWith("__")
        )
            invalid()
        // Firestore path segment limit; bounded tiny allocation, never the image.
        if (id.toByteArray(Charsets.UTF_8).size > 1_500) invalid()
        val image = data["imageBase64"] as? String ?: invalid()
        if (image.isEmpty() || image.length > MAX_COVER_BASE64_CHARACTERS || image.length % 4 != 0)
            invalid()
        var padding = 0
        image.forEachIndexed { index, character ->
            when {
                character == '=' -> {
                    padding++
                    if (padding > 2 || index < image.length - 2) invalid()
                }
                padding != 0 -> invalid()
                character !in 'A'..'Z' &&
                    character !in 'a'..'z' &&
                    character !in '0'..'9' &&
                    character != '+' &&
                    character != '/' -> invalid()
            }
        }
        // JPEG signatures, dimensions, re-encoding and decoded <3MB are domain
        // responsibilities. This transport only bounds the exact callable shape.
    }

    /** Bound nesting before Android's recursive JSON parser sees the response. */
    fun validateRawResponse(value: String) {
        if (value.toByteArray(Charsets.UTF_8).size > MAX_RESPONSE_BYTES)
            throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
        var depth = 0
        var quoted = false
        var escaped = false
        value.forEach { character ->
            if (quoted) {
                if (escaped) escaped = false
                else if (character == '\\') escaped = true else if (character == '"') quoted = false
            } else
                when (character) {
                    '"' -> quoted = true
                    '{',
                    '[' -> {
                        depth++
                        if (depth > 24) throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                    }
                    '}',
                    ']' -> {
                        depth--
                        if (depth < 0) throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                    }
                }
        }
        if (quoted || depth != 0) throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
    }

    private fun encode(value: Any?, depth: Int, budget: JsonBudget): Any? {
        if (depth > 20) invalid()
        return when (value) {
            null -> null.also { budget.take(4) }
            is Boolean -> value.also { budget.take(if (it) 4 else 5) }
            is String -> value.also(budget::string)
            is Byte,
            is Short,
            is Int -> (value as Number).toInt().also { budget.take(it.toString().length) }
            is Long -> {
                val decimal = value.toString()
                budget.take(5) // Object braces, comma, two colons.
                budget.string("@type")
                budget.string(INT64)
                budget.string("value")
                budget.string(decimal)
                mapOf("@type" to INT64, "value" to decimal)
            }
            is Float,
            is Double ->
                (value as Number).toDouble().also {
                    if (!it.isFinite()) invalid()
                    // Match Android JSONObject.numberToString including -0 and
                    // integral doubles. Int64 still uses its typed string wrapper.
                    val number =
                        if (it.toRawBits() == (-0.0).toRawBits()) "-0"
                        else if (it == it.toLong().toDouble()) it.toLong().toString()
                        else it.toString()
                    budget.take(number.length)
                }
            is Map<*, *> -> {
                if (value.size > 1_024) invalid()
                budget.take(2)
                val result = linkedMapOf<String, Any?>()
                value.entries.forEachIndexed { index, (key, item) ->
                    if (key !is String || key == "@type") invalid()
                    if (index > 0) budget.take(1)
                    budget.string(key)
                    budget.take(1)
                    result[key] = encode(item, depth + 1, budget)
                }
                result
            }
            is List<*> -> {
                if (value.size > 1_024) invalid()
                budget.take(2)
                val result = arrayListOf<Any?>()
                value.forEachIndexed { index, item ->
                    if (index > 0) budget.take(1)
                    result += encode(item, depth + 1, budget)
                }
                result
            }
            else -> invalid()
        }
    }

    /**
     * Cumulative serialized UTF-8 budget, consumed while making the bounded immutable envelope and
     * BEFORE JSONObject/JSONArray/String/ByteArray copies. Mirrors Android JSONStringer escaping
     * (including '/'). No full UTF-8 copy of a large field is made just to count it. Invalid UTF-16
     * is rejected.
     */
    private class JsonBudget(private var remaining: Int) {
        fun take(bytes: Int) {
            if (bytes < 0 || bytes > remaining) invalid()
            remaining -= bytes
        }

        fun string(value: String) {
            take(2)
            var index = 0
            while (index < value.length) {
                val character = value[index]
                when {
                    character == '"' ||
                        character == '\\' ||
                        character == '/' ||
                        character == '\t' ||
                        character == '\b' ||
                        character == '\n' ||
                        character == '\r' ||
                        character == '\u000c' -> take(2)
                    character <= '\u001f' -> take(6)
                    character <= '\u007f' -> take(1)
                    character <= '\u07ff' -> take(2)
                    character.isHighSurrogate() -> {
                        if (index + 1 >= value.length || !value[index + 1].isLowSurrogate())
                            invalid()
                        take(4)
                        index++
                    }
                    character.isLowSurrogate() -> invalid()
                    else -> take(3)
                }
                index++
            }
        }
    }

    fun response(status: Int, envelope: Map<String, Any?>): LocalCallableResult {
        // Error wins even when a malicious/malformed response also supplies a result.
        if (envelope.containsKey("error")) {
            val error =
                envelope["error"] as? Map<*, *>
                    ?: throw LocalCallableException(LocalCallableFailure.INTERNAL)
            val code =
                (error["status"] as? String)
                    ?.let { value -> LocalCallableFailure.entries.firstOrNull { it.name == value } }
                    ?.takeUnless { it == LocalCallableFailure.UNCONFIRMED }
                    ?: LocalCallableFailure.INTERNAL
            throw LocalCallableException(code, decode(error["details"], 0))
        }
        if (status !in 200..299)
            throw LocalCallableException(
                when (status) {
                    400 -> LocalCallableFailure.INVALID_ARGUMENT
                    401 -> LocalCallableFailure.UNAUTHENTICATED
                    403 -> LocalCallableFailure.PERMISSION_DENIED
                    404 -> LocalCallableFailure.NOT_FOUND
                    429 -> LocalCallableFailure.RESOURCE_EXHAUSTED
                    503 -> LocalCallableFailure.UNAVAILABLE
                    504 -> LocalCallableFailure.DEADLINE_EXCEEDED
                    else -> LocalCallableFailure.INTERNAL
                }
            )
        val key =
            when {
                envelope.containsKey("result") && !envelope.containsKey("data") -> "result"
                envelope.containsKey("data") && !envelope.containsKey("result") ->
                    "data" // SDK's legacy response alias.
                else -> throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
            }
        return LocalCallableResult(decode(envelope[key], 0))
    }

    private fun decode(value: Any?, depth: Int): Any? {
        if (depth > 20) throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
        return when (value) {
            is Map<*, *> ->
                when (value["@type"]) {
                    INT64 ->
                        (value["value"] as? String)?.toLongOrNull()
                            ?: throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                    UINT64 ->
                        (value["value"] as? String)?.toULongOrNull()
                            ?: throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                    else ->
                        value.entries.associate { (key, item) ->
                            if (key !is String)
                                throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                            key to decode(item, depth + 1)
                        }
                }
            is List<*> -> value.map { decode(it, depth + 1) }
            is Double ->
                value.also {
                    if (!it.isFinite()) throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                }
            is Float ->
                value.also {
                    if (!it.isFinite()) throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                }
            null,
            is String,
            is Boolean,
            is Number -> value
            else -> throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
        }
    }

    fun transportFailure(
        name: String,
        requestStarted: Boolean,
        failure: LocalCallableFailure,
    ): LocalCallableFailure =
        if (
            nonIdempotent(name) &&
                requestStarted &&
                failure in
                    setOf(
                        LocalCallableFailure.UNAVAILABLE,
                        LocalCallableFailure.DEADLINE_EXCEEDED,
                        LocalCallableFailure.UNKNOWN,
                        LocalCallableFailure.INTERNAL,
                        LocalCallableFailure.DATA_LOSS,
                    )
        )
            LocalCallableFailure.UNCONFIRMED
        else failure

    private fun invalid(): Nothing =
        throw LocalCallableException(LocalCallableFailure.INVALID_ARGUMENT)
}
