import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  base: './',
  plugins: [vue()],
  server: { port: 5175 },
  build: { outDir: '../ui', emptyOutDir: true, sourcemap: false },
})
