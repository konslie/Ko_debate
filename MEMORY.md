# MEMORY (Project Continuity & Context)

## Current Status (현재 진행 상황)
- [x] 요구사항 분석 및 프로젝트 컨셉 정의
- [x] `PRD.md` 작성 완료
- [x] 양쪽 Option 키 감지 모니터 설계 및 검증
- [x] 10cm 물리 렌더링 디스플레이 연산 로직 세팅 완료
- [x] AVCaptureConnection 비디오 오리엔테이션 및 미러링 제거 반영 완료
- [x] Vision 실시간 얼굴 추적 100% 정상 가동 성공
- [x] Window Level Cmd + Q 단축키 즉시 종료 구현 완료
- [x] v1.0.1 튜닝 빌드 및 무경고 수준 배포 완료

## Core Technical Decisions (주요 기술적 결정)
1. **Vision Orientation 정밀 싱크**:
   - `AVCaptureVideoDataOutput` 커넥션의 `videoOrientation`을 `.landscapeRight`로 강제 정렬하여, 센서 프레임이 회전되어 들어오는 바람에 Vision의 얼굴 인식이 먹통이 되던 고질적인 현상을 우아하게 영구 박멸함.
2. **미러링 해제에 따른 캔버스 공간 이동 부호 교정**:
   - 좌우반전이 풀린 실시간 렌더링 캔버스 특성을 반영해 X축 얼굴 이동 중심 공식을 `(0.5 - faceX)`로 기하학적 좌우 반전 교정.
3. **콤팩트 10cm 지름 및 확대율 억제**:
   - 윈도우 지름을 10cm(100mm) 규격인 약 `430pt`로 슬림화하고, 과도한 얼굴 클로즈업을 방지하도록 댐핑 확대 상수를 극단적으로 억제(`calculatedScale` 최대 1.35배 제한)하여 가장 세련된 원근 시야 제공.
4. **Command + Q 가로채기**:
   - `LSUIElement` 백그라운드 에이전트의 종료 한계를 극복하기 위해 `NSWindow.keyDown` 단에서 `Cmd+Q` 키 플래그를 정교하게 엣지 인터셉트하여 `NSApp.terminate`로 완벽 맵핑.

## Next Steps for The User (사용자 검증 단계)
1. 10cm 크기의 깜찍하고 세련된 정방향 원형 창 확인.
2. 머리를 움직일 때 Vision AI가 버터처럼 부드럽게 감지하여 얼굴을 중앙으로 트래킹하는 동작 체감.
3. 거울 창을 보다가 `Command(⌘) + Q` 또는 `ESC`를 누르며 즉시 종료/은닉 성능 만끽.
