export const DISTANCE_TO_CENTER = 255;
export const TURNTABLE_DIAMETER = 152.4;
export const MAX_HORIZONTAL_STEPS = 200;
export const MAX_VERTICAL_STEPS = 35;
export const VERTICAL_STEP_SIZE_MM = 0.025;

export type Point = { distance: number; horizontal: number; vertical: number };

export type Status =
  | "Offline"
  | "Initializing"
  | "Ready"
  | "Scanning"
  | "Paused"
  | "Done"
  | "Restarting";
