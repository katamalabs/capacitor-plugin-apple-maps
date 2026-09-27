import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // The plugin's own unit tests only. Keeps vitest from wandering into
    // example-app or dist.
    include: ['src/**/*.test.ts'],
    environment: 'node',
  },
});
