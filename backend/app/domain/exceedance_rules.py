"""超标判定规则: 依据污染物限值计算超标倍数并分级."""
from .standards import get_limit, get_pollutant

# 超标倍数 -> 等级
LEVEL_THRESHOLDS = ((2.0, "severe"), (1.5, "moderate"), (1.0, "light"))

LEVEL_ORDER = {"light": 1, "moderate": 2, "severe": 3}


def grade_ratio(ratio):
    """Map an exceedance ratio (value / limit) to a level code."""
    for threshold, level in LEVEL_THRESHOLDS:
        if ratio >= threshold:
            return level
    return "light"


def evaluate(pollutant_code, period, value):
    """Evaluate a single reading.

    Returns a dict: {"applicable", "exceeded", "limit", "ratio", "level", "unit", "message"}.
    ``applicable`` is False when the standard defines no limit for this period
    (e.g. PM2.5 has no 1-hour limit), in which case ``exceeded`` stays False.
    """
    pollutant = get_pollutant(pollutant_code)
    if pollutant is None:
        raise ValueError("未知监测因子: %s" % pollutant_code)
    if period not in ("hourly", "daily"):
        raise ValueError("未知数据周期: %s" % period)
    if value is None:
        raise ValueError("监测数值不能为空")

    limit = get_limit(pollutant_code, period)
    if limit is None:
        return {
            "applicable": False,
            "exceeded": False,
            "limit": None,
            "ratio": None,
            "level": None,
            "unit": pollutant["unit"],
            "message": "%s 未设定小时均值限值, 仅记录数值" % pollutant["label"],
        }

    ratio = round(float(value) / float(limit), 3)
    exceeded = float(value) > float(limit)
    return {
        "applicable": True,
        "exceeded": exceeded,
        "limit": limit,
        "ratio": ratio if exceeded else ratio,
        "level": grade_ratio(ratio) if exceeded else None,
        "unit": pollutant["unit"],
        "message": None,
    }


def summarize(results):
    """Aggregate evaluation results for the batch entry form."""
    exceeded = [item for item in results if item["exceeded"]]
    return {
        "total": len(results),
        "exceeded_count": len(exceeded),
        "exceeded_pollutants": [item["pollutant"] for item in exceeded],
    }
