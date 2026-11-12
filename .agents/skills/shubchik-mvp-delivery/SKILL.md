---
name: shubchik-mvp-delivery
description: Build and verify Android MVP changes in the existing Shubchik Flutter repository.
---

Use the existing app directory and Android workflow. CI creates the Android scaffold, then app/tool/configure_android.py installs the Kotlin code and manifest entries. Make Android source changes in app/tool. Use Flutter analysis, tests and an APK build for the commit being delivered. Report device behavior separately from CI results. Keep the first distribution private and follow the owner's current release authorization.
