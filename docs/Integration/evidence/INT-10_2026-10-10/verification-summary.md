# INT-10 runtime evidence (2026-10-10/11)

Engine: Godot 4.7.2.stable.steam.ed1daf0bf. Runtime renderer: D3D12 12_0 / Forward+ / AMD Radeon(TM) Graphics. All commands used this clone as `--path`; SaveManager and SettingsManager paths were temporarily redirected to `.godot/int10`, and the MCP runtime plugin/autoload were disabled for the process. These three tracked files were restored after each run.

- Warm import: `--headless --editor --import --quit`; exit 0, stderr empty. Cold import was run in the clone and completed file reimport, but the wrapper did not retain its process exit status; its diagnostic logs are retained separately. It logged audio resource-load errors before reimport and locale-column warnings. All referenced audio source files exist, and later runtime logs were clean.
- Direct production scene capture: `res://scenes/sandbox/sandbox.tscn`, D3D12 / Forward+, `--write-movie ... --quit-after 3`; exit 0, 3 frames. `sandbox_direct.png` is the rendered 1920×1080 Sandbox frame.
- INT-01: real Sandbox/InputEvent lifecycle, 87 checks; exit 0, stderr empty. Covers the actual portrait binding and current streamer-id preset hook as well as attack, repeat, Tier, failure/restart, contradiction and oracle paths.
- Production-flow handoff probe: two real ten-second unbroken contradiction routes, Rest results, both Continue requests, second attempt, DivineDescentFlow completion and `SceneRouter` replacement with EndingPage; exit 0, stderr empty. The current formal `level_002.tres` contains identity fields only. For this route probe only, the harness duplicated the runnable `level_001` profile in memory as a second sample; it did not alter formal resources or claim formal level-two content acceptance. Ending screenshot: `ending_page.png`.
- INT-04 TEST_ONLY suite was not run or used as evidence.

## Final focused check (2026-10-11)

After syncing this branch to `origin/main` at `b676452`, Windows Godot 4.7.2 headless ran `res://tests/integration/int_01_playable_battle_sandbox_test.tscn`: **88 checks passed, process exit 0, stderr empty**. The test verifies the current CS-19 rule that T0 PK stays stable and that T1 enables pullback; it also covers the INT-10 portrait binding and shot-motion event. Raw output is in `int01_final.stdout.txt` and `int01_final.stderr.txt`.

INT-04 remains unrun by instruction. The stored production-flow output remains prior evidence; this turn did not rerun the two-Rest/Continue/Divine/Ending flow. The earlier route probe used an in-memory duplicate of `level_001` as its second sample and is not formal four-level data acceptance.
