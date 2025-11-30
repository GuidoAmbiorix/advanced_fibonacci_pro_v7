/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Institutional Palette (Blue/White/Slate)
        primary: {
          DEFAULT: '#0f172a', // Slate 900 (Deep Blue)
          light: '#1e293b',   // Slate 800
        },
        accent: {
          DEFAULT: '#2563eb', // Blue 600 (Bright Blue)
          hover: '#1d4ed8',   // Blue 700
        },
        background: '#f8fafc', // Slate 50 (Light Gray/White)
        surface: '#ffffff',    // White
        
        // Semantic
        success: '#10b981', // Emerald 500
        danger: '#f43f5e',  // Rose 500
        warning: '#f59e0b', // Amber 500
        
        // Text
        'text-primary': '#1e293b', // Slate 800
        'text-secondary': '#64748b', // Slate 500
      },
      boxShadow: {
        'card': '0 4px 6px -1px rgba(0, 0, 0, 0.05), 0 2px 4px -1px rgba(0, 0, 0, 0.03)',
        'card-hover': '0 10px 15px -3px rgba(0, 0, 0, 0.05), 0 4px 6px -2px rgba(0, 0, 0, 0.025)',
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui'],
      }
    },
  },
  plugins: [],
}
