class BusStopNode {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final bool isTrafficLightNearby;

  const BusStopNode({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.isTrafficLightNearby = false,
  });
}

const List<BusStopNode> kTrabzonBusStops = [
  BusStopNode(id: 'TRB-KTU-01', name: 'KTÜ AKM Ring Durağı', lat: 40.994210, lon: 39.771540),
  BusStopNode(id: 'TRB-KTU-02', name: 'KTÜ Mühendislik / Milli Teknoloji Atölyesi', lat: 40.991850, lon: 39.775120),
  BusStopNode(id: 'TRB-KTU-03', name: 'KTÜ A Kapısı Ana Durak', lat: 40.998120, lon: 39.768400, isTrafficLightNearby: true),
  BusStopNode(id: 'TRB-KTU-04', name: 'KTÜ C Kapısı / Tıp Fakültesi Durağı', lat: 40.993400, lon: 39.781200),
  BusStopNode(id: 'TRB-ORT-05', name: 'Kalkınma Mahallesi Durağı', lat: 40.996500, lon: 39.765200),
  BusStopNode(id: 'TRB-ORT-06', name: 'Forum AVM / Değirmendere Durağı', lat: 40.999800, lon: 39.759100, isTrafficLightNearby: true),
  BusStopNode(id: 'TRB-ORT-07', name: 'Trabzon Meydan Parkı Ana Peron', lat: 41.005300, lon: 39.726800, isTrafficLightNearby: true),
  BusStopNode(id: 'TRB-ORT-08', name: 'Ayasofya / Beşirli Sahil Durağı', lat: 41.003100, lon: 39.698400),
  BusStopNode(id: 'TRB-OF-09',  name: 'KTÜ Of Teknoloji Fakültesi Durağı', lat: 40.946200, lon: 40.268900),
];
