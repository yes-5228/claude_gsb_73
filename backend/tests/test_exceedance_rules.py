"""超标判定规则的单元测试."""
import pytest

from app.domain import exceedance_rules


def test_value_below_limit_is_not_exceeded():
    result = exceedance_rules.evaluate("PM25", "daily", 60.0)
    assert result["applicable"] is True
    assert result["exceeded"] is False
    assert result["limit"] == 75.0
    assert result["level"] is None


def test_light_moderate_and_severe_grading():
    assert exceedance_rules.evaluate("PM25", "daily", 80.0)["level"] == "light"
    assert exceedance_rules.evaluate("PM25", "daily", 120.0)["level"] == "moderate"
    assert exceedance_rules.evaluate("PM25", "daily", 200.0)["level"] == "severe"


def test_ratio_is_computed_against_limit():
    result = exceedance_rules.evaluate("NO2", "hourly", 250.0)
    assert result["exceeded"] is True
    assert result["limit"] == 200.0
    assert result["ratio"] == 1.25
    assert result["level"] == "light"


def test_period_without_limit_is_recorded_but_not_flagged():
    result = exceedance_rules.evaluate("PM10", "hourly", 400.0)
    assert result["applicable"] is False
    assert result["exceeded"] is False
    assert result["limit"] is None
    assert "未设定小时均值限值" in result["message"]


def test_unknown_pollutant_raises():
    with pytest.raises(ValueError):
        exceedance_rules.evaluate("XX", "daily", 1.0)


def test_summarize_counts_exceeded_items():
    results = [
        exceedance_rules.evaluate("PM25", "daily", 10.0),
        exceedance_rules.evaluate("PM25", "daily", 90.0),
    ]
    for item, code in zip(results, ("PM25", "PM25")):
        item["pollutant"] = code
    summary = exceedance_rules.summarize(results)
    assert summary["total"] == 2
    assert summary["exceeded_count"] == 1
