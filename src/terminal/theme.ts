function hexToRgba(hex: string, alpha: number) {
  const value = hex.replace('#', '');
  const r = parseInt(value.slice(0, 2), 16);
  const g = parseInt(value.slice(2, 4), 16);
  const b = parseInt(value.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export type SmuxThemeName = 'dark' | 'sunlight';

export function terminalTheme(accentColor: string, theme: SmuxThemeName = 'dark') {
  if (theme === 'sunlight') {
    return {
      background: '#EDF0F4',
      foreground: '#05111E',
      cursor: '#005FCC',
      cursorAccent: '#FFFFFF',
      selectionBackground: '#B0CCFF',
      selectionForeground: '#05111E',
      black: '#05111E',
      red: '#B5000B',
      green: '#0A6E2E',
      yellow: '#8F5200',
      blue: '#003FA8',
      magenta: '#6B00A8',
      cyan: '#006875',
      white: '#BDC7D4',
      brightBlack: '#4A6278',
      brightRed: '#CC000E',
      brightGreen: '#0E7F35',
      brightYellow: '#A06000',
      brightBlue: '#0050C8',
      brightMagenta: '#7A00BE',
      brightCyan: '#007A8A',
      brightWhite: '#FFFFFF',
    };
  }

  return {
    background: '#15171C',
    foreground: '#E6E8EC',
    cursor: accentColor,
    cursorAccent: '#15171C',
    selectionBackground: hexToRgba(accentColor, 0.28),
    black: '#15171C',
    red: '#E0697A',
    green: '#6FCB7F',
    yellow: '#E8B65A',
    blue: '#5AA6F0',
    magenta: '#B47BE8',
    cyan: '#4FC9D4',
    white: '#AEB4C0',
    brightBlack: '#4A515E',
    brightRed: '#E0697A',
    brightGreen: '#6FCB7F',
    brightYellow: '#E8B65A',
    brightBlue: '#5AA6F0',
    brightMagenta: '#B47BE8',
    brightCyan: '#4FC9D4',
    brightWhite: '#E6E8EC',
  };
}
