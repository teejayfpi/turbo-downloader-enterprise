/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'bg-primary': '#0a0a0f',
        'bg-secondary': '#12121a',
        'bg-tertiary': '#1a1a24',
        'border-subtle': '#2a2a3a',
        'text-primary': '#ffffff',
        'text-secondary': '#8b8b9e',
        'text-muted': '#5a5a6e',
        'accent': '#00d4ff',
        'accent-glow': 'rgba(0, 212, 255, 0.2)',
        'success': '#00ff88',
        'warning': '#ffaa00',
        'error': '#ff4466',
        'speed-ultra': '#00ffcc',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
      animation: {
        'pulse-glow': 'pulse-glow 2s ease-in-out infinite',
        'slide-up': 'slide-up 0.3s ease-out',
        'slide-down': 'slide-down 0.3s ease-out',
        'progress-stripe': 'progress-stripe 1s linear infinite',
      },
      keyframes: {
        'pulse-glow': {
          '0%, 100%': { opacity: '1', boxShadow: '0 0 20px rgba(0, 212, 255, 0.3)' },
          '50%': { opacity: '0.8', boxShadow: '0 0 40px rgba(0, 212, 255, 0.6)' },
        },
        'slide-up': {
          '0%': { transform: 'translateY(20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'slide-down': {
          '0%': { transform: 'translateY(-20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'progress-stripe': {
          '0%': { backgroundPosition: '1rem 0' },
          '100%': { backgroundPosition: '0 0' },
        },
      },
    },
  },
  plugins: [],
}
