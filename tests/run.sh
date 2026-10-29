#!/bin/sh
# meeting-notes 테스트. whisper와 요약기를 가짜 명령으로 바꿔서 모델 없이 돈다.
# 필요: ffmpeg (테스트용 무음 오디오 생성)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/scripts/meeting-notes.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); echo "  ✅ $1"; }
ng() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

# ── 가짜 명령 ──
mkdir -p "$T/bin"
cat > "$T/bin/whisper-cli" <<'EOF'
#!/bin/sh
# --output-file <prefix> 를 찾아 <prefix>.txt에 FAKE_TRANSCRIPT 내용을 쓴다
while [ $# -gt 0 ]; do
  [ "$1" = "--output-file" ] && OUT="$2"
  shift
done
echo "fake whisper log"
[ "${FAKE_WHISPER_RC:-0}" -eq 0 ] || { echo "fake whisper error" >&2; exit "$FAKE_WHISPER_RC"; }
cp "$FAKE_TRANSCRIPT" "$OUT.txt"
EOF
cat > "$T/bin/fake-summarizer" <<'EOF'
#!/bin/sh
cat > "$FAKE_SUMMARY_INPUT"
[ "${FAKE_SUMMARY_RC:-0}" -eq 0 ] || exit "$FAKE_SUMMARY_RC"
printf '## 요약\n- 테스트 요약\n'
EOF
chmod +x "$T/bin/whisper-cli" "$T/bin/fake-summarizer"

ffmpeg -nostdin -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono -t 1 "$T/a.wav"
touch "$T/model.bin"

i=1
while [ $i -le 40 ]; do echo "정상 회의 발언 $i 번째 문장입니다" >> "$T/normal.txt"; i=$((i+1)); done
# 실제 실패 사례처럼 미세 변주가 섞인 반복 (고유 줄 12개, 200줄)
i=1
while [ $i -le 200 ]; do echo "오늘 회의를 시작하겠습니다 $((i % 12))" >> "$T/degen.txt"; i=$((i+1)); done
printf '%s\n' '- Redis — (레디스 → Redis)' > "$T/glossary.txt"

run() {
  PATH="$T/bin:$PATH" WHISPER_MODEL="$T/model.bin" MEETING_NOTES_DIR="$T/out" \
    MEETING_GLOSSARY_FILE="$T/glossary.txt" MEETING_NOTES_SUMMARIZER="fake-summarizer" \
    FAKE_SUMMARY_INPUT="$T/summary_input.md" "$@"
}

echo "meeting-notes tests"

# 1. 반복 감지
sh "$CLI" --check-transcript "$T/normal.txt" >/dev/null; [ $? -eq 0 ] && ok "정상 전사는 통과" || ng "정상 전사는 통과"
sh "$CLI" --check-transcript "$T/degen.txt" >/dev/null; [ $? -eq 2 ] && ok "미세 변주 반복을 감지" || ng "미세 변주 반복을 감지"

# 2. 정상 실행
rm -rf "$T/out"
OUT="$(run env FAKE_TRANSCRIPT="$T/normal.txt" sh "$CLI" "$T/a.wav" -t "주간 회의" 2>"$T/err")"
if [ -f "$OUT" ] && grep -q "테스트 요약" "$OUT" && head -1 "$OUT" | grep -q "^# 주간 회의"; then ok "회의록 생성"; else ng "회의록 생성"; cat "$T/err"; fi
grep -q "## 용어집" "$T/summary_input.md" && grep -q "레디스" "$T/summary_input.md" && ok "용어집을 요약 입력에 포함" || ng "용어집을 요약 입력에 포함"
grep -q "정상 회의 발언 1 번째" "$T/summary_input.md" && ok "전사 원문을 요약 입력에 포함" || ng "전사 원문을 요약 입력에 포함"

# 3. 전사만
rm -rf "$T/out"
OUT="$(run env FAKE_TRANSCRIPT="$T/normal.txt" sh "$CLI" "$T/a.wav" --transcript-only 2>/dev/null)"
case "$OUT" in *_원문.txt) [ -s "$OUT" ] && ok "--transcript-only는 원문만 저장" || ng "--transcript-only는 원문만 저장" ;; *) ng "--transcript-only는 원문만 저장" ;; esac

# 4. 반복 경고
rm -rf "$T/out"
run env FAKE_TRANSCRIPT="$T/degen.txt" sh "$CLI" "$T/a.wav" >/dev/null 2>"$T/err"
grep -q "반복입니다" "$T/err" && ls "$T/out/.logs/"*_transcript_degenerate.txt >/dev/null 2>&1 && ok "반복 경고와 원문 백업" || ng "반복 경고와 원문 백업"

# 5. whisper 실패 시 안내가 출력되는지 (set -e에 묻히지 않는지)
rm -rf "$T/out"
run env FAKE_TRANSCRIPT="$T/normal.txt" FAKE_WHISPER_RC=3 sh "$CLI" "$T/a.wav" >/dev/null 2>"$T/err"
RC=$?
[ $RC -ne 0 ] && grep -q "whisper 실행 실패" "$T/err" && ok "whisper 실패 안내" || ng "whisper 실패 안내 (rc=$RC)"

# 6. 요약 실패 시 빈 회의록을 남기지 않는지
rm -rf "$T/out"
run env FAKE_TRANSCRIPT="$T/normal.txt" FAKE_SUMMARY_RC=1 sh "$CLI" "$T/a.wav" >/dev/null 2>"$T/err"
RC=$?
if [ $RC -ne 0 ] && grep -q "요약 실패" "$T/err" && ! ls "$T/out/"*.md >/dev/null 2>&1; then ok "요약 실패 시 파일 미생성"; else ng "요약 실패 시 파일 미생성"; fi

# 7. 용어집이 없으면 경고
rm -rf "$T/out"
PATH="$T/bin:$PATH" WHISPER_MODEL="$T/model.bin" MEETING_NOTES_DIR="$T/out" \
  MEETING_GLOSSARY_FILE="$T/none.txt" MEETING_NOTES_SUMMARIZER="fake-summarizer" \
  FAKE_SUMMARY_INPUT="$T/summary_input.md" FAKE_TRANSCRIPT="$T/normal.txt" \
  sh "$CLI" "$T/a.wav" >/dev/null 2>"$T/err"
grep -q "용어집이 없습니다" "$T/err" && ok "용어집 없음 경고" || ng "용어집 없음 경고"

echo ""
echo "통과 $PASS, 실패 $FAIL"
[ "$FAIL" -eq 0 ]
