import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mapsindoors_googlemaps/mapsindoors.dart';

void main() {
  runApp(const MapsIndoorsDemoApp());
}

class MapsIndoorsDemoApp extends StatelessWidget {
  const MapsIndoorsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MapsIndoors Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // 'gettingstarted' is an alias for the demo api key
      home: const Map(
        apiKey: 'gettingstarted',
      ),
    );
  }
}

/// The widget that will contain the map
class Map extends StatefulWidget {
  const Map({super.key, required this.apiKey});
  final String apiKey;

  @override
  State<Map> createState() => _MapState();
}

class _MapState extends State<Map> {
  // We use the scaffold to construct a drawer for search results, and a bottomsheet for location details
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  PersistentBottomSheetController? _controller;

  late MapsIndoorsWidget _mapControl;

  // List used to populate the search results drawer
  List<MPLocation> _searchResults = [];
  // coordinate used as origin point for directions
  final _userPosition = MPPoint.withCoordinates(longitude: -77.03740973527613, latitude: 38.897389429704695, floorIndex: 0);
  RouteHandler? _routeHandler;

  @override
  void initState() {
    super.initState();
    loadMapsIndoors(widget.apiKey).then((error) {
      // if no error occured during loading, then we can start using the SDK
      if (error == null) {
        // do stuff like fetching locations
      }
    });
  }

  void onMapControlReady(MPError? error) async {
    if (error == null) {
      // Add a listener for location selection events, we do not want to stop the SDK from moving the camera, so we do not comsume the event
      _mapControl
        ..setOnLocationSelectedListener(onLocationSelected, false)
        ..goTo(await getDefaultVenue());
    } else {
      // if loading mapcontrol failed inform the user
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Map load failed: $error"),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // we change the titlebar into a searching widget
        title: SearchWidget(
          onSubmitted: search,
        ),
      ),
      // add a drawer that can display search results
      drawer: Drawer(
        child: Flex(
          direction: Axis.vertical,
          children: [
            Expanded(
              child: _searchResults.isNotEmpty
              ? ListView.builder(
                  itemBuilder: (ctx, i) {
                    return ListTile(
                      onTap: () {
                        // when clicking on a location in the search results we will close the drawer and open a bottom sheet with that locations details
                        _mapControl.selectLocation(_searchResults[i]);
                        _scaffoldKey.currentState?.closeDrawer();
                      },
                      title: Text(_searchResults[i].name),
                    );
                  },
                  itemCount: _searchResults.length,
                )
              :
              // show something if the search returned no results
              const Icon(
                Icons.search_off,
                color: Colors.black,
                size: 100.0,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            _mapControl = MapsIndoorsWidget(
              readyListener: onMapControlReady,
            ),
          ],
        ),
      ),
    );
  }

  /// make a query in MapsIndoors on the search text
  void search(String value) {
    // we should clear the search filter when the query is empty
    if (value.isEmpty) {
      _mapControl.clearFilter();
      setState(() {
        _searchResults = [];
      });
      return;
    }
    // make a query with the search text
    MPQuery query = (MPQueryBuilder()..setQuery(value)).build();
    // we just want to see the top 30 results, as not to be overwhelmed
    MPFilter filter = (MPFilterBuilder()..setTake(30)).build();

    // fetch all (max 30) locations that match the query
    getLocationsByQuery(query: query, filter: filter).then((locations) {
      if (locations != null && locations.isNotEmpty) {
        // show search results drawer
        setState(() {
          _searchResults = locations;
          _scaffoldKey.currentState?.openDrawer();
        });
        // filter the map to only show matches
        _mapControl.setFilterWithLocations(locations, MPFilterBehavior.DEFAULT);
      }
    }).catchError((err) {
      // handle the error, for now just show a snackbar
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Search failed: $err"),
        backgroundColor: Colors.red,
      ));
    });
  }

  /// enable livedata for availability, occupancy and position domains
  void enableLiveData() {
    _mapControl
      ..enableLiveData(LiveDataDomainTypes.availability.name)
      ..enableLiveData(LiveDataDomainTypes.occupancy.name)
      ..enableLiveData(LiveDataDomainTypes.position.name);
  }

  /// opens bottomsheet with details about the selected location
  void onLocationSelected(MPLocation? location) {
    // if no location is selected, close the sheet
    if (location == null) {
      _controller?.close();
      _controller = null;
      return;
    }
    // if an active route is displayed, remove it from view
    _routeHandler?.removeRoute();
    // show location details
    _controller = _scaffoldKey.currentState?.showBottomSheet((context) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.25,
        width: MediaQuery.of(context).size.width,
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 30,
            ),
            Text(location.name),
            const SizedBox(
              height: 30,
            ),
            Text("Description: ${location.description}"),
            const SizedBox(
              height: 30,
            ),
            Text("Building: ${location.buildingName} - ${location.floorName}"),
            const SizedBox(
              height: 30,
            ),
            // when clicked will create a route from the user position to the location
            ElevatedButton(
              onPressed: () => _routeHandler = RouteHandler(origin: _userPosition, destination: location.point, scaffold: _scaffoldKey.currentState!),
              child: const Row(
                children: [
                  Icon(Icons.keyboard_arrow_left_rounded),
                  SizedBox(
                    width: 5,
                  ),
                  Text("directions")
                ],
              ),
            ),
          ],
        ),
      );
    });
    _controller?.closed.then((value) => _mapControl.selectLocation(null));
  }
}

/// Encapsulates routing
class RouteHandler {
  RouteHandler({required MPPoint origin, required MPPoint destination, required ScaffoldState scaffold}) {
    _service.setTravelMode(MPDirectionsService.travelModeDriving);
    _service.getRoute(origin: origin, destination: destination).then((route) {
      _route = route;
      _renderer.setRoute(route);
      _renderer.setOnLegSelectedListener(onLegSelected);
      showRoute(scaffold);
    });
  }
  final _service = MPDirectionsService();
  final _renderer = MPDirectionsRenderer();
  PersistentBottomSheetController? _controller;
  late final MPRoute _route;
  // backing field for the current route leg index
  int _currentIndex = 0;

  // if the backing field is negative, return 0 as negative legs do no exist
  int get currentIndex {
    return _currentIndex < 0 ? 0 : _currentIndex;
  }

  // ensure that the new index does not go out of bounds
  set currentIndex(int index) {
    _currentIndex = min(index, _route.legs!.length - 1);
  }

  // updates the state of the routehandler if the route is updated externally, eg. by tapping the next marker on the route
  void onLegSelected(int legIndex) {
    _controller?.setState!(() => currentIndex = legIndex);
  }

  // opens the route on a bottom sheet
  void showRoute(ScaffoldState scaffold) {
    _controller = scaffold.showBottomSheet((context) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.35,
        width: MediaQuery.of(context).size.width,
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // goes a step back on the route
            IconButton(
              onPressed: () async {
                currentIndex--;
                await _renderer.selectLegIndex(currentIndex);
              },
              icon: const Icon(Icons.keyboard_arrow_left),
              iconSize: 50,
            ),
            // displays the route instructions
            Expanded(
              child: Text(
                expandRouteSteps(_route.legs![currentIndex].steps!),
                softWrap: true,
                textAlign: TextAlign.center,
              ),
            ),
            // goes a step forward on the route
            IconButton(
              onPressed: () async {
                currentIndex++;
                await _renderer.selectLegIndex(currentIndex);
              },
              icon: const Icon(Icons.keyboard_arrow_right),
              iconSize: 50,
            ),
          ],
        ),
      );
    });
    // if the bottom sheet is closed, then clear the route
    _controller?.closed.then((val) {
      _renderer.clear();
    });
  }

  // external handle to clear the route
  void removeRoute() {
    _renderer.clear();
    _controller?.close();
  }

  // expands the step instructions into a single string for the entire leg
  String expandRouteSteps(List<MPRouteStep> steps) {
    String sum = "${steps[0].maneuver}";
    for (final step in steps.skip(1)) {
      sum += ", ${step.maneuver}";
    }
    return sum;
  }
}

/// A search field widget that fits the app bar
class SearchWidget extends StatelessWidget {
  final Function(String val)? onSubmitted;
  const SearchWidget({
    super.key,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
          icon: Icon(
            Icons.search,
            color: Colors.white,
          ),
          hintText: "Search...",
          hintStyle: TextStyle(color: Colors.white)),
      cursorColor: Colors.white,
      style: const TextStyle(color: Colors.white),
      onSubmitted: onSubmitted,
    );
  }
}
