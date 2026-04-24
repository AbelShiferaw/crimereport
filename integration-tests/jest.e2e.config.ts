import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.e2e.test.ts'],
  testTimeout: 300_000,
  clearMocks: true,
};

export default config;
