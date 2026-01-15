# Xbox Controller Mapper - Refactoring Plan

**Date:** January 14, 2026
**Status:** Planning Phase
**Baseline Tests:** 12 passing, 2 failing

## Executive Summary

This document outlines a comprehensive refactoring of the Xbox Controller Mapper codebase to improve code quality, maintainability, and performance while preserving all existing functionality.

## Current State Analysis

### Strengths
- Well-structured service layer with clear separation of concerns
- Comprehensive test coverage (14 unit tests)
- Proper use of protocols and dependency injection
- Thread-safe state management with NSLock
- Good use of modern Swift features (@MainActor, Combine, async/await)
- Dedicated dispatch queues for different types of operations

### Areas for Improvement

#### 1. **InputSimulator.swift** (~600 lines)
- **Issue:** Significant code duplication in modifier handling
  - `holdModifier()` and `releaseModifier()` both iterate over same mask list
  - `vKeys` dictionary duplicated in multiple functions
  - Lock acquire/release patterns repeated throughout
- **Opportunity:** Extract modifier handling to dedicated helper class
- **Expected impact:** ~100 lines of code reduction, improved maintainability
- **Risk:** Low - protocol-based, fully tested

#### 2. **MappingEngine.swift** (~740 lines)
- **Issue:** Monolithic method implementations, complex logic branches
  - `handleButtonPressed()` is 60+ lines with multiple branches
  - `handleButtonReleased()` is 70+ lines with nested conditions
  - Joystick logic intertwined with button handling
- **Opportunity:**
  - Extract button handling into discrete methods (press/release/chord patterns)
  - Create JoystickHandler class for joystick-specific logic
  - Extract common state checking into helper methods
- **Expected impact:** ~150 lines reduction, improved testability
- **Risk:** Medium - core input logic, needs thorough testing

#### 3. **ControllerService.swift** (~600 lines)
- **Issue:** State management could be more elegant
  - Callback properties with inline getter/setter accessing storage.lock 3x each
  - Thread-safe accessors for individual joystick properties
  - Display update timer creates redundancy in value copying
- **Opportunity:**
  - Create ThreadSafeState wrapper for atomic operations
  - Consolidate callback management
  - Simplify display update logic
- **Expected impact:** ~80 lines reduction, better API clarity
- **Risk:** Medium-High - critical for input delivery

#### 4. **View Files** (Multiple files, ~400 lines)
- **Issue:** Some views are dense and could be more modular
  - ControllerVisualView likely has many small geometry calculations
  - ButtonMappingSheet has complex state management scattered
- **Opportunity:** Extract reusable view components
- **Expected impact:** Improved readability, easier maintenance
- **Risk:** Low - UI-only changes, no logic impact

#### 5. **Code Quality Issues**
- **Print statements in code:** Several `#if DEBUG` print statements should be standardized
- **Magic numbers:** Various timeout/threshold values hard-coded (should be constants)
- **Comments:** Some complex logic lacks explanation
- **Error handling:** Limited error context in some areas

#### 6. **Performance Opportunities**
- **Lock contention:** Some hot paths acquire locks multiple times in sequence
- **Cache efficiency:** Screen bounds cached but could use more aggressive strategies
- **Modifier state tracking:** Reference counting is good but could be optimized

## Refactoring Steps

### Phase 1: Foundation (Non-Breaking Changes)
1. **Extract Common Patterns**
   - Create `ModifierKeyHandler` helper class
   - Create `ThreadSafeStorage<T>` generic wrapper
   - Extract magic constants to named constants

2. **Optimize ControllerService**
   - Consolidate callback management
   - Improve thread-safe accessor pattern
   - Simplify display update logic

### Phase 2: Core Logic (Most Impact)
3. **Refactor MappingEngine**
   - Create ButtonPressMatcher class
   - Extract ChordResolver class
   - Extract JoystickHandler class
   - Break down large methods

4. **Improve InputSimulator**
   - Create ModifierManager class
   - Reduce code duplication
   - Improve error handling and logging

### Phase 3: Polish (Code Quality)
5. **Documentation & Comments**
   - Add comprehensive inline documentation
   - Document complex algorithms
   - Add examples for protocol implementations

6. **UI Refactoring**
   - Extract view components
   - Improve state management
   - Add view composition helpers

### Phase 4: Validation & Testing
7. **Testing**
   - Fix failing unit tests
   - Add new tests for refactored code
   - Performance benchmarking
   - Feature validation

## Expected Outcomes

| Metric | Before | After | Impact |
|--------|--------|-------|--------|
| Total LOC | ~3,800 | ~3,400 | -11% |
| InputSimulator LOC | 600 | 480 | -20% |
| MappingEngine LOC | 740 | 620 | -16% |
| ControllerService LOC | 600 | 540 | -10% |
| Code Duplication | High | Low | Improved maintainability |
| Test Coverage | 88% | 92%+ | Better coverage |

## Risk Mitigation

1. **Feature Regression:** Run full test suite after each phase
2. **Performance:** Profile before/after with real controller input
3. **Breaking Changes:** Use protocols and dependency injection throughout
4. **Testing:** 14 existing tests + new tests for refactored code

## Implementation Order

1. Extract constants and helpers (safest, easiest)
2. Refactor ControllerService (lower risk, clear benefits)
3. Refactor InputSimulator (focused, testable)
4. Refactor MappingEngine (highest complexity, highest impact)
5. Polish and optimize (final pass)
6. Comprehensive testing and validation

## Success Criteria

- All 14 existing tests pass (plus 2 pre-existing failures fixed)
- No feature regression
- 10%+ code reduction achieved
- All code documented
- Performance maintained or improved
- Codebase maintainability significantly improved

---

**Next Step:** Begin Phase 1 - Extract common patterns and optimize ControllerService
