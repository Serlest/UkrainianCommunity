package at.uac.android.feature.moderation

import com.google.firebase.Timestamp
import java.io.DataOutputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.time.Instant

data class ModerationReviewVersion(
    val target: ModerationTarget,
    val reviewHash: String,
    val preservedHash: String,
    val updatedAt: Instant,
    val organizationId: String,
) {
    override fun toString() = "ModerationReviewVersion([redacted])"

    fun validate() {
        if (
            target.kind !in setOf(ModerationKind.NEWS, ModerationKind.EVENT) ||
                !ModerationContract.id(target.id) ||
                !ModerationContract.id(organizationId) ||
                !Regex("[a-f0-9]{64}").matches(reviewHash) ||
                !Regex("[a-f0-9]{64}").matches(preservedHash)
        )
            ModerationDecisionContract.fail(ModerationDecisionFailure.INVALID)
    }

    companion object {
        const val MAX_BYTES = 1_048_576
        const val MAX_ENTRIES = 4096
        const val MAX_DEPTH = 20

        fun instant(value: Any?): Instant? =
            when (value) {
                is Instant -> value
                is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
                else -> null
            }

        fun from(target: ModerationTarget, fields: Map<String, Any?>): ModerationReviewVersion {
            val organizationId = fields["organizationId"] as? String ?: invalid()
            val time = instant(fields["updatedAt"]) ?: invalid()
            if (
                fields["id"] != target.id ||
                    fields["sourceType"] != "organization" ||
                    fields["moderationStatus"] != "pendingReview"
            )
                invalid()
            return ModerationReviewVersion(
                    target,
                    hash(target, fields),
                    hash(target, fields, true),
                    time,
                    organizationId,
                )
                .also { it.validate() }
        }

        fun hash(
            target: ModerationTarget,
            fields: Map<String, Any?>,
            preserved: Boolean = false,
        ): String {
            if (
                target.kind !in setOf(ModerationKind.NEWS, ModerationKind.EVENT) ||
                    !ModerationContract.id(target.id) ||
                    fields.size > MAX_ENTRIES
            )
                invalid()
            val ignored =
                setOf("likeCount", "viewCount", "commentCount") +
                    (if (target.kind == ModerationKind.EVENT) setOf("registeredCount")
                    else emptySet()) +
                    (if (preserved) setOf("moderationStatus", "updatedAt") else emptySet())
            val encoder = Encoder()
            encoder.value(
                listOf(
                    "uac-review-v1",
                    target.kind.collection,
                    target.id,
                    fields.filterKeys { it !in ignored },
                ),
                0,
            )
            return encoder.finish()
        }

        private fun invalid(): Nothing =
            ModerationDecisionContract.fail(ModerationDecisionFailure.INVALID)

        private class Encoder {
            private val digest = MessageDigest.getInstance("SHA-256")
            private var bytes = 0
            private var entries = 0
            private val stream =
                DataOutputStream(
                    object : OutputStream() {
                        override fun write(value: Int) {
                            reserve(1)
                            digest.update(value.toByte())
                        }

                        override fun write(value: ByteArray, offset: Int, count: Int) {
                            reserve(count)
                            digest.update(value, offset, count)
                        }
                    }
                )

            private fun reserve(count: Int) {
                if (count < 0 || count > MAX_BYTES - bytes) invalid()
                bytes += count
            }

            private fun string(value: String) {
                // Count exact valid UTF-8 before allocating its byte array; reject lone surrogates.
                if (value.length > MAX_BYTES) invalid()
                var size = 0
                var index = 0
                while (index < value.length) {
                    val char = value[index++]
                    size +=
                        when {
                            char.code < 0x80 -> 1
                            char.code < 0x800 -> 2
                            char.isHighSurrogate() -> {
                                if (index >= value.length || !value[index++].isLowSurrogate())
                                    invalid()
                                4
                            }
                            char.isLowSurrogate() -> invalid()
                            else -> 3
                        }
                    if (size > MAX_BYTES - bytes - 4) invalid()
                }
                stream.writeInt(size)
                stream.write(value.toByteArray(Charsets.UTF_8))
            }

            fun value(value: Any?, depth: Int) {
                if (depth > MAX_DEPTH || ++entries > MAX_ENTRIES) invalid()
                when (value) {
                    null -> stream.writeByte(0)
                    is Boolean -> {
                        stream.writeByte(1)
                        stream.writeBoolean(value)
                    }
                    is Byte,
                    is Short,
                    is Int,
                    is Long -> {
                        stream.writeByte(2)
                        stream.writeLong((value as Number).toLong())
                    }
                    is Double -> {
                        if (!value.isFinite()) invalid()
                        stream.writeByte(3)
                        stream.writeLong(value.toRawBits())
                    }
                    is String -> {
                        stream.writeByte(4)
                        string(value)
                    }
                    is Instant,
                    is Timestamp -> {
                        val time = instant(value) ?: invalid()
                        stream.writeByte(5)
                        stream.writeLong(time.epochSecond)
                        stream.writeInt(time.nano)
                    }
                    is List<*> -> {
                        if (value.size > MAX_ENTRIES - entries) invalid()
                        stream.writeByte(6)
                        stream.writeInt(value.size)
                        value.forEach { value(it, depth + 1) }
                    }
                    is Map<*, *> -> {
                        if (
                            value.size > (MAX_ENTRIES - entries) / 2 ||
                                value.keys.any { it !is String }
                        )
                            invalid()
                        stream.writeByte(7)
                        stream.writeInt(value.size)
                        value.keys
                            .map { it as String }
                            .sorted()
                            .forEach { key ->
                                entries++
                                string(key)
                                value(value[key], depth + 1)
                            }
                    }
                    else -> invalid()
                }
            }

            fun finish() = digest.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
