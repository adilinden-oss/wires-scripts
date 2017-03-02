/*
 * Create a Google Map with Markers
 *
 * by Adi Linden <adi@adis.ca>
 *
 * Uses the following:
 *
 *   - Google Maps API v3
 *     https://developers.google.com/maps/documentation/javascript/tutorial
 *   - MarkerClusterer for Google Maps v3
 *     https://github.com/googlemaps/v3-utility-library/tree/master/markerclusterer
 *     https://developers.google.com/maps/documentation/javascript/marker-clustering
 *
 * Usage information:
 *
 *   The following http GET variables are supported:
 *
 *     style        'plain' displays a plain map with many markers.
 *                  'cluster' enables the MarkerClusterer features.                  
 *     userid       a provided userid is matched in markers array and
 *                  zoomed into.
 *     zoom         a zoom level (f provided) is used to zoom into the
 *                  marker specified by userid.
 */

// Define maximum zoom level for clusterer to cluster and zoom on click
var maxZoom = 17;

// Define minimu zoom level allowed, this avoids scroll wheel "going crazy"
var minZoom = 2;

var markerIcon = {
    /*
    red:    'http://maps.google.com/mapfiles/ms/icons/red-dot.png',
    yellow: 'http://maps.google.com/mapfiles/ms/icons/yellow-dot.png',
    blue:   'http://maps.google.com/mapfiles/ms/icons/blue-dot.png',
    green:  'http://maps.google.com/mapfiles/ms/icons/green-dot.png',
    ltblue: 'http://maps.google.com/mapfiles/ms/icons/ltblue-dot.png',
    orange: 'http://maps.google.com/mapfiles/ms/icons/orange-dot.png',
    pink:   'http://maps.google.com/mapfiles/ms/icons/pink-dot.png',
    purple: 'http://maps.google.com/mapfiles/ms/icons/purple-dot.png',
    */
    red:    'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,FF0000,000000&ext=.png',
    yellow: 'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,FFFF00,000000&ext=.png',
    blue:   'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,0000FF,000000&ext=.png',
    green:  'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,00FF00,000000&ext=.png',
    ltblue: 'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,008CFF,000000&ext=.png',
    orange: 'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,F0762d,000000&ext=.png',
    pink:   'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,FF1493,000000&ext=.png',
    purple: 'http://chart.apis.google.com/chart?cht=mm&chs=24x32&chco=' +
            'FFFFFF,800080,000000&ext=.png',
};
var map;
var markers = [];

function initMap() {

    // Create map
    map = new google.maps.Map(document.getElementById('map'), {
        mapTypeId: google.maps.MapTypeId.ROADMAP,
        zoom: 5,
        center: new google.maps.LatLng(mapData.node.lat, mapData.node.lng),
    });

    // Define variables used by each marker
    var info = new google.maps.InfoWindow();
    var bound = new google.maps.LatLngBounds();

    // Create marker array
    setMarker(map, info, bound, mapData.node);
    setMarkers(map, info, bound, mapData.user);

    // Is clusterer requested via GET variable?
    var mapStyle = String(getUrlVars()["style"]);

    if (mapStyle != null && mapStyle == "cluster") {
        
        // Add marker clusterer to manage the markers.
        var markerCluster = new MarkerClusterer(map, markers, {
            imagePath: 'mapcluster.d/m',
            maxZoom: maxZoom,
        });

        // Limit marker clusterer zoom on click
        google.maps.event.addListener(markerCluster, 'clusterclick', function(cluster){
            if (markerCluster.isZoomOnClick()) {
                map.fitBounds(cluster.getBounds());
                if (map.getZoom() > markerCluster.getMaxZoom()) map.setZoom(markerCluster.getMaxZoom()+1);
            }
        });

        // Hide the panel, clusterer declutters instead
        document.getElementById('panel').style.visibility='hidden';
    }

    // Limit how far out can be zoomed
    google.maps.event.addListener(map, 'zoom_changed', function() {
        if (map.getZoom() < minZoom) map.setZoom(minZoom);
    });

    // Adjust center and zoom level
    zoomCall(map, bound);
}

function setMarker(map, info, bound, pin) {
    var marker = new google.maps.Marker({
        position: new google.maps.LatLng(pin.lat, pin.lng),
        map: map,
        title: pin.user_id,
        description: "<b>"+pin.user_id+"</b><br>This Node<br>"+pin.call+"("+pin.number+")",
        age: pin.age,
    });

    google.maps.event.addListener(marker, "click", function () {
        info.setContent(this.description);
        info.open(map, this);                
    });

    marker.setIcon(markerIcon.red);
    bound.extend(marker.position);
    markers.push(marker);
}

function setMarkers(map, info, bound, pins) {
    for (var i = 0; i < pins.length; i++) {
        var marker = new google.maps.Marker({
            position: new google.maps.LatLng(pins[i].lat, pins[i].lng),
            map: map,
            title: pins[i].user_id,
            description: "<b>"+pins[i].user_id+"</b><br>"+pins[i].distance+" km<br>"+pins[i].heard+"<br>"+pins[i].posit+"",
            age: pins[i].age,
        });

        google.maps.event.addListener(marker, "click", function () {
            info.setContent(this.description);
            info.open(map, this);                
        });

        if (pins[i].channel == "V-CH") {
            marker.setIcon(markerIcon.green);
        } else {
            marker.setIcon(markerIcon.blue);
        }
        bound.extend(marker.position);
        markers.push(marker);
    }
}

function zoomCall(map, bound) {

    // Get http request GET variables for user_id and zoom
    var userid = String(getUrlVars()["userid"]);
    var zoom = parseInt(getUrlVars()["zoom"]);

    // Zoom into user_id if found in marker array
    if (userid != null && userid.length > 0) {
        // Find userid in markers array
        for (var i = 0; i < markers.length; i++) {
            if (markers[i].title == userid) {
                // Center map on userid
                map.setCenter(markers[i].position);
                // Set zoom for matched userid
                if (zoom != null && zoom > 0) {
                    map.setZoom(zoom);
                } else {
                    map.setZoom(maxZoom + 1);
                }
                // Map is all setup, get out
                return;
            }
        }

    }

    // Must not have found call zoom to fit all markers
    map.fitBounds(bound);
}

function toggleMarkers(map, age) {
    for (var i = 0; i < markers.length; i++) {
        if (markers[i].age < age) {
            markers[i].setMap(map);
        } else {
            markers[i].setMap(null);
        }
    }
}

// Turn on all markers (one year should suffice)
function allMarkers() {
    toggleMarkers(map, 60*60*24*365)
}

function thirtyMarkers() {
    toggleMarkers(map, 60*60*24*30)
}

function tenMarkers() {
    toggleMarkers(map, 60*60*24*10)
}

function sevenMarkers() {
    toggleMarkers(map, 60*60*24*7)
}

function twoMarkers() {
    toggleMarkers(map, 60*60*48)
}

function oneMarkers() {
    toggleMarkers(map, 60*60*24)
}

function getUrlVars() {
    // Shamelessly copied from http://papermashup.com/read-url-get-variables-withjavascript/
    //
    // http://papermashup.com/index.php?id=123&page=home
    //
    //      var first = getUrlVars()["id"];
    //      var second = getUrlVars()["page"];
    //
    //      alert(first);
    //      alert(second);
    //
    var vars = {};
    var parts = window.location.href.replace(/[?&]+([^=&]+)=([^&]*)/gi, function(m,key,value) {
        vars[key] = value;
    });
    return vars;
}
