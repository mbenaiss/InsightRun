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
          DEFAULT: '#FF8C42',
          50: '#FFF4ED',
          100: '#FFE8D6',
          200: '#FFCFAD',
          300: '#FFB084',
          400: '#FF9C5B',
          500: '#FF8C42',
          600: '#FF7419',
          700: '#E65F00',
          800: '#B84C00',
          900: '#8A3900',
        },
        navy: '#1a2942',
      },
    },
  },
  plugins: [],
}
export default config
