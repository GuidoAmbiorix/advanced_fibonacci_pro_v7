/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Liquid Glass Palette
        'glass-surface': 'rgba(255, 255, 255, 0.03)',
        'glass-border': 'rgba(255, 255, 255, 0.08)',
        'glass-highlight': 'rgba(255, 255, 255, 0.15)',

        // Neon Accents
        'neon-blue': '#00f3ff',
        'neon-purple': '#bc13fe',
        'neon-green': '#0aff0a',

        // Semantic
        'chart-green': '#0aff0a',
        'chart-red': '#ff0a5c',
        'chart-blue': '#00f3ff',
      },
      animation: {
        'pulse-slow': 'pulse 4s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'float': 'float 6s ease-in-out infinite',
        'glow': 'glow 2s ease-in-out infinite alternate',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
        glow: {
          'from': { boxShadow: '0 0 10px -5px rgba(0, 243, 255, 0.5)' },
          'to': { boxShadow: '0 0 20px 5px rgba(0, 243, 255, 0.7)' },
        }
      }
    },
  },
  plugins: [],
}
