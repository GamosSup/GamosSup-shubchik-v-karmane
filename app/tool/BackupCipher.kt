package io.github.gamossup.shubchik

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

internal object BackupCipher {
    private val magic = "SHUBK01".toByteArray(Charsets.US_ASCII)
    private const val saltSize = 16
    private const val nonceSize = 12
    private const val tagSize = 16
    private const val maxPayload = 10_000_000
    private const val iterations = 600_000

    fun apply(input: ByteArray, password: String, encrypt: Boolean): ByteArray {
        require(password.length in 12..256)
        val headerSize = magic.size + saltSize + nonceSize
        require(input.size <= maxPayload + headerSize + tagSize)
        val salt = ByteArray(saltSize)
        val nonce = ByteArray(nonceSize)
        if (encrypt) {
            require(input.size <= maxPayload)
            val random = SecureRandom()
            random.nextBytes(salt)
            random.nextBytes(nonce)
        } else {
            require(input.size >= headerSize + tagSize)
            require(input.copyOfRange(0, magic.size).contentEquals(magic))
            input.copyInto(salt, 0, magic.size, magic.size + saltSize)
            input.copyInto(nonce, 0, magic.size + saltSize, headerSize)
        }
        val spec = PBEKeySpec(password.toCharArray(), salt, iterations, 256)
        val key = try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                if (encrypt) Cipher.ENCRYPT_MODE else Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"), GCMParameterSpec(tagSize * 8, nonce),
            )
            cipher.updateAAD(magic)
            return if (encrypt) magic + salt + nonce + cipher.doFinal(input)
                else cipher.doFinal(input, headerSize, input.size - headerSize)
        } finally {
            key.fill(0)
        }
    }
}
