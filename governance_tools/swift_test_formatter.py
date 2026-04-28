#!/usr/bin/env python3
import sys
import re
import json

def main():
    text = sys.stdin.read()
    # Executed 38 tests, with 0 failures
    match = re.search(r"Executed (\d+) tests, with (\d+) failures", text)
    if match:
        passed = int(match.group(1)) - int(match.group(2))
        failed = int(match.group(2))
        print(f"{passed} passed, {failed} failed")
    else:
        print("0 passed, 0 failed")

if __name__ == "__main__":
    main()
