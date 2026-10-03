/** @type {import('tailwindcss').Config} */
const withVar = (name) => `rgb(var(${name}) / <alpha-value>)`;

export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        'bg-primary': withVar('--bg-primary'),
        'bg-secondary': withVar('--bg-secondary'),
        'bg-tertiary': withVar('--bg-tertiary'),
        'border-subtle': withVar('--border-subtle'),
        'text-primary': withVar('--text-primary'),
        'text-secondary': withVar('--text-secondary'),
        'text-muted': withVar('--text-muted'),
        accent: withVar('--accent'),
        success: withVar('--success'),
        warning: withVar('--warning'),
        error: withVar('--error'),
        'speed-ultra': withVar('--speed-ultra'),
      },
      fontFamily: {
        sans: ['Sora', 'system-ui', 'sans-serif'],
        display: ['"Chakra Petch"', 'Sora', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      letterSpacing: {
        micro: '0.28em',
        wider: '0.12em',
      },
      animation: {
        'pulse-glow': 'pulse-glow 2s ease-in-out infinite',
        'slide-up': 'slide-up 0.28s cubic-bezier(0.16, 1, 0.3, 1)',
        'slide-down': 'slide-down 0.28s cubic-bezier(0.16, 1, 0.3, 1)',
        'fade-in': 'fade-in 0.3s ease-out',
        'rise': 'rise 0.5s cubic-bezier(0.16, 1, 0.3, 1) both',
        'scan': 'scan 7s linear infinite',
        'progress-stripe': 'progress-stripe 1s linear infinite',
        shimmer: 'shimmer 2.2s linear infinite',
      },
      keyframes: {
        'pulse-glow': {
          '0%, 100%': { opacity: '1', boxShadow: '0 0 18px rgb(var(--accent) / 0.35)' },
          '50%': { opacity: '0.85', boxShadow: '0 0 34px rgb(var(--accent) / 0.55)' },
        },
        'slide-up': {
          '0%': { transform: 'translateY(16px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'slide-down': {
          '0%': { transform: 'translateY(-16px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        rise: {
          '0%': { opacity: '0', transform: 'translateY(14px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        scan: {
          '0%': { transform: 'translateY(-100%)' },
          '100%': { transform: 'translateY(100%)' },
        },
        'progress-stripe': {
          '0%': { backgroundPosition: '1rem 0' },
          '100%': { backgroundPosition: '0 0' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-500px 0' },
          '100%': { backgroundPosition: '500px 0' },
        },
      },
    },
  },
  plugins: [],
};
