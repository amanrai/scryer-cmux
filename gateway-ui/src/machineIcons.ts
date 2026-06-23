export type MachineIconId =
  | 'os-macos'
  | 'os-linux'
  | 'os-windows'
  | 'device-mini'
  | 'device-laptop'
  | 'device-desktop'
  | 'device-server'
  | 'device-gpu'
  | 'device-cloud';

export type MachineIconOption = {
  id: MachineIconId;
  label: string;
  icon: string;
  group: 'OS' | 'Machine';
};

export const machineIconOptions: MachineIconOption[] = [
  { id: 'os-macos', label: 'macOS', icon: 'fa-brands fa-apple', group: 'OS' },
  { id: 'os-linux', label: 'Linux', icon: 'fa-brands fa-linux', group: 'OS' },
  { id: 'os-windows', label: 'Windows', icon: 'fa-brands fa-windows', group: 'OS' },
  { id: 'device-mini', label: 'Mini', icon: 'fa-solid fa-cube', group: 'Machine' },
  { id: 'device-laptop', label: 'Laptop', icon: 'fa-solid fa-laptop', group: 'Machine' },
  { id: 'device-desktop', label: 'Desktop', icon: 'fa-solid fa-desktop', group: 'Machine' },
  { id: 'device-server', label: 'Server', icon: 'fa-solid fa-server', group: 'Machine' },
  { id: 'device-gpu', label: 'GPU', icon: 'fa-solid fa-microchip', group: 'Machine' },
  { id: 'device-cloud', label: 'Cloud', icon: 'fa-solid fa-cloud', group: 'Machine' },
];

const validMachineIconIds = new Set(machineIconOptions.map((option) => option.id));

export function sanitizeMachineIconIds(value: unknown): MachineIconId[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const icons: MachineIconId[] = [];
  for (const item of value) {
    if (typeof item !== 'string' || !validMachineIconIds.has(item as MachineIconId) || seen.has(item)) continue;
    seen.add(item);
    icons.push(item as MachineIconId);
  }
  return icons;
}

export function machineIconClass(id: MachineIconId) {
  return machineIconOptions.find((option) => option.id === id)?.icon ?? 'fa-solid fa-circle';
}
