package io.github.gamossup.shubchik

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BankNotificationParserTest {
    @Test fun onlyExtractsUnambiguousRubleAmounts() {
        assertEquals(-125050L, BankNotificationListener.candidateAmount("Покупка", "1 250,50 ₽"))
        assertEquals(7500L, BankNotificationListener.candidateAmount("Пополнение", "75 RUB"))
        assertNull(BankNotificationListener.candidateAmount("Перевод", "200 ₽"))
        assertNull(BankNotificationListener.candidateAmount("Покупка", "200 ₽; остаток 900 ₽"))
        assertNull(BankNotificationListener.candidateAmount("Покупка", "Код 123456. 200 ₽"))
        assertNull(BankNotificationListener.candidateAmount("Покупка", "20 USD"))
    }
}
