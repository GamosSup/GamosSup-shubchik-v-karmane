package io.github.gamossup.shubchik

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            preferences(context).all.forEach { (key, value) ->
                val time = value as? Long ?: return@forEach
                if (time > System.currentTimeMillis()) {
                    schedule(context, key, time)
                } else {
                    cancel(context, key)
                }
            }
            return
        }
        if (intent.action != ACTION) return
        val key = intent.data?.lastPathSegment ?: return
        val storedTime = preferences(context).getLong(key, 0L)
        if (storedTime == 0L) return
        if (storedTime > System.currentTimeMillis()) {
            schedule(context, key, storedTime)
            return
        }
        preferences(context).edit().remove(key).apply()
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Напоминания о задачах", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
                      else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("Шубчик в кармане")
            .setContentText("Пора проверить запланированную задачу")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        manager.notify(key, 0, notification)
    }

    companion object {
        private const val ACTION = "io.github.gamossup.shubchik.REMINDER"
        private const val CHANNEL = "task_reminders"

        private fun preferences(context: Context) =
            context.getSharedPreferences("task_reminders", Context.MODE_PRIVATE)

        private fun alarm(context: Context, key: String): PendingIntent {
            val data = Uri.Builder().scheme("shubchik").authority("reminder").appendPath(key).build()
            val intent = Intent(context, ReminderReceiver::class.java).setAction(ACTION).setData(data)
            return PendingIntent.getBroadcast(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun schedule(context: Context, key: String, time: Long) {
            check(preferences(context).edit().putLong(key, time).commit())
            context.getSystemService(AlarmManager::class.java)
                .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, alarm(context, key))
        }

        fun cancel(context: Context, key: String) {
            preferences(context).edit().remove(key).apply()
            context.getSystemService(AlarmManager::class.java).cancel(alarm(context, key))
            context.getSystemService(NotificationManager::class.java).cancel(key, 0)
        }
    }
}
