import os
import xml.etree.ElementTree as ET

# if there's a junit xml or similar, we can parse it, but we don't have local test run output.
# The user provided CI logs:
# Test Suite 'XboxControllerMapperTests.xctest' failed at 2026-08-01 09:17:01.350.
# Executed 1979 tests, with 18 tests skipped and 4 failures (0 unexpected) in 264.258 (264.745) seconds
