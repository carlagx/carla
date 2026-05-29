[app]
title           = MP3 Transkription
package.name    = mp3transkription
package.domain  = org.carla

source.dir      = .
source.include_exts = py,png,jpg,kv,atlas,txt

version         = 1.0.0

# ── Python-Abhängigkeiten ──────────────────────────────────────────────────
# vosk: lokale Offline-Spracherkennung (ARM64-Wheel auf PyPI verfügbar)
# pydub: Audio-Konvertierung (MP3 → WAV)
requirements = python3,kivy==2.3.0,kivymd,vosk,pydub,ffpyplayer

# ── Android-Konfiguration ─────────────────────────────────────────────────
android.permissions = READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE,RECORD_AUDIO
android.api         = 33
android.minapi      = 24
android.ndk         = 25b
android.arch        = arm64-v8a

# ── Vosk-Modell ins APK einbetten (optional) ──────────────────────────────
# Wenn das Modell direkt ins APK gepackt werden soll, den Kommentar entfernen.
# Achtung: vergrößert das APK erheblich (~50 MB für vosk-model-de-0.21).
# source.include_patterns = model/**/*

# ── Build-Einstellungen ───────────────────────────────────────────────────
android.release_artifact = apk

[buildozer]
log_level  = 2
warn_on_root = 1
