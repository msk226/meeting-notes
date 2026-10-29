#!/bin/sh
# meeting-notes — 녹음 파일을 회의록 마크다운으로 정리하는 CLI
#   녹음 파일 → ffmpeg → whisper.cpp(로컬 전사) → LLM 요약 → 회의록 마크다운
#   음성은 로컬에서만 처리한다. 요약 단계에서는 전사 텍스트가 SUMMARIZER로 넘어간다.
#
# 사용법:
#   meeting-notes <오디오파일> [-l ko] [-m <모델경로>] [-o <출력폴더>] [-t <제목>] [--keep-transcript]
#   meeting-notes <오디오파일> --transcript-only   # 전사만 하고 요약은 호출한 AI가 직접 한다
#   meeting-notes --doctor                         # 의존성·모델·용어집 점검
#   meeting-notes --check-transcript <전사.txt>    # 반복 환각 여부만 검사 (0 정상, 2 의심)
#
set -eu

# ── 경로 ──
# 심볼릭 링크로 설치해도 저장소의 prompt.md를 찾도록 실제 위치를 따라간다.
SELF="$0"
while [ -L "$SELF" ]; do
  LINK="$(readlink "$SELF")"
  case "$LINK" in
    /*) SELF="$LINK" ;;
    *) SELF="$(dirname "$SELF")/$LINK" ;;
  esac
done
REPO_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/meeting-notes"

# ── 기본값 ──
LANG_CODE="ko"
MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper-models/ggml-large-v3-turbo.bin}"
OUT_DIR="${MEETING_NOTES_DIR:-$HOME/Documents/회의록}"
GLOSSARY_FILE="${MEETING_GLOSSARY_FILE:-$CONFIG_DIR/glossary.txt}"
PROMPT_FILE="${MEETING_NOTES_PROMPT:-$REPO_DIR/prompt.md}"
[ -f "$CONFIG_DIR/prompt.md" ] && [ -z "${MEETING_NOTES_PROMPT:-}" ] && PROMPT_FILE="$CONFIG_DIR/prompt.md"
SUMMARIZER="${MEETING_NOTES_SUMMARIZER:-claude -p}"
KEEP_TRANSCRIPT=0
TRANSCRIPT_ONLY=0
TITLE="회의록"
AUDIO=""

usage() { sed -n '2,10p' "$SELF" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ── 전사 품질 점검 ──
# 무음 구간에서 whisper가 같은 문장을 반복하는 환각 루프를 잡는다.
# 개수가 아니라 고유 줄 비율로 판단한다: 정상 회의는 고유 줄이 95% 이상이지만,
# 환각 루프는 같은 문장(미세 변주 포함)만 반복해 비율이 급락한다. 자세한 배경은 docs/hallucination-loop.md.
check_transcript() {
  total="$(awk 'NF' "$1" | wc -l | tr -d ' ')"
  unique="$(awk 'NF' "$1" | sort -u | wc -l | tr -d ' ')"
  pct=100
  [ "$total" -gt 0 ] && pct=$(( unique * 100 / total ))
  QUALITY_REPORT="고유 ${unique}/${total}줄, ${pct}%"
  if [ "$total" -ge 30 ] && [ "$pct" -le 20 ]; then
    return 2
  fi
  return 0
}

doctor() {
  ok=0
  printf '%s\n' "meeting-notes 점검"
  if command -v ffmpeg >/dev/null 2>&1; then echo "  ✅ ffmpeg"; else echo "  ❌ ffmpeg — brew install ffmpeg (리눅스: apt install ffmpeg)"; ok=1; fi
  if command -v whisper-cli >/dev/null 2>&1 || command -v whisper-cpp >/dev/null 2>&1; then
    echo "  ✅ whisper.cpp"
  else
    echo "  ❌ whisper.cpp — brew install whisper-cpp (리눅스: README의 소스 빌드 참고)"; ok=1
  fi
  if [ -f "$MODEL" ]; then echo "  ✅ 모델 $MODEL"; else echo "  ❌ 모델 없음 $MODEL — README '모델 받기' 참고"; ok=1; fi
  if [ -f "$GLOSSARY_FILE" ]; then
    echo "  ✅ 용어집 $GLOSSARY_FILE ($(awk 'NF && !/^#/' "$GLOSSARY_FILE" | wc -l | tr -d ' ')개 항목)"
  else
    echo "  ⚠️  용어집 없음 $GLOSSARY_FILE — 동작은 하지만 팀 고유 용어가 틀리게 정리된다. README '용어집 만들기' 참고"
  fi
  if [ -f "$PROMPT_FILE" ]; then echo "  ✅ 프롬프트 $PROMPT_FILE"; else echo "  ❌ 프롬프트 없음 $PROMPT_FILE"; ok=1; fi
  SUMMARIZER_BIN="${SUMMARIZER%% *}"
  if command -v "$SUMMARIZER_BIN" >/dev/null 2>&1; then
    echo "  ✅ 요약 명령 '$SUMMARIZER'"
  else
    echo "  ⚠️  요약 명령 '$SUMMARIZER' 없음 — --transcript-only로 전사만 하거나 MEETING_NOTES_SUMMARIZER를 지정"
  fi
  exit "$ok"
}

# ── 인자 파싱 ──
while [ $# -gt 0 ]; do
  case "$1" in
    -l) LANG_CODE="$2"; shift 2 ;;
    -m) MODEL="$2"; shift 2 ;;
    -o) OUT_DIR="$2"; shift 2 ;;
    -t) TITLE="$2"; shift 2 ;;
    --keep-transcript) KEEP_TRANSCRIPT=1; shift ;;
    --transcript-only) TRANSCRIPT_ONLY=1; shift ;;
    --doctor) doctor ;;
    --check-transcript)
      [ -f "${2:-}" ] || { echo "파일을 찾을 수 없음: ${2:-}" >&2; exit 1; }
      if check_transcript "$2"; then
        echo "정상 ($QUALITY_REPORT)"; exit 0
      else
        echo "반복 환각 의심 ($QUALITY_REPORT)"; exit 2
      fi ;;
    -h|--help) usage 0 ;;
    -*) echo "알 수 없는 옵션: $1" >&2; usage 1 ;;
    *) AUDIO="$1"; shift ;;
  esac
done

[ -n "$AUDIO" ] || { echo "오디오 파일을 지정하세요." >&2; usage 1; }
[ -f "$AUDIO" ] || { echo "파일을 찾을 수 없음: $AUDIO" >&2; exit 1; }

# ── 의존성 확인 ──
WHISPER_BIN="$(command -v whisper-cli || command -v whisper-cpp || true)"
[ -n "$WHISPER_BIN" ] || { echo "whisper-cli 없음 → 'brew install whisper-cpp' 필요" >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg 없음 → 'brew install ffmpeg' 필요" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "whisper 모델 없음: $MODEL" >&2; echo "  (WHISPER_MODEL 환경변수나 -m으로 지정 가능)" >&2; exit 1; }
if [ "$TRANSCRIPT_ONLY" -eq 0 ]; then
  [ -f "$PROMPT_FILE" ] || { echo "프롬프트 파일 없음: $PROMPT_FILE" >&2; exit 1; }
  command -v "${SUMMARIZER%% *}" >/dev/null 2>&1 || {
    echo "요약 명령 없음: $SUMMARIZER" >&2
    echo "  (MEETING_NOTES_SUMMARIZER로 바꾸거나 --transcript-only로 전사만 하세요)" >&2
    exit 1
  }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DATE_TAG="$(date +%Y-%m-%d_%H%M)"
SAFE_TITLE="$(printf '%s' "$TITLE" | tr '/' '-')"
mkdir -p "$OUT_DIR"
LOG_DIR="${MEETING_NOTES_LOG_DIR:-$OUT_DIR/.logs}"
mkdir -p "$LOG_DIR"
RUN_STAMP="$(date +%Y-%m-%d_%H%M%S)"
WHISPER_LOG="$LOG_DIR/${RUN_STAMP}_whisper.log"

echo "[1/3] 오디오 → 16kHz WAV 변환..." >&2
ffmpeg -nostdin -loglevel error -y -i "$AUDIO" -ar 16000 -ac 1 -c:a pcm_s16le "$WORK/audio.wav"

echo "[2/3] 로컬 전사 (whisper, lang=$LANG_CODE)..." >&2
# -mc 0: 이전 문맥을 물고 가지 않게 해서, 앞부분 무음 구간에서 생긴 반복 환각이
#        뒤 구간까지 전파되는 것을 막는다.
# stderr는 버리지 않고 로그 파일에 남긴다 (실패 원인 추적용).
# set -e 아래에서도 실패 안내를 출력하려고 if로 감싼다.
if ! "$WHISPER_BIN" -m "$MODEL" -l "$LANG_CODE" -mc 0 -f "$WORK/audio.wav" \
  --output-txt --output-file "$WORK/transcript" >"$WHISPER_LOG" 2>&1; then
  echo "❌ whisper 실행 실패. 로그: $WHISPER_LOG" >&2
  tail -n 5 "$WHISPER_LOG" >&2
  exit 1
fi

TRANSCRIPT_FILE="$WORK/transcript.txt"
[ -s "$TRANSCRIPT_FILE" ] || {
  echo "❌ 전사 결과가 비어 있음 (오디오/모델 확인). 로그: $WHISPER_LOG" >&2
  exit 1
}

if ! check_transcript "$TRANSCRIPT_FILE"; then
  DEGEN_BACKUP="$LOG_DIR/${RUN_STAMP}_transcript_degenerate.txt"
  cp "$TRANSCRIPT_FILE" "$DEGEN_BACKUP"
  echo "⚠️  전사가 거의 같은 문장의 반복입니다 ($QUALITY_REPORT) — 무음 구간 환각 루프로 추정." >&2
  echo "    whisper 로그: $WHISPER_LOG" >&2
  echo "    전사 원문 백업: $DEGEN_BACKUP" >&2
  echo "    → 요약은 계속 진행하지만, 결과가 부실하면 위 로그를 확인하세요." >&2
fi

if [ "$TRANSCRIPT_ONLY" -eq 1 ]; then
  RAW_OUT="$OUT_DIR/${DATE_TAG}_${SAFE_TITLE}_원문.txt"
  cp "$TRANSCRIPT_FILE" "$RAW_OUT"
  echo "✅ 전사 완료: $RAW_OUT" >&2
  echo "$RAW_OUT"
  exit 0
fi

echo "[3/3] 회의록 요약 ($SUMMARIZER)..." >&2
# 요약기에 넘길 입력: 프롬프트 → 용어집(있을 때) → 전사 원문
{
  cat "$PROMPT_FILE"
  if [ -f "$GLOSSARY_FILE" ] || [ -n "${MEETING_GLOSSARY:-}" ]; then
    printf '\n\n## 용어집\n'
    [ -f "$GLOSSARY_FILE" ] && awk 'NF && !/^#/' "$GLOSSARY_FILE"
    [ -n "${MEETING_GLOSSARY:-}" ] && printf -- '- 추가 교정(왼쪽=오인식, 오른쪽=정답): %s\n' "$MEETING_GLOSSARY"
  fi
  printf '\n\n## 전사 원문\n\n'
  cat "$TRANSCRIPT_FILE"
} > "$WORK/input.md"

if [ ! -f "$GLOSSARY_FILE" ] && [ -z "${MEETING_GLOSSARY:-}" ]; then
  echo "⚠️  용어집이 없습니다 ($GLOSSARY_FILE). 팀 고유 용어가 틀리게 정리될 수 있어요. README '용어집 만들기' 참고." >&2
fi

if ! eval "$SUMMARIZER" < "$WORK/input.md" > "$WORK/summary.md"; then
  echo "❌ 요약 실패 ($SUMMARIZER). 전사 원문을 남기려면 --keep-transcript나 --transcript-only로 다시 실행하세요." >&2
  exit 1
fi
[ -s "$WORK/summary.md" ] || { echo "❌ 요약 결과가 비어 있음 ($SUMMARIZER)" >&2; exit 1; }

OUT_FILE="$OUT_DIR/${DATE_TAG}_${SAFE_TITLE}.md"
{
  echo "# $TITLE ($(date '+%Y-%m-%d %H:%M'))"
  echo ""
  echo "> 원본: \`$AUDIO\`"
  echo ""
  cat "$WORK/summary.md"
} > "$OUT_FILE"

if [ "$KEEP_TRANSCRIPT" -eq 1 ]; then
  cp "$TRANSCRIPT_FILE" "$OUT_DIR/${DATE_TAG}_${SAFE_TITLE}_원문.txt"
  echo "전사 원문: $OUT_DIR/${DATE_TAG}_${SAFE_TITLE}_원문.txt" >&2
fi

# 후처리 훅 (선택): 할 일 앱에 액션 아이템 넣기 등. 실패해도 회의록은 남는다.
if [ -n "${MEETING_NOTES_POST_HOOK:-}" ]; then
  MEETING_NOTES_FILE="$OUT_FILE" sh -c "$MEETING_NOTES_POST_HOOK" || echo "⚠️  후처리 훅 실패 (회의록은 생성됨)" >&2
fi

echo "" >&2
echo "✅ 회의록 생성 완료: $OUT_FILE" >&2
echo "$OUT_FILE"
