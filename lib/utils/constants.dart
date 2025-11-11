const categoryIcons = [
  'veh_pickup_03',
  'veh_truck_02'
];

const colors = [
  'green', 'red'
];

const rotationFrames = 30;

String get traccarBaseUrl {
  const envValue = String.fromEnvironment('TRACCAR_BASE_URL');
  if (envValue.isNotEmpty) {
    return envValue;
  }
  return 'http://gps.frotaweb.com';
}
