import js from "@eslint/js";
import { defineConfig } from "eslint/config";
import tseslint from "typescript-eslint";

export default defineConfig(
  {
    ignores: ["lib/**", "node_modules/**"],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["src/**/*.ts"],
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "max-len": ["error", { code: 100, ignoreUrls: true }],
      "object-curly-spacing": ["error", "always"],
      "quotes": ["error", "double"],
      "semi": ["error", "always"],
      "@typescript-eslint/consistent-type-imports": "error"
    },
  }
);
