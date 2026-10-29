# meeting-notes

회의 녹음 파일을 회의록 마크다운으로 정리하는 CLI이자 AI 에이전트 스킬입니다.

```
녹음 파일 → ffmpeg → whisper.cpp (로컬 전사) → 요약 → 회의록.md
```

- **음성은 내 컴퓨터 밖으로 나가지 않습니다.** 전사는 whisper.cpp로 로컬에서 합니다.
- **요약 단계에서는 전사 텍스트가 요약하는 AI에게 전달됩니다.** 완전 로컬이 필요하면 요약기를 Ollama 같은 로컬 모델로 바꾸세요.
- 회의록은 요약 · 논의 내용 · 결정 사항 · 액션 아이템 · 기타/미결로 정리됩니다. 음성인식이 자주 틀리는 사람 이름은 넣지 않습니다.
- 실제 업무 회의 18건에 쓰면서 다듬었습니다.

## AI에게 맡기기 (가장 빠른 방법)

Claude Code, Codex, Gemini CLI 등에 저장소 주소와 함께 이렇게 말하면 됩니다.

> 이 저장소를 받아서 SKILL.md대로 meeting-notes를 설치해 줘. 설치가 끝나면 우리 팀 용어집도 같이 만들자.
> https://github.com/msk226/meeting-notes

그 뒤에는 이렇게 요청합니다.

> ~/Downloads/주간회의.m4a 회의록 만들어 줘.

에이전트는 [`SKILL.md`](SKILL.md)의 절차를 따릅니다. 설치 점검 → 용어집 → 전사 → 요약 → 결과 확인 순서입니다. 패키지 설치나 모델 다운로드 전에는 사용자에게 먼저 묻도록 되어 있습니다.

### Claude Code 스킬로 설치

```sh
git clone https://github.com/msk226/meeting-notes ~/.claude/skills/meeting-notes
```

Codex·Gemini CLI는 저장소 폴더에서 실행하면 `AGENTS.md` / `GEMINI.md`를 읽고 같은 절차를 따릅니다.

## ⚠️ 용어집은 직접 만들어야 합니다

음성인식은 회사·팀 고유 용어를 거의 항상 틀립니다. 사내 시스템 이름, 약어, 업무 용어가 특히 그렇습니다 (`OMS` → "옴스", `Redis` → "레디스").
**이 저장소에는 예시([`glossary.example.txt`](glossary.example.txt))만 있습니다. 각자 자기 팀 상황에 맞는 용어집을 새로 만들어야 합니다.** 용어집 없이도 동작은 하지만 회의록 품질이 크게 떨어집니다.

### 용어집 만들기

1. `~/.config/meeting-notes/glossary.txt`를 만듭니다.
2. 한 줄에 한 용어씩 이 형식으로 씁니다.
   ```
   정식표기 — 뜻 (자주 들리는 오인식 → 정식표기)
   OMS — 주문관리시스템 (오엠에스/옴스 → OMS)
   ```
3. 처음에는 팀 문서나 위키에서 시스템 이름과 약어부터 모읍니다.
4. **가장 효과가 큰 방법**은 실제 녹음 하나를 `--transcript-only`로 전사해 보고, 원문에서 틀리게 받아쓴 단어를 `오인식 → 정식표기`로 추가하는 것입니다.
5. 회의를 정리할 때마다 새로 틀린 용어를 추가합니다.

AI 에이전트에게 "용어집 만들어 줘"라고 하면 위 과정을 같이 진행합니다.

용어집에는 회사 내부 정보가 들어갑니다. **공개 저장소에 올리지 마세요.** `.gitignore`에 `glossary.txt`가 들어 있습니다.

## 직접 설치

### macOS

```sh
brew install ffmpeg whisper-cpp

mkdir -p ~/.local/share/whisper-models
curl -L -o ~/.local/share/whisper-models/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin   # 약 1.6GB

git clone https://github.com/msk226/meeting-notes
ln -s "$PWD/meeting-notes/scripts/meeting-notes.sh" ~/.local/bin/meeting-notes

meeting-notes --doctor
```

저사양 기기라면 `ggml-small.bin`(약 470MB)을 받아 `WHISPER_MODEL`로 지정하세요.

### Linux

```sh
sudo apt install ffmpeg build-essential cmake
git clone https://github.com/ggml-org/whisper.cpp && cd whisper.cpp
cmake -B build && cmake --build build -j --config Release
cp build/bin/whisper-cli ~/.local/bin/
```

모델과 스크립트 설치는 macOS와 같습니다.

## 사용법

```sh
meeting-notes ~/Downloads/주간회의.m4a -t "주간 회의"
# → ~/Documents/회의록/2026-10-29_1530_주간 회의.md

meeting-notes 녹음.m4a --transcript-only     # 전사만 (요약은 AI 에이전트가 직접)
meeting-notes 녹음.m4a --keep-transcript     # 회의록과 전사 원문을 함께 저장
MEETING_GLOSSARY="옴스→OMS" meeting-notes 녹음.m4a   # 이번 실행에만 추가 교정
```

### 맥에서 녹음하기: 음성 메모 앱

따로 녹음 앱을 설치할 필요 없이 맥이나 아이폰의 **음성 메모** 앱으로 녹음하면 됩니다. 음성 메모는 `.m4a` 파일로 저장되고, meeting-notes는 이 형식을 바로 받습니다.

1. 음성 메모 앱에서 녹음합니다. 아이폰에서 녹음해도 같은 Apple 계정이면 iCloud로 맥의 음성 메모 앱에 동기화됩니다.
2. 녹음을 파일로 꺼냅니다. 방법은 둘 중 하나입니다.
   - 녹음 항목을 Finder나 데스크톱으로 **드래그**
   - 녹음 항목을 우클릭하고 **공유 → 파일에 저장**
3. 꺼낸 파일로 실행합니다.
   ```sh
   meeting-notes ~/Desktop/주간회의.m4a -t "주간 회의"
   ```
   AI 에이전트를 쓰면 "데스크톱에 있는 주간회의.m4a 회의록 만들어 줘"라고 해도 됩니다.

> 음성 메모 원본은 `~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings`에 있습니다. 터미널에서 바로 읽으려면 터미널 앱에 **전체 디스크 접근 권한**이 필요합니다. 그래서 드래그로 꺼내는 쪽이 간단합니다.

녹음 팁:
- 노트북을 회의 테이블 가운데에 두면 화자마다 음량 차이가 줄어 전사가 잘 됩니다.
- 회의 시작 전 긴 무음 구간이 있어도 괜찮습니다. 환각 루프가 생기지 않게 막혀 있고, 생기더라도 경고가 나옵니다.

요약기는 표준 입력으로 프롬프트를 받아 표준 출력으로 회의록을 내는 명령이면 무엇이든 됩니다.

```sh
export MEETING_NOTES_SUMMARIZER="claude -p"            # 기본값
export MEETING_NOTES_SUMMARIZER="ollama run qwen2.5:14b" # 완전 로컬
```

회의록 형식을 바꾸고 싶으면 `prompt.md`를 `~/.config/meeting-notes/prompt.md`로 복사해서 고치세요. 전체 옵션은 [`SKILL.md`](SKILL.md#옵션과-환경변수)에 있습니다.

## 조용한 실패 막기: whisper 환각 루프

38분 녹음에서 회의 앞부분 얘기만 나온 적이 있습니다. whisper가 무음 구간에서 같은 문장을 2,146줄 반복했고, 스크립트는 에러 없이 끝났습니다.

`-mc 0` 옵션으로 해결했습니다(같은 녹음이 424줄 정상 전사). 같은 문제가 다시 생겨도 알아챌 수 있게 고유 줄 비율 감지와 로그 보존을 넣었습니다. 처음 만든 감지 로직은 실제 실패 사례를 놓쳐서 다시 설계했습니다. 자세한 과정은 [docs/hallucination-loop.md](docs/hallucination-loop.md)에 있습니다.

## 테스트

```sh
sh tests/run.sh
```

whisper와 요약기를 가짜 명령으로 바꿔서 모델 없이 실행합니다. ffmpeg만 있으면 됩니다.

## 주의

- 회의를 녹음할 때는 참석자에게 먼저 동의를 받으세요.
- 녹음, 전사 원문, 용어집, 회의록을 공개 저장소에 올리지 마세요.

## License

MIT
