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
      background: '#FFFFFF',
      foreground: '#000000',
      cursor: '#FF0000',
      cursorAccent: '#FFFFFF',
      selectionBackground: '#FFD400',
      selectionForeground: '#000000',
      black: '#000000',
      red: '#D00000',
      green: '#006B00',
      yellow: '#8A5A00',
      blue: '#003BFF',
      magenta: '#8B00FF',
      cyan: '#005A6A',
      white: '#FFFFFF',
      brightBlack: '#303030',
      brightRed: '#FF0000',
      brightGreen: '#008A00',
      brightYellow: '#B87500',
      brightBlue: '#0000FF',
      brightMagenta: '#B000FF',
      brightCyan: '#007A90',
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
