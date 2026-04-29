#!/usr/bin/env python3
import sys
import re

def main():
    text = sys.stdin.read()
    
    # Extract summary
    matches = re.findall(r"Executed (\d+) tests, with (\d+) failures", text)
    if matches:
        sorted_matches = sorted(matches, key=lambda x: int(x[0]), reverse=True)
        total, failed = sorted_matches[0]
        passed = int(total) - int(failed)
        print(f"{passed} passed, {failed} failed")
    
    # Extract individual failures
    # /Users/.../ZoneTruthCoreTests.swift:78: error: -[ZoneTruthCoreTests.ZoneTruthCoreTests testStrengthAnalysis] : XCTAssertEqual failed...
    failures = re.findall(r"error: -\[(.*?)\]", text)
    for f in failures:
        # Format as FAILED <test_id>
        print(f"FAILED {f}")

if __name__ == "__main__":
    main()
