# AGENTS.md

이 저장소를 받은 AI 에이전트(Codex, Gemini CLI, Claude Code 등)를 위한 안내다.

- **회의록을 만들어 달라는 요청**이면 [`SKILL.md`](SKILL.md)의 0 → 1 → 2 → 3 순서를 그대로 따른다.
- **처음 설치하는 사용자**면 `SKILL.md`의 0(설치 점검)과 1(용어집 만들기)부터 진행한다. 용어집은 사용자 팀에 맞게 새로 만들어야 하며, `glossary.example.txt`를 그대로 복사해 쓰지 않는다.
- **이 저장소의 코드를 고치는 작업**이면:
  - 스크립트는 POSIX sh로 유지한다 (bash 전용 문법 금지).
  - 고친 뒤 `sh tests/run.sh`를 실행한다. whisper와 요약기는 테스트에서 가짜 명령으로 대체되므로 모델 없이 돈다.
  - `shellcheck scripts/meeting-notes.sh`가 있으면 함께 돌린다.
- 용어집(`glossary.txt`), 녹음 파일, 전사 원문, 생성된 회의록은 커밋하지 않는다.
