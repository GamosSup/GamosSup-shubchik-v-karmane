package io.github.gamossup.shubchik

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

class BankNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(notification: StatusBarNotification) {
        val bank = when (notification.packageName) {
            "ru.sberbankmobile" -> "sber"
            "ru.ozon.fintech.finance" -> "ozon"
            else -> return
        }
        val prefs = getSharedPreferences("bank_notification_candidates", MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return
        val extras = notification.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val amount = candidateAmount(title, text) ?: return
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("${notification.key}:${notification.postTime}:$amount".toByteArray())
        val id = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
        val previous = JSONArray(prefs.getString("items", "[]"))
        if ((0 until previous.length()).any { previous.getJSONObject(it).getString("id") == id }) return
        val items = JSONArray()
        for (index in maxOf(0, previous.length() - 99) until previous.length()) {
            items.put(previous.getJSONObject(index))
        }
        items.put(JSONObject().put("id", id).put("bank", bank)
            .put("cents", amount).put("time", notification.postTime))
        prefs.edit().putString("items", items.toString()).apply()
    }

    companion object {
        private val rubles = Regex(
            """(?<![\d.,])([0-9]{1,3}(?:[ \u00a0\u202f][0-9]{3})+|[0-9]{1,8})(?:[.,]([0-9]{2}))?\s*(?:₽|RUB)(?![A-Z])""",
            RegexOption.IGNORE_CASE,
        )

        internal fun candidateAmount(title: String, text: String): Long? {
            val sign = when (title.trim().lowercase()) {
                "покупка", "оплата", "списание" -> -1
                "пополнение", "зачисление" -> 1
                else -> return null
            }
            if (text.length > 320 || text.contains("код", ignoreCase = true)) return null
            val match = rubles.findAll(text).singleOrNull() ?: return null
            val whole = match.groupValues[1].filter(Char::isDigit).toLongOrNull() ?: return null
            val fraction = match.groupValues[2].toLongOrNull() ?: 0
            val cents = whole * 100 + fraction
            return if (cents in 1..9_999_999_999L) sign * cents else null
        }
    }
}
