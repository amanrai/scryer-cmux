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
      foreground: '#06111F',
      cursor: '#005FCC',
      cursorAccent: '#FFFFFF',
      selectionBackground: '#B9D7FF',
      selectionForeground: '#06111F',
      black: '#06111F',
      red: '#8A1C1C',
      green: '#006B4F',
      yellow: '#7A5200',
      blue: '#005FCC',
      magenta: '#5F3DC4',
      cyan: '#006C8F',
      white: '#F7F9FC',
      brightBlack: '#4E647C',
      brightRed: '#9A1B1B',
      brightGreen: '#007A5A',
      brightYellow: '#8A6200',
      brightBlue: '#004EA8',
      brightMagenta: '#7048E8',
      brightCyan: '#007EA7',
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
