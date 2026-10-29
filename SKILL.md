---
name: meeting-notes
description: 회의 녹음 파일(m4a, mp3, wav, mp4 등)을 로컬 whisper.cpp로 전사하고 회의록 마크다운(요약·논의·결정·액션 아이템)으로 정리한다. "회의록 만들어줘", "이 녹음 정리해줘", "회의 요약해줘", "회의록 용어집 만들어줘" 같은 요청에 사용한다.
---

# meeting-notes

녹음 파일 → ffmpeg → whisper.cpp(로컬 전사) → 요약 → 회의록 마크다운.
음성은 이 컴퓨터 밖으로 나가지 않는다. 요약 단계에서는 **전사 텍스트**가 요약하는 AI에게 전달된다.

이 문서는 Claude Code, Codex, Gemini CLI 같은 AI 에이전트가 그대로 따라 실행하도록 쓴 절차다.
아래에서 `scripts/`, `prompt.md`는 이 파일이 있는 폴더 기준 경로다.

## 0. 설치 상태 점검

```sh
sh scripts/meeting-notes.sh --doctor
```

❌가 있으면 사용자에게 무엇을 설치할지 알리고 **동의를 받은 뒤** 설치한다.

| 항목 | macOS | Linux |
|---|---|---|
| ffmpeg | `brew install ffmpeg` | `sudo apt install ffmpeg` |
| whisper.cpp | `brew install whisper-cpp` | README의 "Linux 설치" (소스 빌드 후 `whisper-cli`를 PATH에) |
| 모델 (약 1.6GB) | 아래 명령 | 아래 명령 |

```sh
mkdir -p ~/.local/share/whisper-models
curl -L -o ~/.local/share/whisper-models/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

모델 파일이 커서 다운로드 전에 반드시 사용자에게 확인한다. 저사양 기기라면 `ggml-small.bin`(약 470MB)을 쓰고 `WHISPER_MODEL`로 경로를 지정한다.

## 1. 용어집 만들기 (처음 한 번, 이후 계속 보강)

**용어집은 사용자마다 직접 만들어야 한다.** 이 저장소에는 예시(`glossary.example.txt`)만 있다.
음성인식은 사내 시스템 이름, 약어, 팀 고유 용어를 거의 항상 틀린다 (예: `OMS` → "옴스", `Redis` → "레디스").
용어집이 없어도 동작은 하지만 회의록 품질이 크게 떨어진다.

`--doctor`에서 용어집이 없다고 나오면 사용자와 함께 만든다:

1. 사용자에게 묻는다: 어떤 팀·도메인인지, 회의에 자주 나오는 시스템 이름·약어·업무 용어가 무엇인지.
2. 사용자가 **허락한 자료만** 참고해 후보를 모은다: 팀 문서, 저장소 README와 코드의 도메인 용어, 위키, 이전 회의록.
3. 가장 효과가 큰 방법: 실제 녹음 하나를 `--transcript-only`로 전사한 뒤, 원문에서 틀리게 받아쓴 단어를 찾아 `오인식 → 정식표기` 쌍으로 넣는다.
4. `glossary.example.txt` 형식으로 `~/.config/meeting-notes/glossary.txt`에 저장한다.
   ```
   정식표기 — 뜻 (자주 들리는 오인식 → 정식표기)
   ```
5. 지킬 것
   - 비밀번호·토큰·고객 정보는 넣지 않는다.
   - 용어집에는 회사 내부 정보가 들어가므로 **저장소에 커밋하거나 공개하지 않는다** (`.gitignore`에 포함됨).
   - 사람 이름은 넣지 않는다. 회의록에 이름을 쓰지 않는 정책이다.

회의를 정리할 때마다 새로 틀린 용어가 보이면 사용자에게 용어집 추가를 제안한다.

## 2. 회의록 만들기

### 기본: 전사는 스크립트, 요약은 지금 대화 중인 AI가 직접

어떤 에이전트든 이 방식으로 동작한다. 별도 요약 CLI가 필요 없다.

```sh
sh scripts/meeting-notes.sh "<녹음 파일>" --transcript-only -t "<회의 제목>"
```

1. 마지막 줄에 출력되는 전사 원문 경로를 읽는다.
2. `prompt.md`의 지시와 `~/.config/meeting-notes/glossary.txt`(있으면)를 적용해 직접 회의록을 쓴다.
3. 원문 파일과 같은 폴더에 `<날짜>_<제목>.md`로 저장한다. 첫 줄은 `# <제목> (<YYYY-MM-DD HH:MM>)`, 다음은 `> 원본: \`<녹음 파일>\``.

전사가 길면(대략 3만 자 이상) 나눠 읽고 주제별로 합친다.

### 대안: 스크립트가 요약까지 (터미널 단독 실행용)

```sh
sh scripts/meeting-notes.sh "<녹음 파일>" -t "<회의 제목>"
```

요약 명령은 기본 `claude -p`이고 `MEETING_NOTES_SUMMARIZER`로 바꾼다. 명령은 표준 입력으로 프롬프트+용어집+전사 원문을 받아 표준 출력으로 회의록을 내야 한다.

```sh
MEETING_NOTES_SUMMARIZER="ollama run qwen2.5:14b"   # 완전 로컬
MEETING_NOTES_SUMMARIZER="gemini"                    # Gemini CLI
```

## 3. 결과 확인

- `⚠️ 전사가 거의 같은 문장의 반복입니다` 경고가 나오면 회의록을 그대로 믿지 말고 사용자에게 알린다. 무음 구간 환각 루프다 (`docs/hallucination-loop.md`). 로그와 원문 백업 경로가 경고에 함께 나온다.
- 액션 아이템의 담당은 `미정`으로 나온다. 담당자 지정은 사용자에게 맡긴다.
- 사용자에게 저장 경로와 요약 3~5줄을 보여 준다.

## 옵션과 환경변수

| 옵션 / 변수 | 기본값 | 설명 |
|---|---|---|
| `-l` | `ko` | whisper 언어 코드 |
| `-m` / `WHISPER_MODEL` | `~/.local/share/whisper-models/ggml-large-v3-turbo.bin` | 모델 경로 |
| `-o` / `MEETING_NOTES_DIR` | `~/Documents/회의록` | 출력 폴더 |
| `-t` | `회의록` | 제목 (파일명에도 쓰임) |
| `--keep-transcript` | 끔 | 요약과 함께 전사 원문도 저장 |
| `--transcript-only` | 끔 | 전사만 하고 끝냄 |
| `MEETING_GLOSSARY_FILE` | `~/.config/meeting-notes/glossary.txt` | 용어집 위치 |
| `MEETING_GLOSSARY` | 없음 | 이번 실행에만 쓸 추가 교정 (`옴스→OMS, 레디스→Redis`) |
| `MEETING_NOTES_PROMPT` | `~/.config/meeting-notes/prompt.md`, 없으면 저장소 `prompt.md` | 요약 프롬프트 |
| `MEETING_NOTES_SUMMARIZER` | `claude -p` | 요약 명령 |
| `MEETING_NOTES_POST_HOOK` | 없음 | 회의록 생성 후 실행할 명령. `$MEETING_NOTES_FILE`로 파일 경로를 받음 |

## 하지 말 것

- 사용자 동의 없이 패키지 설치나 대용량 모델 다운로드를 하지 않는다.
- 녹음 파일, 전사 원문, 용어집을 외부 서비스에 업로드하지 않는다 (요약 단계에서 사용자가 고른 요약 AI에 전사 텍스트를 넘기는 것은 예외).
- 회의록에 사람 이름을 넣지 않는다.
