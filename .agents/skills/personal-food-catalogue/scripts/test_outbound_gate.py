#!/usr/bin/env python3
"""Synthetic tests for http_client.safe_query, the outbound privacy gate on every search query.

Usage: python3 -I test_outbound_gate.py <scripts_dir>
"""
import os
import sys

os.environ.pop("PFC_CONFIG", None)  # synthetic only: never the owner's private config
sys.path.insert(0, sys.argv[1])
import http_client as H  # noqa: E402

H.FOOD_WORDS = {"yogurt", "yoghurt", "bakewell", "milk", "apple", "crisp", "salted", "cherry"}  # synthetic vocabulary
H.CJK_FOOD_BIGRAMS = {"甲乙"}  # synthetic two-character fragment
H._BRAND_HONORIFICS = ("Mr Sample",)  # synthetic brand exception, as the private config would supply

ALLOW = ["A&B Greek Style Natural Yogurt", "Mr Sample Cherry Bakewells", "Example Farm Organic Whole Milk",
         "fuji apple", "甲乙", "Example Ready Salted Crisps"]
REFUSE = ["王小明", "Alice 张", "Alice Smith 5.00", "A&B Yogurt £1.50", "Mr Other Cherry Bakewells", "Delivery for Mrs Jones", "12 Example Abbey Road",
          "99 Example Lane", "contact a@b.com", "Order 1234567", "AB1 2CD", "", "x" * 200]
wrong = []
for t in ALLOW:
    try:
        H.safe_query(t)
    except ValueError:
        wrong.append(("refused", t))
for t in REFUSE:
    try:
        H.safe_query(t)
        wrong.append(("allowed", t))
    except ValueError:
        pass
total = len(ALLOW) + len(REFUSE)
print(f"outbound gate: {total - len(wrong)} of {total} cases correct")
if wrong:
    print("WRONG:", wrong)
    sys.exit(1)
