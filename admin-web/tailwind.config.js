/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        beeware: {
          yellow: '#FFCC00',
          yellowLight: '#FFFDE7',
          yellowDark: '#E5B800',
          amber: '#F5A623',
          dark: '#1A1D20',
          card: '#FFFFFF',
          border: '#E2E8F0',
          grayBg: '#F8FAFC',
          green: '#2E7D32',
          red: '#D32F2F',
          orange: '#ED6C02',
          blue: '#0288D1'
        }
      }
    },
  },
  plugins: [],
}
