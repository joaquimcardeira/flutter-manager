const categoryIcons = [
  'truck'
];

const colors = [
  'green', 'red'
];

const rotationFrames = 16;

String get traccarBaseUrl {
  const envValue = String.fromEnvironment('TRACCAR_BASE_URL');
  if (envValue.isNotEmpty) { return envValue; }
  return 'https://dash.frotaweb.com';
}

const String sourceId = 'devices-source';
const double selectedZoomLevel=16;
