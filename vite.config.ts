import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const commitSha =
  process.env.CF_PAGES_COMMIT_SHA ??
  process.env.GITHUB_SHA ??
  process.env.COMMIT_SHA ??
  'local'

export default defineConfig({
  plugins: [react()],
  define: {
    __APP_COMMIT__: JSON.stringify(commitSha),
  },
})
