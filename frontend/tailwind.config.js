/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        background: '#0a0a0a',
        surface: '#171717',
        primary: '#10b981',
        secondary: '#3b82f6',
        accent: '#fbbf24',
        danger: '#ef4444',
      },
    },
  },
  plugins: [],
}
