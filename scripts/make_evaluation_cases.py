"""生成固定的合成验收集；不读取用户剪贴板。"""

import hashlib
import json
import random
from pathlib import Path


def main():
    cases = []
    for language in ("en", "zh"):
        for index in range(30):
            group, variation = index % 10, index // 10
            number = 100 + variation
            bank = [
                f"maya.chen{number}@example.com",
                f"https://meet.example.com/project-{number}",
                f"{number} Maple Street, Bristol, BS1 4AA" if language == "en" else f"浙江省杭州市示例路{number}号2楼",
                "Maya Chen" if language == "en" else "陈小雨",
                f"INV-2026-{number}",
                f"def total_{number}(items):\n    return sum(items)\n",
                "Please review the attached draft.\nThank you for your time." if language == "en" else "请查收附件中的草稿。\n感谢审阅。",
                f"Support incident {number}: database connection timed out" if language == "en" else f"故障{number}：数据库连接超时",
            ]
            fields_en = ["Contact email address", "Online meeting link", "Shipping street address", "Full name", "Invoice reference", "Paste Python function", "Email closing message", "Error message to investigate", "Credit card expiry date", "Phone number"]
            fields_zh = ["联系人邮箱", "线上会议链接", "收货详细地址", "收件人姓名", "发票编号", "粘贴 Python 函数", "邮件结尾正文", "需要排查的报错原文", "信用卡有效期", "手机号码"]
            field = (fields_en if language == "en" else fields_zh)[group]
            # 独立随机种子固定候选顺序，答案不总处于同一位置。
            shuffled = list(enumerate(bank))
            random.Random(734 + index + (100 if language == "zh" else 0)).shuffle(shuffled)
            history = []
            expected = None
            for position, (original, text) in enumerate(shuffled):
                item_id = hashlib.sha256(f"{language}/{index}/{original}".encode()).hexdigest()[:16]
                history.append({"id": item_id, "text": text, "copied_at": 1_800_000_000 - position * 60})
                if original == group:
                    expected = item_id
            context = {
                "application": "Safari" if variation == 0 else "Google Chrome",
                "bundle_id": "com.apple.Safari" if variation == 0 else "com.google.Chrome",
                "window_title": "Synthetic acceptance form" if language == "en" else "合成验收表单",
                "field_label": field,
                "role": "AXTextArea" if group in (5, 6, 7) else "AXTextField",
                "selected_text": "",
                "nearby_text": "",
            }
            cases.append({"id": f"{language}-{index + 1:02}", "language": language, "category": group, "context": context, "history": history, "expected_id": expected})
    root = Path(__file__).resolve().parents[1]
    path = root / "evaluation/cases.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(cases, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(cases)} synthetic cases: {path}")


if __name__ == "__main__":
    main()
