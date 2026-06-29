log_lines = """
2026-06-29T09:35:06.7915320Z Test Suite 'XboxControllerMapperTests.xctest' failed at 2026-06-29 09:35:06.413.
2026-06-29T09:35:06.7921360Z 	 Executed 1785 tests, with 18 tests skipped and 1 failure (0 unexpected) in 226.876 (227.381) seconds
2026-06-29T09:35:06.7922880Z Test Suite 'All tests' failed at 2026-06-29 09:35:06.418.
2026-06-29T09:35:06.7924580Z 	 Executed 1785 tests, with 18 tests skipped and 1 failure (0 unexpected) in 226.876 (227.396) seconds
2026-06-29T09:35:06.7993580Z ⚠️ MappingEngine: Chord [ControllerKeys.ControllerButton.a, ControllerKeys.ControllerButton.b] detected but no active profile — input ignored
2026-06-29T09:35:06.7994660Z ⚠️ MappingEngine: Button a pressed but no active profile — input ignored
2026-06-29T09:35:06.7995180Z ⚠️ MappingEngine: Button a pressed but no active profile — input ignored
2026-06-29T09:35:06.8026810Z ##[error]Process completed with exit code 1.
"""
print(log_lines)
