sed -i.bak 's/tail -200/grep -E -A 5 -B 5 "XCTFail|failed|Failed|error:|Error:"/' .github/workflows/test.yml
