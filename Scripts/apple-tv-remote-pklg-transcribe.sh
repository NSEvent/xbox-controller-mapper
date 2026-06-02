#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <capture.pklg> [output-prefix]" >&2
  exit 2
fi

capture="$1"
prefix="${2:-${capture%.*}.siri-remote-mic}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
decoder="$script_dir/apple-tv-remote-pklg-decode.py"
whisper_cli="${WHISPER_CLI:-$HOME/projects/oss/whisper.cpp/build/bin/whisper-cli}"
whisper_model="${WHISPER_MODEL:-$HOME/projects/oss/whisper.cpp/models/ggml-base.en.bin}"
wav_path="$prefix.wav"
txt_path="$prefix.txt"

if [[ ! -x "$decoder" ]]; then
  echo "Missing decoder: $decoder" >&2
  exit 1
fi
if [[ ! -x "$whisper_cli" ]]; then
  echo "Missing whisper-cli: $whisper_cli" >&2
  exit 1
fi
if [[ ! -f "$whisper_model" ]]; then
  echo "Missing whisper model: $whisper_model" >&2
  exit 1
fi

"$decoder" "$capture" -o "$wav_path"
"$whisper_cli" -m "$whisper_model" -f "$wav_path" -nt -np | tee "$txt_path"
printf '\n'
echo "wav=$wav_path"
echo "transcript=$txt_path"
