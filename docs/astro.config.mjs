import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://dwm.christitus.com",
  output: "static",
  build: {
    format: "file"
  },
  markdown: {
    shikiConfig: {
      theme: "github-dark-default",
      wrap: true
    }
  }
});
