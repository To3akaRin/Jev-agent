"""第二版独立合成集：新场景、新内容，生成后固定，不用于调参。"""

import hashlib
import json
import random
from pathlib import Path

EN = [
    ("Send receipt to", "Work email", "riley.fox@example.org"),
    ("Open video call", "Video conference URL", "https://call.example.org/room/orchid"),
    ("Deliver this parcel", "Delivery address", "47 Birch Avenue, Bath, BA1 2AB"),
    ("Identify the attendee", "Attendee full name", "Riley Fox"),
    ("Resolve payment enquiry", "Order ID", "ORDER-48319"),
    ("Add executable sample", "Python source code", "def greet(name):\n    return f'Hello, {name}'\n"),
    ("Contact the supplier", "Telephone number", "+44 20 7946 0843"),
    ("Describe the failure", "Exact error text", "ConnectionError: the search service refused the connection"),
    ("Share written next steps", "Follow-up note", "Please confirm the delivery date.\nWe will review the draft on Thursday."),
    ("Locate the profile", "Profile page URL", "https://people.example.org/riley"),
    ("Register a package", "Tracking code", "TRACK-918402"),
    ("Provide a database query", "SQL statement", "SELECT name FROM products WHERE active = 1;"),
    ("Send sample coordinates", "Latitude and longitude", "51.5074, -0.1278"),
    ("Pick a theme", "Hex color value", "#3A7B65"),
    ("Schedule a reminder", "Calendar date", "2026-11-04"),
    ("Card details", "Card expiry month and year", None),
    ("Book accommodation", "Passport number", None),
    ("Invite a teammate", "Mobile telephone", None),
    ("Set a meeting time", "Start time in HH:MM", None),
    ("Look up a book", "ISBN", None),
]
ZH = [
    ("发送电子回执", "接收回执的邮箱", "lin.yue@example.org"),
    ("进入线上讨论", "视频会议网址", "https://call.example.org/room/bamboo"),
    ("填写快递信息", "详细收货地址", "江苏省苏州市示例街47号3室"),
    ("登记活动人员", "参与者姓名", "林悦"),
    ("查找采购记录", "订单编号", "ORDER-57281"),
    ("提交代码示例", "Python源代码", "def square(value):\n    return value * value\n"),
    ("联系客户", "联系电话", "+86 010 5550 0198"),
    ("排查程序故障", "完整错误信息", "连接失败：搜索服务拒绝连接，请检查服务状态。"),
    ("发送后续安排", "后续说明正文", "请确认预计送达日期。\n我们将在周四评审草稿。"),
    ("查找个人页面", "个人主页链接", "https://people.example.org/linyue"),
    ("跟踪包裹", "物流运单号", "TRACK-719305"),
    ("执行查询", "SQL查询语句", "SELECT title FROM articles WHERE published = 1;"),
    ("登记位置", "经纬度", "31.2304, 121.4737"),
    ("设置主题", "十六进制颜色值", "#5B6F8A"),
    ("登记事项", "日历日期", "2026-12-08"),
    ("填写银行卡", "银行卡到期年月", None),
    ("填写住宿信息", "护照号码", None),
    ("邀请同事", "手机号码", None),
    ("安排会议", "开始时刻，小时和分钟", None),
    ("查找图书", "ISBN编号", None),
]


def main():
    records = []
    for lang, rows in (("en", EN), ("zh", ZH)):
        for index, (window, label, expected_text) in enumerate(rows):
            other = [row[2] for row in rows if row[2] is not None and row[2] != expected_text]
            # 无匹配用例避免把其他格式的号码误作手机号候选。
            if expected_text is None:
                other = [v for v in other if not v.startswith(("+", "2026-", "51.", "31."))]
            rng = random.Random(2048 + index + (400 if lang == "zh" else 0))
            texts = rng.sample(other, 7 if expected_text else 8)
            if expected_text:
                texts.append(expected_text)
            rng.shuffle(texts)
            history = [{"id": hashlib.sha256(f"v2/{lang}/{index}/{n}".encode()).hexdigest()[:16],
                        "text": value, "copied_at": 1_800_100_000 - n * 79} for n, value in enumerate(texts)]
            expected = next((item["id"] for item in history if item["text"] == expected_text), None)
            records.append({"id": f"v2-{lang}-{index+1:02}", "language": lang,
                            "context": {"application": "Google Chrome", "bundle_id": "com.google.Chrome",
                                        "window_title": window, "field_label": label, "role": "AXTextField",
                                        "nearby_text": "", "selected_text": ""},
                            "history": history, "expected_id": expected})
    root = Path(__file__).resolve().parents[1]
    target = root / "evaluation/cases_v2.json"
    target.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(records)} new held-out synthetic cases")


if __name__ == "__main__":
    main()
