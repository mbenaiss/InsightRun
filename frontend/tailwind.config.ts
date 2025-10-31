import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#0094FF',
          50: '#E5F4FF',
          100: '#CCE9FF',
          200: '#99D3FF',
          300: '#66BDFF',
          400: '#33A7FF',
          500: '#0094FF',
          600: '#0077CC',
          700: '#005A99',
          800: '#003D66',
          900: '#002033',
        },
        navy: '#1a2942',
      },
    },
  },
  plugins: [],
}
export default config
