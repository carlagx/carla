#!/usr/bin/env python3
"""
MP3 Transkriptions-App (Android)
Framework : Kivy
Engine    : Vosk (lokale Offline-Transkription, kein API-Key)
"""

import json
import os
import tempfile
import threading
import wave

from kivy.app import App
from kivy.clock import mainthread
from kivy.lang import Builder
from kivy.metrics import dp
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.popup import Popup

KV = """
<RootLayout>:
    orientation: 'vertical'
    padding: dp(16)
    spacing: dp(10)

    # ── Titel ──────────────────────────────────────────────────────────
    Label:
        text: 'MP3 Transkription'
        font_size: dp(22)
        bold: True
        size_hint_y: None
        height: dp(44)
        color: 0.2, 0.55, 1, 1

    # ── Dateiauswahl ───────────────────────────────────────────────────
    BoxLayout:
        orientation: 'horizontal'
        size_hint_y: None
        height: dp(48)
        spacing: dp(8)

        TextInput:
            id: file_label
            hint_text: 'Audiodatei auswählen …'
            readonly: True
            multiline: False
            size_hint_x: 0.75
            valign: 'middle'

        Button:
            text: 'Öffnen'
            size_hint_x: 0.25
            background_color: 0.2, 0.55, 1, 1
            on_press: root.show_file_chooser()

    # ── Statuszeile & Fortschritt ──────────────────────────────────────
    Label:
        id: status_label
        text: 'Bereit'
        size_hint_y: None
        height: dp(28)
        color: 0.55, 0.55, 0.55, 1

    ProgressBar:
        id: progress
        value: 0
        max: 100
        size_hint_y: None
        height: dp(16)

    # ── Ergebnis-Textfeld ──────────────────────────────────────────────
    ScrollView:
        TextInput:
            id: result_box
            hint_text: 'Transkription erscheint hier …'
            readonly: True
            multiline: True
            size_hint_y: None
            height: max(self.minimum_height, dp(220))

    # ── Aktions-Buttons ────────────────────────────────────────────────
    BoxLayout:
        orientation: 'horizontal'
        size_hint_y: None
        height: dp(52)
        spacing: dp(8)

        Button:
            id: btn_transcribe
            text: 'Transkribieren'
            background_color: 0.18, 0.76, 0.42, 1
            on_press: root.start_transcription()

        Button:
            text: 'Speichern'
            background_color: 0.56, 0.36, 0.8, 1
            on_press: root.save_transcript()

        Button:
            text: 'Leeren'
            size_hint_x: 0.38
            background_color: 0.78, 0.36, 0.18, 1
            on_press: root.clear()
"""

Builder.load_string(KV)


# ──────────────────────────────────────────────────────────────────────────────
# Hilfsfunktionen
# ──────────────────────────────────────────────────────────────────────────────

def _find_model() -> str | None:
    """Sucht das Vosk-Modell an bekannten Speicherorten."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "model"),          # neben main.py
        "/sdcard/vosk-model",                        # interner Speicher
        "/sdcard/Download/vosk-model",
        os.path.expanduser("~/vosk-model"),
    ]
    for path in candidates:
        if os.path.isdir(path):
            return path
    return None


def _to_wav(src: str) -> str | None:
    """Konvertiert eine Audiodatei zu mono-16-kHz-WAV für Vosk."""
    if src.lower().endswith(".wav"):
        return src                                   # bereits WAV – direkt nutzen
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    try:
        from pydub import AudioSegment
        audio = (
            AudioSegment.from_file(src)
            .set_channels(1)
            .set_frame_rate(16_000)
            .set_sample_width(2)
        )
        audio.export(tmp.name, format="wav")
        return tmp.name
    except Exception as exc:
        print(f"Konvertierungsfehler: {exc}")
        # Fallback: ffmpeg direkt aufrufen
        ret = os.system(
            f'ffmpeg -y -i "{src}" -ac 1 -ar 16000 -sample_fmt s16 "{tmp.name}" 2>/dev/null'
        )
        return tmp.name if ret == 0 else None


def _transcribe_vosk(model_path: str, wav_path: str) -> str:
    """Führt die Vosk-Transkription durch und gibt den vollständigen Text zurück."""
    from vosk import KaldiRecognizer, Model

    model = Model(model_path)
    with wave.open(wav_path, "rb") as wf:
        rec = KaldiRecognizer(model, wf.getframerate())
        parts: list[str] = []
        while True:
            data = wf.readframes(4_000)
            if not data:
                break
            if rec.AcceptWaveform(data):
                chunk = json.loads(rec.Result()).get("text", "")
                if chunk:
                    parts.append(chunk)
        final = json.loads(rec.FinalResult()).get("text", "")
        if final:
            parts.append(final)
    return " ".join(parts).strip()


# ──────────────────────────────────────────────────────────────────────────────
# Haupt-Widget
# ──────────────────────────────────────────────────────────────────────────────

class RootLayout(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._selected_file: str | None = None
        self._busy = False

    # ── Dateiauswahl ──────────────────────────────────────────────────────────

    def show_file_chooser(self):
        start = next(
            (p for p in ("/sdcard/Download", "/sdcard", os.path.expanduser("~"))
             if os.path.isdir(p)),
            ".",
        )

        chooser = FileChooserListView(
            path=start,
            filters=["*.mp3", "*.wav", "*.m4a", "*.ogg", "*.flac", "*.aac"],
        )

        btn_row = BoxLayout(size_hint_y=None, height=dp(50), spacing=dp(8))
        btn_cancel = Button(text="Abbrechen", background_color=(0.8, 0.3, 0.3, 1))
        btn_ok = Button(text="Auswählen", background_color=(0.3, 0.8, 0.3, 1))
        btn_row.add_widget(btn_cancel)
        btn_row.add_widget(btn_ok)

        content = BoxLayout(orientation="vertical")
        content.add_widget(chooser)
        content.add_widget(btn_row)

        popup = Popup(title="Audiodatei auswählen", content=content, size_hint=(0.95, 0.92))
        btn_cancel.bind(on_press=popup.dismiss)

        def _select(_):
            if chooser.selection:
                self._selected_file = chooser.selection[0]
                self.ids.file_label.text = os.path.basename(self._selected_file)
                self._set_status("Datei geladen – bereit zum Transkribieren.", (0.3, 0.8, 0.5, 1))
                popup.dismiss()

        btn_ok.bind(on_press=_select)
        popup.open()

    # ── Transkription ─────────────────────────────────────────────────────────

    def start_transcription(self):
        if self._busy:
            return
        if not self._selected_file:
            self._set_status("Bitte zuerst eine Audiodatei auswählen!", (1, 0.4, 0.4, 1))
            return
        self._busy = True
        self.ids.btn_transcribe.disabled = True
        self.ids.result_box.text = ""
        self._set_progress(5)
        threading.Thread(target=self._worker, daemon=True).start()

    def _worker(self):
        wav_tmp: str | None = None
        try:
            self._set_status("Vosk-Modell wird gesucht …", (0.9, 0.75, 0.2, 1))
            model_path = _find_model()
            if not model_path:
                self._set_status(
                    "Kein Vosk-Modell gefunden! Bitte download_model.py ausführen.",
                    (1, 0.3, 0.3, 1),
                )
                return

            self._set_status("Audio wird konvertiert …", (0.9, 0.75, 0.2, 1))
            self._set_progress(25)
            wav_tmp = _to_wav(self._selected_file)
            if not wav_tmp:
                self._set_status("Konvertierung fehlgeschlagen – ffmpeg fehlt?", (1, 0.3, 0.3, 1))
                return

            self._set_status("Transkription läuft …", (0.9, 0.75, 0.2, 1))
            self._set_progress(50)
            text = _transcribe_vosk(model_path, wav_tmp)

            self._set_progress(100)
            self._set_status("Fertig!", (0.2, 0.82, 0.44, 1))
            self._set_result(text or "[Kein Text erkannt]")

        except ImportError:
            self._set_status("vosk nicht installiert – pip install vosk", (1, 0.3, 0.3, 1))
        except Exception as exc:
            self._set_status(f"Fehler: {exc}", (1, 0.3, 0.3, 1))
        finally:
            if wav_tmp and wav_tmp != self._selected_file:
                try:
                    os.remove(wav_tmp)
                except OSError:
                    pass
            self._finish()

    # ── Speichern ─────────────────────────────────────────────────────────────

    def save_transcript(self):
        text = self.ids.result_box.text.strip()
        if not text or text == "[Kein Text erkannt]":
            self._set_status("Kein Text zum Speichern vorhanden.", (1, 0.5, 0.2, 1))
            return
        if self._selected_file:
            out = os.path.splitext(self._selected_file)[0] + "_transkript.txt"
        else:
            out = "/sdcard/Download/transkript.txt"
        try:
            with open(out, "w", encoding="utf-8") as f:
                f.write(text)
            self._set_status(f"Gespeichert: {out}", (0.2, 0.82, 0.44, 1))
        except OSError as exc:
            self._set_status(f"Speichern fehlgeschlagen: {exc}", (1, 0.3, 0.3, 1))

    # ── Hilfsmethoden ─────────────────────────────────────────────────────────

    def clear(self):
        self.ids.result_box.text = ""
        self._set_status("Bereit", (0.55, 0.55, 0.55, 1))
        self._set_progress(0)

    @mainthread
    def _set_status(self, text, color=(0.55, 0.55, 0.55, 1)):
        self.ids.status_label.text = text
        self.ids.status_label.color = color

    @mainthread
    def _set_progress(self, value):
        self.ids.progress.value = value

    @mainthread
    def _set_result(self, text):
        self.ids.result_box.text = text

    @mainthread
    def _finish(self):
        self._busy = False
        self.ids.btn_transcribe.disabled = False


# ──────────────────────────────────────────────────────────────────────────────
# App-Klasse
# ──────────────────────────────────────────────────────────────────────────────

class TranscribeApp(App):
    def build(self):
        self.title = "MP3 Transkription"
        return RootLayout()

    def on_start(self):
        try:
            from android.permissions import Permission, request_permissions
            request_permissions([
                Permission.READ_EXTERNAL_STORAGE,
                Permission.WRITE_EXTERNAL_STORAGE,
            ])
        except ImportError:
            pass  # Desktop-Betrieb – keine Android-Permissions nötig


if __name__ == "__main__":
    TranscribeApp().run()
