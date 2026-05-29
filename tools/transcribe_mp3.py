#!/usr/bin/env python3
"""
MP3 to Text Transcription Tool
Uses OpenAI Whisper (local, no API key required)
"""

import argparse
import os
import sys
import time
from pathlib import Path


def check_dependencies():
    missing = []
    try:
        import whisper  # noqa: F401
    except ImportError:
        missing.append("openai-whisper")
    try:
        import ffmpeg  # noqa: F401
    except ImportError:
        missing.append("ffmpeg-python")
    if missing:
        print(f"Missing dependencies: {', '.join(missing)}")
        print("Install with:  pip install " + " ".join(missing))
        sys.exit(1)


def transcribe(
    audio_path: str,
    output_path: str | None,
    model_name: str,
    language: str | None,
    verbose: bool,
) -> str:
    import whisper

    audio_path = Path(audio_path).resolve()
    if not audio_path.exists():
        print(f"Error: file not found: {audio_path}", file=sys.stderr)
        sys.exit(1)

    if verbose:
        print(f"Loading Whisper model '{model_name}' …")

    model = whisper.load_model(model_name)

    if verbose:
        print(f"Transcribing {audio_path.name} …")

    start = time.time()
    result = model.transcribe(
        str(audio_path),
        language=language,
        verbose=False,
    )
    elapsed = time.time() - start

    text: str = result["text"].strip()
    detected_lang: str = result.get("language", "unknown")

    if verbose:
        print(f"Done in {elapsed:.1f}s  |  language detected: {detected_lang}")

    if output_path is None:
        output_path = audio_path.with_suffix(".txt")
    else:
        output_path = Path(output_path).resolve()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text, encoding="utf-8")
    print(f"Transcript saved to: {output_path}")

    return text


def main():
    parser = argparse.ArgumentParser(
        description="Transcribe an MP3 (or any audio) file to a TXT file using Whisper.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Models (trade-off between speed and accuracy):
  tiny    ~39 M params  – fastest, lower accuracy
  base    ~74 M params  – good balance for short clips
  small   ~244 M params – recommended default
  medium  ~769 M params – high accuracy, slower
  large   ~1550 M params – best accuracy, GPU recommended

Examples:
  python transcribe_mp3.py interview.mp3
  python transcribe_mp3.py interview.mp3 -o output/transcript.txt
  python transcribe_mp3.py interview.mp3 --model medium --language de
        """,
    )
    parser.add_argument("audio", help="Path to the MP3 (or WAV/M4A/…) file")
    parser.add_argument("-o", "--output", default=None, help="Output TXT file path (default: same name as input)")
    parser.add_argument(
        "--model",
        default="small",
        choices=["tiny", "base", "small", "medium", "large"],
        help="Whisper model size (default: small)",
    )
    parser.add_argument(
        "--language",
        default=None,
        help="Force a specific language code, e.g. 'de', 'en', 'fr' (auto-detect if omitted)",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Show progress output")
    parser.add_argument("--print", action="store_true", dest="print_text", help="Also print the transcript to stdout")

    args = parser.parse_args()

    check_dependencies()

    text = transcribe(
        audio_path=args.audio,
        output_path=args.output,
        model_name=args.model,
        language=args.language,
        verbose=args.verbose,
    )

    if args.print_text:
        print("\n--- Transcript ---")
        print(text)


if __name__ == "__main__":
    main()
