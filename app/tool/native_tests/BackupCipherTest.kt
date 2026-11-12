package io.github.gamossup.shubchik

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class BackupCipherTest {
    @Test fun restoresOnlyWithTheCorrectPassword() {
        val payload = """{"tasks":[{"title":"Тест"}]}""".toByteArray(Charsets.UTF_8)
        val password = "synthetic-backup-password"
        val encrypted = BackupCipher.apply(payload, password, encrypt = true)
        assertFalse(encrypted.contentEquals(payload))
        assertArrayEquals(payload, BackupCipher.apply(encrypted, password, encrypt = false))
        assertThrows(Exception::class.java) {
            BackupCipher.apply(encrypted, "different-test-password", encrypt = false)
        }
        encrypted[encrypted.lastIndex] = (encrypted.last().toInt() xor 1).toByte()
        assertThrows(Exception::class.java) {
            BackupCipher.apply(encrypted, password, encrypt = false)
        }
    }
}
