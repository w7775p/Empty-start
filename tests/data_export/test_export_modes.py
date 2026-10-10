"""TEST_ONLY 导表端到端回归：可重复、保留正式数据、失败原子性、禁止误用模式。"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools/export_game_data.py"
FIXTURE = ROOT / "tests/fixtures/data_export/test_only_data.xlsx"


def execute(path: Path, *flags: str) -> subprocess.CompletedProcess:
    """运行真实入口，并锁定 UTF-8 控制台输出，避免 Windows 本地代码页乱码。"""
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    return subprocess.run(
        [sys.executable, str(TOOL), "--input", str(path), *flags],
        cwd=ROOT, capture_output=True, encoding="utf-8", env=env,
        check=False,
    )


def files_snapshot(paths: list[Path]) -> dict[Path, tuple[bytes, int]]:
    """用文件字节和 mtime 判定重复导表是否真正稳定。"""
    return {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in paths}


def main() -> None:
    # 测试模式不能覆盖策划原始 CSV 或已确认 Tier Resource。
    authoritative_paths = sorted((ROOT / "data/source_tables").glob("*.csv"))
    for name in ("01_身份配置.csv", "06_战斗数值.csv", "08_Tier档位.csv"):
        assert ROOT / "data/source_tables" / name in authoritative_paths, f"缺少已确认来源：{name}"
    authoritative_paths.append(ROOT / "data/combat_stage/tier_catalog.tres")
    authoritative = files_snapshot(authoritative_paths)
    success = execute(FIXTURE, "--test-only")
    assert success.returncode == 0, (success.stdout, success.stderr)
    test_outputs = sorted((ROOT / "data/test_only/source_tables").glob("*.csv"))
    test_outputs += sorted((ROOT / "data/test_only/generated").rglob("*.tres"))
    assert len(test_outputs) == 20, len(test_outputs)
    state = files_snapshot(test_outputs)
    success = execute(FIXTURE, "--test-only")
    assert success.returncode == 0, (success.stdout, success.stderr)
    assert state == files_snapshot(test_outputs)
    assert authoritative == files_snapshot(authoritative_paths)
    print("PASS TEST_ONLY repeatable output: 15 CSV + 5 Resource; source unchanged")

    with tempfile.TemporaryDirectory() as temp:
        # A3 原有 test_word_01，复制到第二条数据制造重复 ID。
        wb = load_workbook(FIXTURE)
        wb["03_普通词库"]["A4"] = "test_word_01"
        duplicate = Path(temp) / "duplicate.xlsx"
        wb.save(duplicate)
        result = execute(duplicate, "--test-only")
        assert result.returncode == 1 and "稳定 ID 重复" in result.stderr
        assert state == files_snapshot(test_outputs), "错误时覆盖了旧版测试资产"
        print("PASS duplicate ID rejected without replacing existing assets")

        # 词库引用有双方来源，拼错关卡的 pool_id 必须失败并保留旧产物。
        wb = load_workbook(FIXTURE)
        sheet = wb["02_主播关卡"]
        header = next(row for row in sheet.iter_rows() if any(cell.value == "word_pool_id" for cell in row))
        column = next(cell.column for cell in header if cell.value == "word_pool_id")
        sheet.cell(header[0].row + 1, column, "test_missing_pool")
        dangling = Path(temp) / "dangling_pool.xlsx"
        wb.save(dangling)
        result = execute(dangling, "--test-only")
        assert result.returncode == 1 and "关联 ID" in result.stderr, (result.stdout, result.stderr)
        assert state == files_snapshot(test_outputs), "跨表错误覆盖了旧版测试资产"
        assert authoritative == files_snapshot(authoritative_paths), "失败导出改变了正式来源"
        print("PASS missing cross-table pool rejected without replacing assets")

        wb = load_workbook(FIXTURE)
        wb["00_填写说明"]["A1"] = "普通数据表"
        non_test = Path(temp) / "non_test.xlsx"
        wb.save(non_test)
        result = execute(non_test, "--test-only")
        assert result.returncode == 2 and "--test-only" in result.stderr
        print("PASS prevents official/unmarked workbook entering TEST_ONLY mode")

if __name__ == "__main__":
    main()
