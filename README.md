# 7조 2-Player FPGA Baseball

Vivado 2024.1에서 편집하고 시뮬레이션할 수 있는 Verilog-2001 프로젝트다. 경기 규칙은 최신 7조 제안서, 패키지 핀은 `COMM206_fpga_pin_map.pdf`를 기준으로 정했다.

## Vivado에서 바로 실행하기

시뮬레이션 프로젝트가 이미 있다면 **File → Open Project**에서 `build/sim/FPGA_BASEBALL_GAME.xpr`를 연 뒤 **Run Behavioral Simulation**을 누른다.

1. 프로젝트를 새로 만들려면 Vivado 2024.1에서 **File → Close Project**로 열린 프로젝트를 먼저 닫는다. 시작 화면의 Tcl Console을 열고 아래 경로를 내려받은 프로젝트 폴더의 절대 경로로 바꾼다.

   ```tcl
   set argv {sim}
   source {C:/경로/FPGA_BASEBALL_GAME/scripts/create_project.tcl}
   ```

2. **Flow Navigator → Simulation → Run Simulation → Run Behavioral Simulation**을 누른다. 기본 Design Top은 `baseball_top`, 기본 Simulation Top은 `tb_baseball_top`이다. 콘솔에서 `PASS tb_baseball_top`을 확인한다.
3. 다른 테스트는 **Sources → Simulation Sources**에서 해당 `tb_*.v`의 모듈을 우클릭해 **Set as Top**으로 설정한 뒤 실행한다. 시뮬레이션이 일찍 멈춘 경우 **Run All**을 누른다.

생성 스크립트는 기본적으로 `build/sim/FPGA_BASEBALL_GAME.xpr`에 프로젝트를 만든다. 시뮬레이션 프로젝트는 Vivado 생성용 예시 Part `xc7s50csga324-1`을 사용한다. 실제 보드 Part와 핀 제약은 하드웨어 설정을 적용할 때 들어간다. Windows 경로 길이 문제가 생기면 `set argv {sim C:/짧은폴더/baseball_sim}`처럼 출력 폴더를 따로 지정한다.

### GUI로 프로젝트 만들기

1. **File → Project → New → RTL Project**에서 프로젝트를 만들고, 시뮬레이션만 할 때는 예시 Part를 선택한다. 실기는 확인한 Part를 선택한다.
2. **Add Sources → Add or Create Design Sources**로 `rtl/*.v` 13개와 `rtl/baseball_defs.vh`를 넣고 `baseball_top`을 **Set as Top**으로 지정한다.
3. **Add Sources → Add or Create Simulation Sources**로 `sim/tb_*.v` 8개를 넣고 `tb_baseball_top`을 **Set as Top**으로 지정한다. 헤더를 찾지 못하면 **Settings → Synthesis → Verilog Options** 및 **Settings → Simulation → Compilation**의 include 경로에 `rtl` 폴더를 지정한다.
4. 실기 프로젝트에서 **Tools → Run Tcl Script**로 `scripts/apply_board_settings.tcl`을 실행하면 `constraints/comm206_pins.xdc`, 자동 생성한 `baseball_clock_io.generated.xdc`, FPGA Part, RTL 파라미터가 함께 적용된다.

### 전체 테스트를 한 번에 실행하기

프로젝트 폴더에서 PowerShell로 실행한다. Vivado 도구가 PATH에 있으면 `-VivadoBin`을 생략할 수 있다. Vivado가 없는 경우 Icarus Verilog가 PATH에 설치된 환경에서 `-Simulator Icarus`를 사용할 수 있다.

```powershell
.\scripts\run_tests.ps1 -Simulator XSim -VivadoBin 'C:\Xilinx\Vivado\2024.1\bin'
.\scripts\run_tests.ps1 -Simulator XSim -VivadoBin 'C:\Xilinx\Vivado\2024.1\bin' -Top tb_one_pitch
```

각 테스트는 기대값과 실제값을 비교한다. XSim 로그는 기본적으로 `build/sim_tests/`에 저장된다. 스크립트는 PASS 표식이 누락되거나 오류가 나오면 실패를 반환한다. [AMD Vivado 2024.1 시뮬레이션 안내서](https://docs.amd.com/r/2024.1-English/ug900-vivado-logic-simulation/Compiling-and-Simulating)

| 테스트벤치 | 확인 항목 |
|---|---|
| `tb_button_input` | 접점 바운스, 길게 누름, 떼고 재입력, 구종 동시 입력, 준비 중 시작한 스윙, 리셋, 1ms tick |
| `tb_pitch_engine` | 직구와 볼의 일치, 변화구 LED 6–8 가속과 직구보다 긴 전체 이동 시간, 위치별 one-hot LED, 종료와 중단 |
| `tb_one_pitch` | LED 1–8 스윙, 무스윙, 7→8·8→종료 직전/동일/직후 클럭, 공당 판정 한 번, HBP 후보 래치와 LFSR 주기 |
| `tb_runner_update` | 8가지 주자 상태에서 안타·강제 진루·홈런의 진루와 득점 |
| `tb_game_manager` | 네 번째 볼, 세 번째 스트라이크, HBP, 득점 한 번과 255점 포화, 공수 교대, 끝내기 없이 3아웃, 승·패·무승부, 리셋 |
| `tb_displays` | `0123`·`0255` 8자리 스캔, 1·2·3루 등, LCD 16자 문구·명령·바이트 순서와 전송 타이밍 |
| `tb_effect_ctrl` | 준비음, 홈런 세 음, RGB 점멸, 효과 도중 리셋 |
| `tb_baseball_top` | 보드 버튼 입력만으로 1루타→2루타→홈런, 3:0 종료, 종료 후 입력 무시, 경기 중·종료 후 리셋 |

Vivado 2024.1 XSim에서 테스트 8개를 실행해 모두 통과했다. 생성한 Vivado 프로젝트의 기본 Behavioral Simulation에서도 `tb_baseball_top`이 통과했다. 예시 Part `xc7s50csga324-1`에서 RTL 합성을 완료했고 합성 결과에서 래치가 없음을 확인했다. `xc7s75fgga484-1`의 50 MHz 시험 설정으로 배치·배선, 타이밍 검사, 비트스트림 생성을 확인했다. 실제 보드의 전압과 조명 극성은 확인이 필요하다.

## 회로 연결과 버스

모든 순차회로의 클럭은 `clk_sys`다. `tick_ms`는 1클럭 길이의 갱신 허용 신호다. 버튼은 2단 동기화와 ms 표본 디바운스를 거친다. `rst`는 게임 로직에 동기식으로 적용하고, 부팅 시 처음 네 클럭에도 리셋을 유지한다. 버튼과 tick 카운터는 리셋 버튼을 떼는 동안에도 계속 동작한다.

| 파일 | 주요 입력 → 출력과 역할 |
|---|---|
| `button_input.v` | 논리 버튼 `{SW_*,SW_3,SW_2,SW_1,SW_0}`, `tick_ms`, `swing_window` → `pitch_req`, `pitch_sel`, `swing_pulse`, `rst` |
| `tick_gen.v` | `clk_sys` → `tick_ms`. 1,000으로 나누어떨어지지 않는 주파수에서도 평균 간격은 1ms |
| `pitch_engine.v` | `pitch_ctrl`, `tick_ms` → `led`, `pitch_bus`. LED 8도 해당 구종의 한 구간 동안 점등 |
| `hbp_rng.v` | `clk_sys`, `rst` → `hbp_candidate`. 최대 주기 16비트 LFSR |
| `hit_judge.v` | `pitch_bus`, `swing_pulse`, `hbp_candidate` → `result_valid`, `result_code` |
| `runner_update.v` | `runner_req` → `runner_res`. 현재 주자와 진루 종류로 다음 주자 및 득점 계산 |
| `game_manager.v` | `pitch_req/sel`, `result_valid/code`, `runner_res` → `pitch_ctrl`, `runner_req`, `scores`, `bases`, `lcd_state`, `fx_evt` |
| `score_7seg.v` | `scores`, `tick_ms` → 10진수 `seg_com`, `seg_data`. 자리마다 약 1ms, 전환 시 1클럭 공백 |
| `base_lights_ctrl.v` | `bases` → 세 베이스의 녹색 표시등 |
| `lcd_line_gen.v` | `lcd_state` → `line1`, `line2`. 각 줄 16바이트, 왼쪽 문자부터 `[127:120]`에 저장 |
| `lcd_driver.v` | `line1`, `line2` → `lcd_data`, `lcd_rs`, `lcd_rw`, `lcd_e` |
| `effect_ctrl.v` | `fx_evt`, `tick_ms` → `piezo`, `rgb_r/g/b` |
| `baseball_top.v` | 위 모듈을 연결하고 물리 포트의 극성과 7세그먼트 자리 방향을 적용 |

| 버스 | 비트 순서와 코드 |
|---|---|
| `pitch_ctrl[3:0]` | `[3]` 시작, `[2]` 정지, `[1:0]` 구종. 직구 0, 변화구 1, 볼 2 |
| `pitch_bus[7:0]` | `[7]` 진행, `[6]` 이번 상승 에지에 종료, `[5:4]` 구종, `[3:0]` 위치. 시작 에지에는 진행 1·위치 0, 점등 중 위치 1–8 |
| `result_code[2:0]` | 0 초기값, 1 헛스윙, 2 루킹, 3 일반 볼, 4 HBP, 5 1루타, 6 2루타, 7 홈런. `result_valid`가 1인 1클럭에 유효 |
| `runner_req[5:0]` | `[5:3]` 현재 주자, `[2:0]` 진루 종류. 0 유지, 1 강제 진루, 2 1루타, 3 2루타, 4 홈런 |
| `runner_res[5:0]` | `[5:3]` 다음 주자, `[2:0]` 추가 득점. 주자의 비트 0/1/2는 1/2/3루 |
| `scores[15:0]` | `[15:8]` P1, `[7:0]` P2. 무부호 8비트, 각 255점에서 포화 |
| `lcd_state[12:0]` | `[12]` 종료, `[11:10]` 결과(0 진행, 1 P1 승, 2 P2 승, 3 무승부), `[9]` 공격(0 TOP, 1 BOT), `[8:7]` 볼, `[6:5]` 스트라이크, `[4:3]` 아웃, `[2:0]` 최근 판정 |
| `fx_evt[1:0]` | 0 없음, 1 준비 시작, 2 홈런. 해당 이벤트 처리 에지에서 한 번 소비 |

코드 상수는 `rtl/baseball_defs.vh`에 모았다. 투구 시작 에지에서 후보를 저장한 뒤 LED 1이 켜진다. 이동 또는 LED 8 종료와 `swing_pulse`가 겹치면 에지 직전 위치에서 스윙을 판정한다. 물리 버튼이 준비 중에 눌려 유지되면, 디바운스가 LED 1에서 끝나도 스윙 펄스를 내지 않는다.

`game_manager`는 판정 펄스를 받은 에지에 코드를 저장하고 투구를 멈춘다. 다음 에지에 저장한 판정으로 계산된 `runner_res`를 반영한다. 볼넷·HBP는 연속으로 점유한 1루부터 강제 진루한다. 삼진 및 진루로 타석이 끝나면 B/S를 지우고, 초의 세 번째 아웃에서 주자와 아웃을 지운 뒤 말로 넘어간다. 말의 세 번째 아웃에서 최종 승패와 점수를 유지한다.

## 속도와 효과 조정

| 바꿀 파일 | 파라미터와 초기값 |
|---|---|
| `rtl/baseball_top.v` | `DEBOUNCE_MS=20`, `PREP_MS=300`, `FAST_STEP_MS=220`, `CURVE_EARLY_MS=300`, `CURVE_LATE_MS=120`, `RESULT_MS=950`, `HOMER_MS=900`. 시간은 양의 정수 ms |
| `rtl/baseball_top.v` | `HBP_SEED=16'h1ace`, `HBP_THRESHOLD=9830`. 기준은 0–65,535이며 9,830/65,535개의 상태가 후보(약 15%). 0 시드는 1로 치환하고, 0 기준은 HBP를 끈다. 실제 투구에서 후보는 버튼 타이밍에 따른 LFSR 표본 |
| `rtl/effect_ctrl.v` | `PREP_HZ=1500`, `HOMER_LOW_HZ=523`, `HOMER_MID_HZ=659`, `HOMER_HIGH_HZ=784`, `BLINK_MS=125`. 홈런의 3구간 동안 네 RGB의 R/G를 함께 점멸. 전체 효과를 들으려면 `RESULT_MS ≥ HOMER_MS` 유지 |
| `constraints/board_config.tcl` | 보드 Part, 실제 `clk_hz`, I/O 표준, 반전 마스크, 7세그먼트 방향, LCD 호환 방식 |

최상위 RTL의 기본 `CLK_HZ=50000000`은 예시값이다. `tb_baseball_top`은 10kHz와 짧은 타이밍을 별도로 지정한다. 준비 중 모든 구종은 같은 음을 낸다. 스윙 없이 LED 1부터 LED 8이 꺼질 때까지 직구와 볼은 각각 1,760ms가 걸린다. 변화구는 LED 1–5에 각각 300ms, LED 6–8에 각각 120ms가 걸려 총 1,860ms다.

시간을 바꿀 때는 후반이 전반보다 빠르도록 `CURVE_LATE_MS < CURVE_EARLY_MS`를 유지한다. 변화구의 전체 이동 시간 `5 × CURVE_EARLY_MS + 3 × CURVE_LATE_MS`는 직구의 `8 × FAST_STEP_MS`보다 길게 설정한다.

## 보드 핀과 확인할 설정

표의 배열 순서는 포트 비트 0부터 증가한다. 핀은 첨부 핀맵과 대조한 값이다. Part, 핀에 인가되는 실제 클럭, I/O 뱅크 전압과 표준, 장치 극성 및 LCD 호환 방식은 보드에서 확인해야 한다.

| 포트 | 핀 배열 | 장치와 핀맵 쪽 |
|---|---|---|
| `clk_sys` | B6 | MAIN_CLOCK1, 2쪽 |
| `sw_0, sw_1, sw_2, sw_3, sw_star` | L1, K4, N8, N4, L7 | 스윙, 직구, 변화구, 볼, 리셋, 4쪽 |
| `led[7:0]` | L4, M4, M2, N7, M7, M3, M1, N5 | LED 1–8, 3쪽 |
| `seg_data[7:0]` | F1, F5, E2, E4, J1, J3, J7, H2 | AR_SEG_A–G, DP, 8쪽 |
| `seg_com[7:0]` | H4, H6, G1, G3, L6, K1, K3, K5 | AR_SEG_S0–S7, 8쪽 |
| `base_lights[2:0]` | A20, E11, C16 | E_GREEN 1루, N_GREEN 2루, W_GREEN 3루, 16쪽 |
| `piezo` | Y21 | Piezo, 10쪽 |
| `rgb_r[3:0]` | T2, U1, P2, R3 | CLED_R1–R4, 11쪽 |
| `rgb_g[3:0]` | U5, V1, R7, T6 | CLED_G1–G4, 11쪽 |
| `rgb_b[3:0]` | U3, W2, R5, T3 | CLED_B1–B4, 11쪽 |
| `lcd_data[7:0]` | A4, B2, C3, D4, A2, C5, C1, D1 | LCD_D0–D7, 13쪽 |
| `lcd_rs, lcd_rw, lcd_e` | G6, D6, A6 | LCD 제어, 13쪽 |

- 보드의 FPGA 마킹 또는 확실히 같은 보드의 동작한 프로젝트에서 정확한 **Part**와 I/O 전압을 확인한다. 보드 매뉴얼이나 계측으로 현재 스위치 설정의 **MAIN_CLOCK1 주파수**를 확인한다. (10^9/`clk_hz`) ns를 XDC 주기로 생성하고 같은 정수값을 RTL `CLK_HZ`에 전달한다.
- `io_default`에 검증한 기본 I/O 표준을 기록한다. 다른 표준이 필요한 포트는 `io_overrides`에 Tcl 사전으로 적는다. 키는 버스 이름 또는 중괄호로 감싼 비트 이름이다. 비트별 설정이 같은 버스의 설정에 우선한다.
- 버튼과 조명은 RTL 내부에서 1이 활성이다. 10진수 반전 마스크의 해당 비트를 1로 설정하면 보드 포트에서 뒤집힌다. `button_invert` 비트 0–4는 SW_0, SW_1, SW_2, SW_3, SW_*, `lcd_ctrl_invert` 비트 0–2는 E, RW, RS다. 다른 마스크는 포트 비트와 같은 순서다. 검증한 직접 극성은 명시적으로 0을 넣는다.
- 7세그먼트 논리 자리 0–3은 왼쪽 P1, 4–7은 오른쪽 P2다. 각각 `0000`–`0255`를 표시하고 DP는 항상 꺼진다. 물리 S0이 왼쪽이면 `seg_reverse=0`, S7이 왼쪽이면 1을 사용한다. `seg_com_invert`는 자리 선택, `seg_data_invert`는 A–G와 DP의 활성 극성을 조정한다.
- LCD가 HD44780 계열 16×2 병렬 8비트 쓰기 모드이며 전압 및 신호 연결이 맞는지 확인하고 `lcd_interface`에 `HD44780_8BIT_WRITE`를 입력한다. 버튼 패널은 **Button Switch** 모드로 설정한다.

### LCD 신호 확인

FPGA가 8비트 데이터를 출력하며 논리 RW=0을 유지한다. 첫 전송까지 50ms를 기다린 뒤 명령 `30 30 30 38 08 01 06 0C`(16진수)를 보낸다. 첫 두 초기화 간격은 5ms, 150µs다. 각 쓰기는 1µs 설정, 1µs E High, 50µs 대기이며 화면 지우기 뒤에는 2.5ms를 기다린다. 실제 클럭의 정수 사이클로 올림한다.

줄 주소 명령은 `80`, `C0`이며 각 명령 뒤에 RS=1로 왼쪽부터 ASCII 16바이트를 보낸다. 화면이 바뀔 때 두 줄을 함께 래치하고 오른쪽 공백까지 다시 쓴다. 보드에서는 `SW_*`를 놓은 뒤 로직 분석기나 오실로스코프로 RW와 E 유휴 상태, 초기 명령, 줄 주소 및 16바이트를 확인한다. 초기 정상 표시는 첫 줄 `P1 TOP B0 S0 O0`, 둘째 줄 `NO PITCH`다. 다른 컨트롤러나 인터페이스일 경우 `lcd_driver.v`의 초기화와 전송 방식을 장치 자료에 맞춘다. [Hitachi HD44780U 데이터시트](https://www.threefivedisplays.com/wp-content/uploads/datasheets/lcd_driver_datasheets/HD44780U_REV_0_0_DS.pdf)

## 합성, 비트스트림, Program Device

1. `constraints/board_config.tcl`에 50 MHz 시험 설정이 들어 있다. 보드에 올리기 전에 `MAIN_CLOCK1`을 50 MHz로 맞추고, 주자 표시등이 연결된 Bank 16이 3.3 V인지와 주자 표시등·RGB LED가 High에서 켜지는지 확인한다. 보드에서 확인한 값에 맞춰 설정을 조정한다.
2. `build/hardware/FPGA_BASEBALL_GAME.xpr`이 있으면 **File → Open Project**에서 연다. 처음 만들 때는 열린 프로젝트를 닫고 Tcl Console에 `set argv {hardware}`를 입력한 뒤 `source`로 `scripts/create_project.tcl`을 실행한다.
3. **Run Synthesis → Run Implementation → Open Implemented Design** 순으로 실행한다. **Report Timing Summary**에서 B6 입력 클럭과 setup/hold slack을 확인하고 **Report DRC**의 핀·뱅크·I/O 표준 오류를 해결한 후 **Generate Bitstream**을 실행한다. 보드 설정을 바꿀 때마다 설정 Tcl을 다시 적용하고 합성과 구현을 다시 실행한다.
4. USB/JTAG 연결 및 보드 전원을 확인하고 **Open Hardware Manager → Open Target → Auto Connect → Program Device**에서 해당 FPGA와 `baseball_top.bit`를 선택한다.

배치로 만들 때는 프로젝트 폴더에서 Vivado 명령 프롬프트를 열고 아래 명령을 실행한다. 기본 비트스트림 저장 경로는 `build/hardware/FPGA_BASEBALL_GAME.runs/impl_1/baseball_top.bit`이다.

```text
vivado -mode batch -source scripts/create_project.tcl -tclargs hardware
vivado -mode batch -source scripts/build_hardware.tcl
```

## 보드에서 한 경기 시연

1. `SW_*`를 눌렀다 뗀다. LCD에 P1 TOP과 B0/S0/O0이 표시되고 7세그먼트는 `0000 0000`, 주자 표시등은 모두 꺼진다.
2. `SW_1`을 한 번 누르고 준비음 뒤 **LED 6에서 `SW_0`**를 눌러 1루타를 낸다. 1루 녹색등만 켜진다. 버튼을 떼고 결과 표시 시간 약 0.95초를 보낸다.
3. 다시 `SW_1`을 누르고 **LED 7에서 스윙**해 2루타를 낸다. 2루와 3루 녹색등이 켜지고 점수는 0:0이다.
4. 다음 `SW_1) 투구의 **LED 8에서 스윙**해 홈런을 낸다. 두 주자와 타자가 들어와 3점, 녹색등 모두 꺼짐, 7세그먼트 `0003 0000`, 홈런음과 RGB 점멸이 나온다.
5. 결과 표시 이후 직구를 스윙 없이 세 번 지켜보면 삼진 1개다. 삼진 3개씩으로 초와 말을 마치면 `P1 WIN`과 최종 3:0이 유지된다. `SW_*`로 0:0의 1회초로 돌아간다.

버튼에는 약 20ms 디바운스가 있으므로 실기 스윙은 목표 LED가 켜진 뒤 여유 있게 누른다. 볼에 스윙하면 헛스윙이고, LED 8까지 지켜본 볼만 일반 볼 또는 HBP가 된다.

### 파형 캡처

| 구간 | Vivado Wave에 추가할 신호와 관찰점 |
|---|---|
| 준비음 → LED 1 | `sw_1`, `dut.pitch_req`, `dut.fx_evt`, `piezo`, `dut.pitch_ctrl`, `dut.pitch_bus`, `led`. PREP 효과 후 시작 에지에 LED 1 |
| LED 7→8 / LED 8→종료 | `clk_sys`, `dut.tick_ms`, `dut.pitch_bus`, `dut.swing_pulse`, `dut.result_valid`, `dut.result_code`. 1클럭 경계 비교는 `tb_one_pitch`를 확대 |
| 득점/공수 교대 | `dut.result_valid`, `dut.result_code`, `dut.runner_req`, `dut.runner_res`, `dut.scores`, `base_lights`, `dut.lcd_state`. 결과 래치에서 다음 에지까지와 각 반회의 세 번째 아웃 |
| 홈런·표시·리셋 | `dut.fx_evt`, `piezo`, `rgb_r/g/b`, `seg_com`, `seg_data`, `lcd_e/rs/rw/data`, `sw_star`, `dut.rst`. 홈런 적용 직후, 한 번의 8자리 순환, 리셋 후 LCD 초기화 |
