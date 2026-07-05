from pathlib import Path

TEST_ASSETS_ROOT = Path(__file__).resolve().parents[1] / "test"


def test_asset(*parts: str) -> Path:
    return TEST_ASSETS_ROOT.joinpath(*parts)