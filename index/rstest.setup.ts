import { afterEach, expect } from '@rstest/core';
import * as jestDomMatchers from '@testing-library/jest-dom/matchers';
import { cleanup } from '@testing-library/react';

expect.extend(jestDomMatchers);

// happy-dom's WAAPI finished promise rejects on cancel; Motion uses cancel
// while unmounting viewport animations. Let Motion use its JS fallback here.
Object.defineProperty(Element.prototype, 'animate', { configurable: true, value: undefined });

afterEach(() => {
  cleanup();
  window.localStorage.clear();
});
