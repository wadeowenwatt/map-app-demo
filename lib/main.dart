import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:routing_client_dart/routing_client_dart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_map Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8dea88),
      ),
      home: const MyHomePage(
        title: 'Counting',
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final CameraPosition _initialLocation =
      const CameraPosition(target: LatLng(21.028511, 105.804817));

  /// controller in MAP
  GoogleMapController? mapController;

  Position? _currentPosition;
  String? _currentAddress;

  LatLng? _firstPosition;
  String? _firstAddress;

  LatLng? _secondPosition;
  String? _secondAddress;

  final firstAddressTextController = TextEditingController();
  final secondAddressTextController = TextEditingController();

  String _placeDistance = "";

  Set<Marker> markers = {};

  PolylinePoints? polylinePoints;
  Map<PolylineId, Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Method for retrieving the current location
  void _getCurrentLocation() async {
    bool serviceEnabled = false;

    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      print("😡 Location services are disabled!");
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print("😡 Location permissions are disabled!");
      }
    }

    await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation)
        .then((Position position) async {
      setState(() {
        _currentPosition = position;
        print('CURRENT POS: $_currentPosition');
        mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 18.0,
            ),
          ),
        );
      });
      setState(() async {
        _currentAddress = await _getAddressOfMarker(_currentPosition!);
      });
    }).catchError((e) {
      print(e);
    });
  }

  void _setCurrentAddressIsFirst() {
    // _getCurrentLocation();
    firstAddressTextController.text = _currentAddress ?? "";
    _firstAddress = _currentAddress ?? "";
    LatLng curPos =
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    _firstPosition = curPos;
    markers.clear();
    clearRoutePolyline();
    setState(() {
      markers.add(Marker(
        markerId: MarkerId(curPos.toString()),
        position: curPos,
      ));
    });
  }

  Future<String> _getAddressOfMarker(Position? pos,
      [double? lat, double? lon]) async {
    try {
      List<Placemark> pms = await placemarkFromCoordinates(
          pos?.latitude ?? (lat ?? 0), pos?.longitude ?? (lon ?? 0));
      Placemark place = pms[1];
      String result =
          "${place.street}, ${place.subAdministrativeArea}, ${place.administrativeArea}, ${place.country}";
      return result;
    } catch (e) {
      print(e);
      return "";
    }
  }

  void _addMarker(LatLng position) async {
    clearRoutePolyline();
    if (markers.isEmpty) {
      _firstPosition = position;
      _firstAddress = await _getAddressOfMarker(
        null,
        position.latitude,
        position.longitude,
      );
      firstAddressTextController.text = _firstAddress ?? "";
    } else if (markers.length == 1) {
      _secondPosition = position;
      _secondAddress = await _getAddressOfMarker(
        null,
        position.latitude,
        position.longitude,
      );
      secondAddressTextController.text = _secondAddress ?? "";
    } else if (markers.length == 2) {
      markers.remove(markers.first);
      _firstAddress = _secondAddress;
      _firstPosition = _secondPosition;
      _secondAddress = await _getAddressOfMarker(
        null,
        position.latitude,
        position.longitude,
      );
      _secondPosition = position;
      firstAddressTextController.text = _firstAddress ?? "";
      secondAddressTextController.text = _secondAddress ?? "";
    }
    setState(() {
      markers.add(Marker(
        markerId: MarkerId(position.toString()),
        position: position,
      ));
    });
    print(">>>>>>>> ${position.latitude} + ${position.longitude}");
  }

  void clearRoutePolyline() {
    setState(() {
      if (polylines.isNotEmpty) {
        polylines.clear();
      }
      if (polylineCoordinates.isNotEmpty) {
        polylineCoordinates.clear();
      }
      _placeDistance = "";
    });
  }

  // Method for calculating the distance between two places
  Future<bool> _calculateDistance() async {
    try {
      /// Make bounding map when two positions have been hide
      // LatLng? southwestCoordinates;
      // LatLng? northeastCoordinates;
      // if (_firstPosition != null && _secondPosition != null) {
      //   if (_firstPosition!.latitude <= _secondPosition!.latitude) {
      //     southwestCoordinates = _firstPosition;
      //     northeastCoordinates = _secondPosition;
      //   } else {
      //     southwestCoordinates = _secondPosition;
      //     northeastCoordinates = _firstPosition;
      //   }
      // }
      //
      // // Accomodate the two locations within the
      // // camera view of the map
      // mapController?.animateCamera(
      //   CameraUpdate.newLatLngBounds(
      //     LatLngBounds(
      //       northeast: northeastCoordinates!,
      //       southwest: southwestCoordinates!,
      //     ),
      //     100.0,
      //   ),
      // );

      // Calculating the distance between the start and the end positions
      // with a straight path, without considering any route
      double distanceInMeters = Geolocator.bearingBetween(
        _firstPosition!.latitude,
        _firstPosition!.longitude,
        _secondPosition!.latitude,
        _secondPosition!.longitude,
      );

      await _createPolyline(
        _firstPosition!,
        _secondPosition!,
      );

      double totalDistance = 0.0;

      // Calculating the total distance by adding the distance
      // between small segments
      for (int i = 0; i < polylineCoordinates.length - 1; i++) {
        totalDistance += _coordinateDistance(
          polylineCoordinates[i].latitude,
          polylineCoordinates[i].longitude,
          polylineCoordinates[i + 1].latitude,
          polylineCoordinates[i + 1].longitude,
        );
      }

      setState(() {
        _placeDistance = totalDistance.toStringAsFixed(2);
        print('DISTANCE: $_placeDistance km');
      });
      return true;
    } catch (e) {
      print(e);
      return false;
    }
    return false;
  }

  // Formula for calculating distance between two coordinates
  // https://stackoverflow.com/a/54138876/11910277
  double _coordinateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  List<PointLatLng> _decodeEncodedPolyline(String encoded) {
    List<PointLatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;
      PointLatLng p =
          PointLatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble());
      poly.add(p);
    }
    return poly;
  }

  // Create the polyline for showing the route between two places
  Future<void> _createPolyline(LatLng start, LatLng destination) async {
    try {
      List<LngLat> waypoints = [
        LngLat(lng: start.longitude, lat: start.latitude),
        LngLat(lng: destination.longitude, lat: destination.latitude),
      ];
      final manager = OSRMManager();
      final road = await manager.getRoad(
        waypoints: waypoints,
        geometries: Geometries.polyline,
        steps: true,
        language: Languages.en,
      );
      List<PointLatLng> result =
          _decodeEncodedPolyline(road.polylineEncoded ?? "");

      for (var point in result) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }

      PolylineId id = const PolylineId('poly');
      Polyline polyline = Polyline(
        polylineId: id,
        color: Colors.red,
        points: polylineCoordinates,
        width: 3,
      );
      polylines[id] = polyline;
    } catch (e) {
      print(">>>>>>>>>>>>>>>>> $e");
    }
  }

  /// Separate UI with logic function
  /// *********************************************

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  Widget build(BuildContext context) {
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    return _buildBody(height, width, context);
  }

  SizedBox _buildBody(double height, double width, BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: <Widget>[
            _buildMap(),
            _zoomButton(),
            _buildActionContainer(width, context),
            _buildBtnCurrentLocation(),
          ],
        ),
      ),
    );
  }

  GoogleMap _buildMap() {
    return GoogleMap(
            markers: markers,
            initialCameraPosition: _initialLocation,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            zoomGesturesEnabled: true,
            zoomControlsEnabled: false,
            polylines: Set<Polyline>.of(polylines.values),
            onMapCreated: (GoogleMapController controller) {
              mapController = controller;
            },
            onTap: (position) {
              _addMarker(position);
            },
          );
  }

  SafeArea _buildBtnCurrentLocation() {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 10.0, bottom: 10.0),
          child: ClipOval(
            child: Material(
              color: Colors.orange[100], // button color
              child: InkWell(
                splashColor: Colors.orange, // inkwell color
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.my_location),
                ),
                onTap: () {
                  mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: LatLng(
                          _currentPosition?.latitude ?? 0.0,
                          _currentPosition?.longitude ?? 0.0,
                        ),
                        zoom: 15.0,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  SafeArea _zoomButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 10.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ClipOval(
              child: Material(
                color: Colors.blue[100], // button color
                child: InkWell(
                  splashColor: Colors.blue, // inkwell color
                  child: const SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(Icons.add),
                  ),
                  onTap: () {
                    mapController?.animateCamera(
                      CameraUpdate.zoomIn(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            ClipOval(
              child: Material(
                color: Colors.blue[100], // button color
                child: InkWell(
                  splashColor: Colors.blue, // inkwell color
                  child: const SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(Icons.remove),
                  ),
                  onTap: () {
                    mapController?.animateCamera(
                      CameraUpdate.zoomOut(),
                    );
                  },
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  SafeArea _buildActionContainer(double width, BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white70,
              borderRadius: BorderRadius.all(
                Radius.circular(20.0),
              ),
            ),
            width: width * 0.9,
            child: Padding(
              padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _textField(
                      label: 'Start',
                      hint: 'Choose starting point',
                      initialValue: _currentAddress ?? "",
                      prefixIcon: const Icon(Icons.looks_one),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.my_location),
                        onPressed: () {
                          _setCurrentAddressIsFirst();
                        },
                      ),
                      controller: firstAddressTextController,
                      width: width,
                      locationCallback: (String value) {
                        setState(() {
                          _firstAddress = value;
                        });
                      }),
                  const SizedBox(height: 10),
                  _textField(
                    label: 'Destination',
                    hint: 'Choose destination',
                    initialValue: '',
                    prefixIcon: const Icon(Icons.looks_two),
                    controller: secondAddressTextController,
                    width: width,
                    locationCallback: (String value) {
                      setState(() {
                        _secondAddress = value;
                      });
                    },
                    suffixIcon: const SizedBox(),
                  ),
                  const SizedBox(height: 10),
                  Visibility(
                    visible: _placeDistance == null ? false : true,
                    child: Text(
                      'DISTANCE: $_placeDistance km',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  ElevatedButton(
                    onPressed: (_firstAddress != '')
                        ? () async {
                            clearRoutePolyline();

                            _calculateDistance().then((isCalculated) {
                              if (isCalculated) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Distance Calculated Sucessfully'),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Error Calculating Distance'),
                                  ),
                                );
                              }
                            });
                          }
                        : null,
                    style: const ButtonStyle(
                        backgroundColor:
                            MaterialStatePropertyAll<Color>(Colors.red)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Show Route'.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 20.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String initialValue,
    required double width,
    required Icon prefixIcon,
    required Widget suffixIcon,
    required Function(String) locationCallback,
  }) {
    return SizedBox(
      width: width * 0.8,
      child: TextField(
        onChanged: (value) {
          locationCallback(value);
        },
        controller: controller,
        decoration: InputDecoration(
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          labelText: label,
          labelStyle: const TextStyle(color: Colors.black),
          suffixIconColor: Colors.black,
          prefixIconColor: Colors.black,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.black,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.all(15),
          hintText: hint,
        ),
      ),
    );
  }
}
